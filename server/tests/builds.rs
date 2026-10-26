use vssjx_server::{attributes,builds,loot,shop,skills,pve_rules::Stats};
use uuid::Uuid;
fn template(job:i16,slot:&str)->String{shop::ITEMS.iter().find(|d|d.equipment()&&d.slot==slot&&d.equip_error(job,0).is_none()).unwrap().id.clone()}
fn gear(index:usize,legend:bool,count:usize)->loot::State{
    let d=&builds::DATA["items"][index];let id=d["id"].as_str().unwrap();let job=d["job"].as_i64().unwrap() as i16;let mut state=loot::State::default();
    let mut add=|slot:&str,q:&str|{let mut item=loot::roll_special(&template(job,slot),60,q,id,17,Uuid::new_v4()).unwrap();item.equipped=true;item.bound=true;state.items.push(item);};
    if legend{add(d["legend_slot"].as_str().unwrap(),"orange");}
    for slot in builds::DATA["set_slots"].as_array().unwrap().iter().take(count){add(slot.as_str().unwrap(),"green");}
    state
}
fn stats(index:usize,legend:bool,count:usize)->Stats{let state=gear(index,legend,count);let job=builds::DATA["items"][index]["job"].as_i64().unwrap() as i16;let mut stats=attributes::balanced_stats(job,60,false,[0;5]);state.apply_stats(&mut stats,job);stats}
fn cast(s:Stats,state:&mut skills::State,id:&str)->(i32,i32,i32){state.reset_turn();let mut hp=s.hp/2;let mut mp=s.mp;let damage=state.cast(skills::item(id).unwrap(),s,&mut hp,&mut mp,100,0);(damage,hp,mp)}
#[test]
fn six_styles_activate_at_exact_two_and_four_thresholds_without_legacy_conversion(){
    for i in 0..6{let job=builds::DATA["items"][i]["job"].as_i64().unwrap() as i16;
        for count in 0..=4{for legend in [false,true]{let gear=gear(i,legend,count);assert!(gear.valid(job,0));let s=stats(i,legend,count);assert_eq!(s.balance.unwrap().builds.tier(i),usize::from(legend)+usize::from(count==4));
            let loaded:Stats=serde_json::from_value(serde_json::to_value(s).unwrap()).unwrap();assert_eq!(loaded.balance.unwrap().builds.tier(i),s.balance.unwrap().builds.tier(i));
        }}
    }
    let s=attributes::balanced_stats(0,60,false,[0;5]);assert!(!serde_json::to_string(&s).unwrap().contains("builds"));
    assert!(loot::roll_special(&template(2,"weapon"),60,"orange","rend",1,Uuid::new_v4()).is_err());
    assert!(loot::roll_special(&template(0,"armor"),60,"orange","rend",1,Uuid::new_v4()).is_err());
    let mut bad=gear(0,true,0);bad.items[0].legendary=Some("focus".into());assert!(!bad.valid(0,0));
}
#[test]
fn rampart_requires_setup_consumes_one_charge_and_cannot_resurrect(){
    for (legend,pieces,tier) in [(true,0,1),(false,4,1),(true,4,2)]{
        let s=stats(0,legend,pieces);let mut state=skills::State::default();let baseline=cast(s,&mut state,"sheet_010").0;
        cast(s,&mut state,"sheet_012");let (hit,hp,_)=cast(s,&mut state,"sheet_010");assert_eq!(hit,baseline*(if tier==1{13000}else{14500})/10000);assert!(hp>s.hp/2);assert_eq!(state.builds.as_ref().unwrap().charges[0],0);
        assert_eq!(cast(s,&mut state,"sheet_010").0,baseline);
        cast(s,&mut state,"sheet_012");state.reset_turn();let mut hp=0;let mut mp=s.mp;state.cast(skills::item("sheet_010").unwrap(),s,&mut hp,&mut mp,100,0);assert_eq!(hp,0);
    }
}
#[test]
fn bleed_is_faster_and_team_aoe_setup_is_consumed_once_per_action(){
    let s=stats(1,true,4);let mut fx=skills::State::default();cast(s,&mut fx,"sheet_025");assert_eq!(fx.enemy_bleed,2);assert_eq!(fx.bleed_damage,attributes::dot_damage(s,100,3000)*2);
    let s=stats(2,true,4);let mut fx=skills::State::default();cast(s,&mut fx,"sheet_003");cast(s,&mut fx,"sheet_003");assert_eq!(fx.builds.as_ref().unwrap().charges[2],2);
    fx.reset_turn();fx.balance.as_mut().unwrap().targets=5;let mut hp=s.hp/2;let mut mp=s.mp;
    let first=fx.cast(skills::item("sheet_004").unwrap(),s,&mut hp,&mut mp,100,0);let after=fx.builds.clone().unwrap();let second=fx.cast(skills::item("sheet_004").unwrap(),s,&mut hp,&mut mp,100,0);
    assert_eq!(first,second);assert_eq!(after.charges,fx.builds.as_ref().unwrap().charges);assert_eq!(after.bonus_bp,3600);assert_eq!(after.charges[2],0);
}
#[test]
fn poison_sleep_synergy_respects_control_protection_and_keeps_dot_clock(){
    let s=stats(3,true,4);let mut fx=skills::State::default();cast(s,&mut fx,"sheet_052");let tick=fx.poison_damage;
    let expected=attributes::direct_damage(s,100,6000,0);let (hit,_,_)=cast(s,&mut fx,"sheet_051");assert_eq!(hit,expected+tick*2);assert_eq!(fx.enemy_poison,3);assert_eq!(fx.enemy_sleep,1);
    let (hit,_,_)=cast(s,&mut fx,"sheet_051");assert_eq!(hit,expected,"Control immunity prevents the proc even when poisoned");
}
#[test]
fn mage_setup_and_mana_steal_change_the_followup_not_turn_count(){
    let s=stats(4,true,4);let mut fx=skills::State::default();let baseline=cast(s,&mut fx,"sheet_017").0;
    cast(s,&mut fx,"sheet_039");let (hit,_,mp)=cast(s,&mut fx,"sheet_017");assert_eq!(hit,baseline*14500/10000);assert_eq!(mp,s.mp-vssjx_server::skill_balance::cost(skills::item("sheet_017").unwrap(),s)+s.mp*500/10000);
    let s=stats(5,true,4);let mut fx=skills::State::default();fx.enemy_mp=40;let (_,hp,_)=cast(s,&mut fx,"sheet_047");assert!(hp>s.hp/2);assert_eq!(fx.enemy_mp,20);
    cast(s,&mut fx,"sheet_018");assert_eq!(fx.bleed_damage,attributes::dot_damage(s,100,3000)*16000/10000);assert_eq!(fx.builds.as_ref().unwrap().charges[5],0);
    let mut old=s;old.balance.as_mut().unwrap().builds=Default::default();let mut fx=skills::State::default();cast(old,&mut fx,"sheet_039");assert!(fx.builds.is_none(),"Frozen old snapshot never reads newly equipped artifacts");
}
#[test]
fn ally_support_only_primes_the_caster_and_preserves_shared_command_round(){
    use vssjx_server::{team_rules::{Battle,Fighter},population};
    let s=stats(4,true,4);
    let fighters:Vec<_>=(0..2).map(|_|Fighter{id:Uuid::new_v4(),name:"凝元验证".into(),job:2,gender:0,school:3,level:60,appearance:[0;3],stats:s,hp:s.hp/2,mp:s.mp,potions:3,effects:skills::State::new(2,3,60,60),guarding:false}).collect();
    let ids=[fighters[0].id,fighters[1].id];let enemy=population::definitions().into_iter().find(|d|d.id=="wolf_a").unwrap();
    let mut battle=Battle::new("qingyun_trail".into(),fighters,vec![enemy],1000);
    let now=battle.selection_starts_ms+1;
    battle.act(ids[0],"skill",None,Some("sheet_041"),now,99).unwrap();
    assert!(battle.fighters[0].effects.builds.is_none(),"Commands are collected before executing anyone");
    battle.act(ids[1],"guard",None,None,now,99).unwrap();
    assert_eq!(battle.fighters[0].effects.builds.as_ref().unwrap().charges[4],1);
    assert!(battle.fighters[1].effects.builds.is_none(),"Receiving another player's heal is not casting a setup skill");
}
#[test]
fn duels_apply_the_separate_healing_budget_to_legendary_lifesteal(){
    use vssjx_server::duel::{Arena,Command,Fighter};use std::time::Instant;
    let s=stats(1,true,4);
    for _ in 0..16{
        let now=Instant::now();let make=||Fighter{id:Uuid::new_v4(),name:"汲血验证".into(),job:0,gender:0,school:3,level:60,speed:100,stats:s,appearance:[0;3],hp:s.hp/2,mp:s.mp,effects:skills::State::new(0,3,60,60),guarding:false};
        let a=make();let mut b=make();b.effects.passive_physical=0;b.effects.passive_magic=0;let ids=[a.id,b.id];let mut arena=Arena::default();let offer=arena.invite(a.id,b.id,a.name.clone(),b.name.clone(),now).unwrap();let id=arena.start(offer,b.id,[a,b],now).unwrap();
        let c=|action:&str,skill:Option<&str>|Command{request_id:Uuid::new_v4(),action:action.into(),target:None,invite_id:None,battle_id:Some(id),expected_revision:Some("0".into()),skill:skill.map(str::to_owned)};
        arena.act(ids[0],&c("skill",Some("sheet_025")),now,[99;3]).unwrap();arena.act(ids[1],&c("guard",None),now,[99;3]).unwrap();
        let b=&arena.battles[&id];let event=b.events.iter().find(|e|e.actor==ids[0]).unwrap();if event.missed{continue;}
        let heal=(s.hp*500/10000)*6000/10000;
        assert_eq!(b.fighters[0].hp,s.hp/2+heal);assert_eq!(b.fighters[0].effects.last_healed,heal);return;
    }
    panic!("No successful hit in sixteen independent trials");
}
