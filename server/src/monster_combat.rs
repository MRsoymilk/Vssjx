//! Frozen encounter AI; rolls are supplied by the authority, never by the client.
use crate::population::ResidentDefinition;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::LazyLock;
pub static DATA: LazyLock<Value> = LazyLock::new(|| serde_json::from_str(include_str!("../../shared/data/monster-combat-v1.json")).unwrap());
pub fn n(key: &str) -> i32 { DATA[key].as_i64().unwrap() as i32 }
pub fn strong(d: &ResidentDefinition) -> bool {
    d.id == "boss" || d.level >= n("strong_level") || DATA["strong_kinds"].as_array().unwrap().iter().any(|k| k.as_str() == Some(&d.kind))
}
pub fn solo_count(roll: i32) -> usize {
    DATA["solo_counts"].as_array().unwrap().iter().position(|p| roll.rem_euclid(100) < p.as_i64().unwrap() as i32).unwrap_or(2) + 1
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Plan { pub skill: String, pub hits: usize, pub all: bool, pub magical: bool, pub coefficient: i32, pub bleed: bool }
pub fn plan(d: &ResidentDefinition, roll: i32, magical: bool, silenced: bool) -> Plan {
    let mut p = Plan { skill: String::new(), hits: 1, all: false, magical, coefficient: 10000, bleed: false };
    if !strong(d) { return p; }
    let roll = roll.rem_euclid(100);
    if roll < n("combo_chance") {
        p.skill = "monster_combo".into(); p.hits = 2; p.coefficient = n("combo_bp"); p.magical = false;
    } else if roll < n("combo_chance") + n("sweep_chance") && !silenced {
        p.skill = "monster_sweep".into(); p.all = true; p.coefficient = n("sweep_bp");
    } else if roll < n("combo_chance") + n("sweep_chance") + n("rend_chance") {
        p.skill = "monster_rend".into(); p.coefficient = n("rend_bp"); p.bleed = true; p.magical = false;
    }
    p
}
pub fn critical(d: &ResidentDefinition, damage: i32, roll: i32) -> (i32, bool) {
    let critical = damage > 0 && roll.rem_euclid(100) < n(if strong(d) { "strong_crit" } else { "normal_crit" });
    (if critical { damage * n("crit_bp") / 10000 } else { damage }, critical)
}
pub fn name(id: &str) -> &str { match id { "monster_combo" => "疾风连击", "monster_sweep" => "横扫千军", "monster_rend" => "撕裂重击", _ => "攻击" } }

/// Consecutive accepted encounters; coordinates deliberately do not participate.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct HuntPressure { pub map: String, pub species: String, pub count: u8 }
impl HuntPressure {
    pub fn valid(&self) -> bool {
        self.count <= n("hunt_threshold") as u8 && self.map.len() <= 64 && self.species.len() <= 128 &&
        if self.count == 0 { self.map.is_empty() && self.species.is_empty() } else { !self.map.is_empty() && !self.species.is_empty() }
    }
    pub fn note(&mut self, map: &str, species: &str) -> bool {
        if self.map != map || self.species != species { *self=Self {map:map.into(),species:species.into(),count:0}; }
        self.count=(self.count+1).min(n("hunt_threshold") as u8);
        self.due()
    }
    pub fn due(&self) -> bool { self.count == n("hunt_threshold") as u8 }
    pub fn cleared(&mut self, map: &str, species: &str) {
        if self.due() && self.map==map && self.species==species { *self=Self::default(); }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Elite { pub party_size: usize, pub revives_left: i32 }
pub fn elite_n(party: usize, key: &str) -> i32 { DATA[if party>1 {"elite_party"}else{"elite_solo"}][key].as_i64().unwrap() as i32 }
pub fn empower(d: &mut ResidentDefinition, party: usize) {
    // Normal boss/party budgeting runs first; scale once, retaining species and rewards.
    let extra=if party>1 && d.kind!="boss" && d.id!="boss" {100+25*(party as i32-1)}else{100};
    d.hp=((i64::from(d.hp)*i64::from(elite_n(party,"hp_bp"))*i64::from(extra))/1_000_000).clamp(1,100000) as i32;
    d.attack=(d.attack*elite_n(party,"attack_bp")/10000).clamp(1,100000);
    d.defense=(d.defense*elite_n(party,"defense_bp")/10000).clamp(0,100000);
}
pub fn elite_plan(elite: Option<&Elite>, d: &ResidentDefinition, roll: i32, magical: bool, silenced: bool) -> Plan {
    let Some(elite)=elite else { return plan(d,roll,magical,silenced); };
    let combo=roll.rem_euclid(100)<elite_n(elite.party_size,"combo_chance");
    Plan {skill:if combo {"monster_combo"}else{"monster_sweep"}.into(),hits:if combo {elite_n(elite.party_size,"hits") as usize}else{1},all:!combo && !silenced,magical:!combo&&magical&&!silenced,coefficient:if combo {elite_n(elite.party_size,"combo_bp")}else{10000},bleed:true}
}
pub fn elite_critical(elite: Option<&Elite>, d: &ResidentDefinition, damage:i32,roll:i32) -> (i32,bool) {
    let Some(elite)=elite else {return critical(d,damage,roll);};
    let crit=damage>0 && roll.rem_euclid(100)<elite_n(elite.party_size,"crit");
    (if crit {damage*elite_n(elite.party_size,"crit_bp")/10000}else{damage},crit)
}
