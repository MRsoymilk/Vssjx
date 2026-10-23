//! Versioned budgets for revised encounters only; legacy skills remain byte-stable.
use crate::{pve_rules::Stats,skills::Skill,population::ResidentDefinition};
use serde_json::Value;
use std::sync::LazyLock;
pub static DATA:LazyLock<Value>=LazyLock::new(||serde_json::from_str(include_str!("../../shared/data/skill-balance-v1.json")).unwrap());
pub fn n(key:&str)->i32{DATA[key].as_i64().unwrap() as i32}
pub fn revised(stats:Stats)->bool{stats.balance.is_some_and(|b|b.skills_revision>=1)}
pub fn kind(s:&Skill)->&'static str{
    if matches!(s.effect.as_str(),"sleep"|"silence"){"control"}
    else if matches!(s.effect.as_str(),"bleed"|"poison"){"dot"}
    else if s.damage_percent==0{"support"}
    else if s.target=="all_enemies"{"aoe"}else{"single"}
}
pub fn coefficient(s:&Skill,targets:i32)->i32{
    if s.damage_percent==0{return 0;}
    let raw=match kind(s){"dot"=>n("dot_direct_bp"),"aoe"=>n("aoe_bp"),"control"=>n("control_direct_bp"),_=>n("single_bp")};
    if s.target=="all_enemies"{crate::combat_balance::aoe_coefficient(raw as i64,targets.clamp(1,5) as i64).unwrap() as i32}else{raw}
}
pub fn cost(s:&Skill,stats:Stats)->i32{
    if !revised(stats){return s.mp_cost;}
    let bp=DATA["cost_bp"][kind(s)].as_i64().unwrap() as i32;
    ((i64::from(stats.mp)*i64::from(bp)+9999)/10000).max(1) as i32
}
pub fn cooldown_for(s:&Skill,stun_enabled:bool)->i32{if stun_enabled && let Some(stun)=s.stun.as_ref(){return stun.cooldown;}DATA["cooldowns"][kind(s)].as_i64().unwrap() as i32}
pub fn cooldown(s:&Skill)->i32{cooldown_for(s,true)}
pub fn recovery(stats:Stats,key:&str,legacy:i32)->i32{if revised(stats){(stats.mp*n(key)/10000).max(1)}else{legacy}}
pub fn potion(stats:Stats)->i32{if revised(stats){(stats.hp*n("potion_restore_bp")/10000).max(45)}else{45}}
pub fn monster(mut d:ResidentDefinition)->ResidentDefinition{
    d.defense*=n("monster_defense_multiplier");
    if d.kind=="boss"||d.id=="boss"{d.hp*=n("boss_hp_multiplier");}
    d
}
pub fn monster_magical(d:&ResidentDefinition,round:i32,mp:i32,silenced:bool)->bool{
    !silenced&&mp>=10&&round%n("cast_period")==0&&DATA["magic_art_prefixes"].as_array().unwrap().iter().any(|p|d.art.starts_with(p.as_str().unwrap()))
}
