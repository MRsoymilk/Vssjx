//! Bounded loot/crafting economy. Callers own the receipt/save transaction.
use crate::{loot::{self,State,Item,Dice},shop,builds};
use serde_json::Value;
use sha2::{Digest,Sha256};
use std::sync::LazyLock;
use uuid::Uuid;
pub static DATA:LazyLock<Value>=LazyLock::new(||serde_json::from_str(include_str!("../../shared/data/progression-v1.json")).unwrap());
pub static HASH:LazyLock<String>=LazyLock::new(||format!("{:x}",Sha256::digest(include_str!("../../shared/data/progression-v1.json").replace("\r\n","\n").as_bytes())));
pub fn n(key:&str)->i32{DATA[key].as_i64().unwrap() as i32}
pub fn monster(mut d:crate::population::ResidentDefinition)->crate::population::ResidentDefinition{
    if d.kind=="boss"||d.id=="boss"{d.hp=(i64::from(d.hp)*i64::from(n("boss_hp_budget_bp"))/10000) as i32;}d
}
pub fn quote(item:&Item,action:&str)->Result<[i32;3],&'static str>{
    if item.legacy{return Err("LEGACY_CRAFT_LOCKED");}
    match action{
        "gear_upgrade"=>{let next=item.upgrade+1;if next>n("max_upgrade"){return Err("UPGRADE_LIMIT");}Ok([item.level*next*n("upgrade_gold_per_level"),next*n("upgrade_scrap"),i32::from(next>=n("upgrade_essence_from"))])},
        "gear_reroll"=>{if item.affixes.is_empty(){return Err("NO_AFFIXES");}if item.rerolls>=n("max_rerolls"){return Err("REROLL_LIMIT");}Ok([item.level*(item.rerolls+1)*n("reroll_gold_per_level"),n("reroll_scrap_base")+item.rerolls,i32::from(item.legendary.is_some()||item.set_id.is_some())])},
        _=>Err("INVALID_LOOT_COMMAND")
    }
}
pub fn craft(state:&mut State,id:Uuid,action:&str,index:Option<usize>,gold:&mut i32,seed:u32)->Result<(),&'static str>{
    let pos=state.items.iter().position(|i|i.id==id).ok_or("INSTANCE_NOT_OWNED")?;
    let item=&state.items[pos];if item.legacy{return Err("LEGACY_CRAFT_LOCKED");}
    if action=="gear_salvage"{
        if index.is_some(){return Err("INVALID_LOOT_COMMAND");}if item.equipped{return Err("UNEQUIP_BEFORE_SALVAGE");}
        state.scrap=(state.scrap+DATA["salvage_scrap"][&item.quality].as_i64().unwrap() as i32).min(1000000000);
        state.essence=(state.essence+DATA["salvage_essence"][&item.quality].as_i64().unwrap() as i32).min(1000000000);
        state.skins.insert(item.template.clone());state.items.remove(pos);return Ok(());
    }
    let cost=quote(item,action)?;
    if action=="gear_reroll"{
        let index=index.ok_or("INVALID_AFFIX_INDEX")?;
        if index>=item.affixes.len(){return Err("INVALID_AFFIX_INDEX");}
        if item.reroll_index.is_some_and(|locked|locked!=index){return Err("REROLL_SLOT_LOCKED");}
    }else if index.is_some(){return Err("INVALID_LOOT_COMMAND");}
    if *gold<cost[0]{return Err("GOLD_INSUFFICIENT");}if state.scrap<cost[1]||state.essence<cost[2]{return Err("MATERIALS_INSUFFICIENT");}
    let item=&mut state.items[pos];
    if action=="gear_upgrade"{item.upgrade+=1;}else{
        let index=index.unwrap();let mut dice=Dice(seed);
        let pool:Vec<_>=loot::DATA["pools"][item.slot()].as_array().unwrap().iter().filter_map(Value::as_str).filter(|kind|!item.affixes.iter().enumerate().any(|(j,a)|j!=index&&a.kind==*kind)&&*kind!=item.affixes[index].kind).collect();
        let kind=pool[dice.next(pool.len())];let (lo,hi)=loot::range(kind,item.level).unwrap();
        item.affixes[index]=loot::Affix{kind:kind.into(),value:lo+dice.next((hi-lo+1) as usize) as i32};item.reroll_index=Some(index);item.rerolls+=1;
    }
    *gold-=cost[0];state.scrap-=cost[1];state.essence-=cost[2];Ok(())
}
pub fn reward(state:&mut State,_job:i16,_gender:i16,level:i32,boss:bool,bag_count:usize,seed:u32)->Vec<Uuid>{
    // Challenge admission reserves room for the entire encounter, not each kill.
    assert!(state.can_fight(),"loot storage must be reserved before combat");
    let mut dice=Dice(seed);credit(state,boss);
    if !boss&&dice.next(100)>=n("normal_drop_percent") as usize&&state.kills%n("normal_pity")!=0{return vec![];}
    let mut used=bag_count;let mut ids=vec![];
    for drop in 0..if boss{n("boss_drops")}else{1}{
        let pity=boss&&drop==0&&state.bosses%n("boss_pity")==0&&level>=n("min_special_level");
        // Drop class is random, never the recipient's class or gender. Old focus is ignored.
        let job=dice.next(3) as i16;
        let mut slot=shop::SLOTS[dice.next(shop::SLOTS.len())];
        let roll=dice.next(100);let mut total=0;let mut quality="yellow";
        for q in ["white","blue","yellow","orange","green"]{total+=DATA[if boss{"boss_weights"}else{"normal_weights"}][q].as_u64().unwrap_or(0) as usize;if roll<total{quality=q;break;}}
        if pity{quality=if dice.next(2)==0{"orange"}else{"green"};}
        if level<n("min_special_level")&&matches!(quality,"orange"|"green"){quality="yellow";}
        let mut specials:Vec<_>=builds::DATA["items"].as_array().unwrap().iter().filter(|b|builds::compatible(b["id"].as_str().unwrap(),job,slot,quality=="orange")).collect();
        if matches!(quality,"orange"|"green")&&specials.is_empty(){
            if pity{
                let choices:Vec<_>=builds::DATA["items"].as_array().unwrap().iter().filter(|b|b["job"]==job).collect();let b=choices[dice.next(choices.len())];
                slot=if quality=="orange"{b["legend_slot"].as_str().unwrap()}else{builds::DATA["set_slots"][dice.next(4)].as_str().unwrap()};
            }else{quality=if quality=="orange"{"green"}else{"orange"};}
            specials=builds::DATA["items"].as_array().unwrap().iter().filter(|b|builds::compatible(b["id"].as_str().unwrap(),job,slot,quality=="orange")).collect();
            if specials.is_empty(){quality="yellow";}
        }
        // Choose art independently of the recipient and catalog family sizes.
        let source=if dice.next(100)<n("original_appearance_percent") as usize{"original/"}else{"ai/"};
        let candidates:Vec<_>=shop::ITEMS.iter().filter(|d|d.equipment()&&d.slot==slot&&(d.job<0||d.job==job)&&d.id.starts_with(source)).collect();
        let candidates=if candidates.is_empty(){shop::ITEMS.iter().filter(|d|d.equipment()&&d.slot==slot&&(d.job<0||d.job==job)).collect()}else{candidates};
        let d=candidates[dice.next(candidates.len())];let seed=dice.next(u32::MAX as usize) as u32;
        let item=if matches!(quality,"orange"|"green"){let build=specials[dice.next(specials.len())]["id"].as_str().unwrap();loot::roll_special(&d.id,level.clamp(1,60),quality,build,seed,Uuid::new_v4()).unwrap()}else{loot::roll(&d.id,level.clamp(1,60),quality,seed,Uuid::new_v4()).unwrap()};
        state.skins.insert(d.id.clone());ids.push(item.id);
        if used<60{state.items.push(item);used+=1;}else{state.pending.push(item);}
    }
    ids
}
pub fn credit(state:&mut State,boss:bool){
    state.kills=(state.kills+1).min(1000000000);if boss{state.bosses=(state.bosses+1).min(1000000000);}
    state.scrap=(state.scrap+n(if boss{"boss_scrap"}else{"victory_scrap"})).min(1000000000);
    if boss{state.essence=(state.essence+n("boss_essence")).min(1000000000);}
}
