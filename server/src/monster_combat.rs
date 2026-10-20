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
