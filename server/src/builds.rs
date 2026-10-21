//! Equipment-derived play styles. Only frozen snapshots grant combat procs.
use crate::{loot,skills::{Skill,State},pve_rules::Stats};
use serde::{Serialize,Deserialize};
use serde_json::Value;
use std::sync::LazyLock;
use sha2::{Digest,Sha256};
pub static DATA:LazyLock<Value>=LazyLock::new(||serde_json::from_str(include_str!("../../shared/data/builds-v1.json")).unwrap());
pub static HASH:LazyLock<String>=LazyLock::new(||format!("{:x}",Sha256::digest(include_str!("../../shared/data/builds-v1.json").replace("\r\n","\n").as_bytes())));
pub fn index(id:&str)->Option<usize>{DATA["items"].as_array().unwrap().iter().position(|v|v["id"]==id)}
#[derive(Clone,Copy,Debug,Default,Serialize,Deserialize)]
pub struct Snapshot{pub legendary:u8,pub sets:[u8;6]}
impl Snapshot{
    pub fn empty(&self)->bool{self.legendary==0&&self.sets==[0;6]}
    pub fn tier(&self,i:usize)->usize{usize::from(self.legendary&(1<<i)!=0)+usize::from(self.sets[i]>=4)}
}
#[derive(Clone,Debug,Default,Serialize,Deserialize)]
pub struct Progress{pub charges:[i32;6],pub used:bool,pub bonus_bp:i32,pub dot_bp:i32}
pub fn compatible(id:&str,job:i16,slot:&str,legendary:bool)->bool{
    index(id).is_some_and(|i|DATA["items"][i]["job"]==job&&if legendary{DATA["items"][i]["legend_slot"]==slot}else{DATA["set_slots"].as_array().unwrap().iter().any(|v|v==slot)})
}
pub fn aggregate(loot:&loot::State,s:&mut Stats){
    let Some(b)=s.balance.as_mut()else{return;};let mut snapshot=Snapshot::default();
    for item in loot.items.iter().filter(|i|i.equipped&&!i.legacy){
        if let Some(i)=item.legendary.as_deref().and_then(index){snapshot.legendary|=1<<i;}
        if let Some(i)=item.set_id.as_deref().and_then(index){snapshot.sets[i]+=1;}
    }
    for i in 0..6{if snapshot.sets[i]>=2{for (kind,v) in DATA["items"][i]["two"].as_object().unwrap(){let v=v.as_i64().unwrap() as i32;match kind.as_str(){"reduction"=>b.reduction_bp+=v,"dot"=>b.dot_bp+=v,"crit"=>{b.crit_bonus[0]+=v;b.crit_bonus[1]+=v;},"hit"=>{b.hit_bonus[0]+=v;b.hit_bonus[1]+=v;},"mana"=>s.mp+=v,_=>()}}}}
    b.builds=snapshot;
}
pub fn cast(skill:&Skill,stats:Stats,state:&mut State,hp:&mut i32,mp:&mut i32,mut damage:i32,stolen:i32,control_applied:bool)->i32{
    let snapshot=stats.balance.map(|b|b.builds).unwrap_or_default();if snapshot.empty(){return damage;}
    let p=state.builds.get_or_insert_with(Default::default);let once=!p.used;p.used=true;
    let mut healed=0;let mut refund=0;
    let param=|i:usize,key:&str|->i32{let tier=snapshot.tier(i);if tier==0{0}else{DATA["items"][i][key][tier-1].as_i64().unwrap() as i32}};
    if once{
        if snapshot.tier(0)>0{
            if matches!(skill.effect.as_str(),"defense"|"reflect_physical"|"reflect_magic"){p.charges[0]=1;}
            else if damage>0&&p.charges[0]>0{p.charges[0]=0;p.bonus_bp+=param(0,"bonus");healed+=stats.hp*param(0,"heal")/10000;}
        }
        if snapshot.tier(1)>0&&skill.effect=="bleed"{healed+=stats.hp*param(1,"heal")/10000;}
        if snapshot.tier(2)>0&&damage>0{
            if skill.target=="all_enemies"{p.bonus_bp+=p.charges[2]*param(2,"bonus");p.charges[2]=0;}
            else{p.charges[2]=(p.charges[2]+1).min(2);}
        }
        if snapshot.tier(4)>0{
            if skill.effect=="regen"{p.charges[4]=1;}
            else if damage>0&&p.charges[4]>0{p.charges[4]=0;p.bonus_bp+=param(4,"bonus");refund=stats.mp*param(4,"refund")/10000;}
        }
        if snapshot.tier(5)>0{
            if skill.effect=="mana_steal"&&stolen>0{p.charges[5]=1;healed+=(stolen*2).min(stats.hp*param(5,"heal_cap")/10000);}
            else if skill.effect=="bleed"&&p.charges[5]>0{p.charges[5]=0;p.dot_bp=param(5,"dot");}
        }
    }
    damage=(i64::from(damage)*i64::from(10000+p.bonus_bp.min(DATA["final_bonus_cap_bp"].as_i64().unwrap() as i32))/10000) as i32;
    if skill.effect=="bleed"{
        if snapshot.tier(1)>0{state.enemy_bleed=2;state.bleed_damage=state.bleed_damage*param(1,"tick")/10000;}
        state.bleed_damage=state.bleed_damage*(10000+p.dot_bp)/10000;
    }
    if snapshot.tier(3)>0&&skill.effect=="sleep"&&control_applied&&state.enemy_poison>0{damage+=state.poison_damage*param(3,"ticks");}
    if *hp>0{let amount=healed.min(stats.hp-*hp);*hp+=amount;state.last_healed+=amount;}
    *mp=(*mp+refund).min(stats.mp);damage
}
