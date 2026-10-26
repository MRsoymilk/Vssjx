//! Integrated live party engine and authored AI encounters. Hit RNG stays authoritative.
use vssjx_server::{attributes,builds,loot,population::ResidentDefinition,shop,skills,skill_balance,team_rules::{Battle,Fighter},progression};
use serde_json::{Value,json};use uuid::Uuid;
fn gear(job:i16,index:usize,level:i32,stage:i32)->loot::State{
    let mut gear=loot::State::default();if stage==0{return gear;}
    let build=builds::DATA["items"][index]["id"].as_str().unwrap();
    for (n,slot) in shop::SLOTS.iter().enumerate(){
        let template=shop::ITEMS.iter().find(|d|d.equipment()&&d.slot==*slot&&d.equip_error(job,0).is_none()).unwrap();
        let special=stage>=2;let quality=if special&&builds::compatible(build,job,slot,true){"orange"}else if special&&builds::compatible(build,job,slot,false){"green"}else{"yellow"};
        let seed=17+n as u32*7919;
        let mut item=if matches!(quality,"orange"|"green"){loot::roll_special(&template.id,level,quality,build,seed,Uuid::new_v4()).unwrap()}else{loot::roll(&template.id,level,quality,seed,Uuid::new_v4()).unwrap()};
        item.equipped=true;item.bound=true;if stage==3{item.upgrade=6;}gear.items.push(item);
    }gear
}
fn rotation(b:&Battle,i:usize,style:usize)->(&'static str,Option<&'static str>){
    let f=&b.fighters[i];if f.hp<f.stats.hp/3&&f.potions>0{return ("potion",None);}
    let e=b.enemies.iter().find(|e|e.hp>0).unwrap();let charges=f.effects.builds.as_ref().map(|p|p.charges).unwrap_or([0;6]);
    let preferred=match style{
        0=>if charges[0]==0&&f.effects.defense==0{"sheet_012"}else{"sheet_010"},
        1=>if e.effects.enemy_bleed==0{"sheet_025"}else{"sheet_010"},
        2=>if charges[2]>=2{"sheet_004"}else{"sheet_003"},
        3=>if e.effects.enemy_poison==0{"sheet_052"}else if e.effects.balance.as_ref().is_none_or(|b|b.control_protection==0){"sheet_051"}else{"sheet_003"},
        4=>if charges[4]==0&&f.effects.regen==0{"sheet_039"}else{"sheet_017"},
        _=>if charges[5]==0&&e.effects.enemy_mp>0{"sheet_047"}else if charges[5]>0||e.effects.enemy_bleed==0{"sheet_018"}else{"sheet_017"}
    };
    let fallback=["sheet_010","sheet_003","sheet_017"][f.job as usize];
    for id in [preferred,fallback]{let s=skills::item(id).unwrap();if skills::eligible(s,f.job,3,f.level)&&f.effects.remaining(id)==0&&f.mp>=skill_balance::cost(s,f.stats){return ("skill",Some(id));}}
    ("attack",None)
}
fn main(){
    let world:Value=serde_json::from_str(include_str!("../../shared/data/ai-world-v1.json")).unwrap();let mut rows=vec![];let trials=60;
    for map_id in ["ai_054","ai_061","ai_091"]{let map=world["maps"].as_array().unwrap().iter().find(|m|m["map_id"]==map_id).unwrap();let mobs:Vec<ResidentDefinition>=map["residents"].as_array().unwrap().iter().filter(|r|r["kind"]!="npc").map(|r|serde_json::from_value(r.clone()).unwrap()).collect();
    for level in [mobs[0].level,60]{for style in 0..6{let job=builds::DATA["items"][style]["job"].as_i64().unwrap() as i16;
    for stage in 0..4{let equipment=gear(job,style,level,stage);let mut stats=attributes::balanced_stats(job,level,false,attributes::balanced_recommended(job,level,[0;5]));if stage==0{attributes::gear_bonus(&mut stats,14,27);}equipment.apply_stats(&mut stats,job);
    for party in [1,3,5]{for kind in ["ordinary","elite","boss"]{let mut wins=0;let mut rounds=0;let mut health=0;let mut mana=0;let mut potions=0;
        for trial in 0..trials{
            let fighters:Vec<_>=(0..party).map(|_|Fighter{id:Uuid::new_v4(),name:"综合验证".into(),job,gender:0,school:3,level,appearance:[0;3],stats,hp:stats.hp,mp:stats.mp,potions:3,effects:skills::State::new(job,3,level,level),guarding:false}).collect();
            let mut sources=vec![if kind=="boss"{mobs.iter().find(|d|d.kind=="boss").unwrap().clone()}else{mobs[0].clone()}];
            for n in 1..party{let mut d=mobs[0].clone();d.id=format!("simulation_{n}");sources.push(d);}
            let mut b=Battle::new(map_id.into(),fighters,sources,1000);if kind=="elite"{b.empower_hunt();}
            while b.active()&&b.round<=30{
                let target=b.enemies.iter().find(|e|e.hp>0).unwrap().slot.clone();let now=b.selection_starts_ms+1;
                let intents:Vec<_>=(0..b.fighters.len()).filter(|i|b.fighters[*i].hp>0).map(|i|{let (action,skill)=rotation(&b,i,style);(b.fighters[i].id,action,skill)}).collect();
                for (who,action,skill) in intents{
                    if !b.active(){break;}let directed=skill.map(|id|matches!(skills::item(id).unwrap().target.as_str(),"enemy"|"all_enemies")).unwrap_or(action=="attack");
                    b.act(who,action,if directed{Some(&target)}else{None},skill,now,(trial*37+b.round as i32*19)%100).unwrap();
                }
            }
            if b.outcome=="victory"{wins+=1;}rounds+=b.round as i32-1;
            health+=b.fighters.iter().map(|f|f.hp).sum::<i32>();mana+=b.fighters.iter().map(|f|f.mp).sum::<i32>();potions+=b.fighters.iter().map(|f|3-f.potions).sum::<i32>();
        }
        // Starter fixed gear is intentionally measured, not assumed sufficient
        // for every elite. Report losses before selecting acceptance thresholds.
        if stage>=1{assert!(wins>=trials*95/100,"Completed rolled-gear regression: map={map_id} level={level} style={style} stage={stage} party={party} kind={kind} wins={wins}/{trials}");}
        rows.push(json!({"map":map_id,"level":level,"style":builds::DATA["items"][style]["id"],"gear_stage":stage,"party":party,"encounter":kind,"trials":trials,"wins":wins,"mean_rounds":rounds as f64/trials as f64,"mean_hp_percent":health as f64/(trials*party*stats.hp) as f64*100.0,"mean_mp_percent":mana as f64/(trials*party*stats.mp) as f64*100.0,"mean_potions":potions as f64/(trials*party) as f64}));
    }}}}}}
    let mut economies=vec![];
    let economy_map=world["maps"].as_array().unwrap().iter().find(|m|m["map_id"]=="ai_091").unwrap();
    let income=|boss:bool|economy_map["residents"].as_array().unwrap().iter().find(|r|if boss{r["kind"]=="boss"}else{r["kind"]=="wolf"}).unwrap()["gold"].as_i64().unwrap() as i32;
    for party in [1,3,5]{let mut source=loot::State::default();let mut s=loot::State::default();let mut gold=0;let mut count=0;let mut pool_count=0;let mut dice=loot::Dice(1717);let mut qualities=std::collections::BTreeMap::<String,i32>::new();
        for n in 0..1000{let boss=n%5==0;source.reward(1,0,60,boss,0,(17+n*7919) as u32);progression::credit(&mut s,boss);gold+=(income(boss)+party-1)/party;
            let common=std::mem::take(&mut source.items);pool_count+=common.len();
            // Same-class, equal eligibility, everybody rolls: each character's
            // chance of winning an item is 1/party, including fair tie-breaks.
            for item in common{if dice.next(party as usize)!=0{continue;}count+=1;*qualities.entry(item.quality.clone()).or_default()+=1;let id=item.id;s.items.push(item);progression::craft(&mut s,id,"gear_salvage",None,&mut gold,0).unwrap();}
        }
        let base=loot::roll("sword",60,"yellow",17,Uuid::new_v4()).unwrap();let id=base.id;s.items.push(base);let before=(gold,s.scrap,s.essence);
        for _ in 0..6{progression::craft(&mut s,id,"gear_upgrade",None,&mut gold,0).unwrap();}
        economies.push(json!({"party":party,"wins":1000,"bosses":200,"pool_drops":pool_count,"awarded_drops":count,"allocation":"same class, everybody rolls, seeded uniform fair-share simulation","qualities":qualities,"gold_income":before.0,"scrap_income":before.1,"essence_income":before.2,"upgrade_to_6_cost":[before.0-gold,before.1-s.scrap,before.2-s.essence]}));
    }
    println!("{}",json!({"engine":"actual team_rules::Battle and authored AI templates; seeded intents, authoritative independent hit RNG (not fully seeded)","total_fights":rows.len()*trials as usize,"results":rows,"economy":economies}));
}
