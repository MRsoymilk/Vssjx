//! Reconstructed attribute rules; committed allocations are monotonic and level bounded.
use crate::pve_rules::{self, Stats};
use rand::Rng;
use serde_json::{Value, json};
pub const VERSION: &str = "attributes-v1";
pub fn stats(job: i16, level: i32, equipped: bool, a: [i32; 5]) -> Stats {
    let mut s = pve_rules::stats(job, level, equipped);
    s.hp += a[0] * 8;
    s.mp += a[0] + a[1] * 5 + a[2];
    s.attack += if job == 2 { a[1] * 2 } else { a[2] * 2 };
    s.attributes = a;
    s
}
pub fn available(level: i32, a: [i32; 5]) -> i32 {
    level * 5 - a.iter().sum::<i32>()
}
pub fn recommended(job: i16, level: i32, a: [i32; 5]) -> [i32; 5] {
    let pattern = match job {
        0 => [0, 0, 0, 2, 3],
        1 => [0, 2, 3, 3, 3],
        _ => [0, 1, 1, 1, 4],
    };
    let mut result = a;
    for i in 0..available(level, a) {
        result[pattern[i as usize % 5]] += 1;
    }
    result
}
pub fn profile(job: i16, level: i32, equipped: bool, a: [i32; 5]) -> Value {
    let base = pve_rules::stats(job, level, equipped);
    let s = stats(job, level, equipped, a);
    json!({"version":VERSION,"formula_revision":2,"allocated":a,"available":available(level,a),"recommended":recommended(job,level,a),
        "combat":{"hp":s.hp,"mp":s.mp,"physical_attack":base.attack+a[2]*2,"magic_attack":base.attack+a[1]*2,
        "physical_defense":s.defense,"magic_defense":s.defense,"physical_crit":a[3],"magic_crit":a[4],
        "physical_hit":100+a[3],"magic_hit":100+a[4],"physical_evasion":a[3],"magic_evasion":a[4],"damage_reduction":0}})
}

pub fn unallocated(a: &[i32; 5]) -> bool {
    *a == [0; 5]
}

/// Attack stores the class's main power for the existing wire contract. Basic
/// attacks use physical power; only the hidden master's spells use magic power.
pub fn for_attack(mut s: Stats, job: i16, magical: bool) -> Stats {
    let main = if job == 2 { 1 } else { 2 };
    let selected = if magical { 1 } else { 2 };
    s.attack += 2 * (s.attributes[selected] - s.attributes[main]);
    s
}

/// Ratings are not percentages. One rating = 0.1 percentage points; hit cancels
/// evasion, with a 50% hit floor. New rolls are independent of skill proc rolls.
pub fn hit_chance(attacker: Option<Stats>, defender: Option<Stats>, magical: bool) -> i32 {
    let i = if magical { 4 } else { 3 };
    let hit = attacker.map_or(0, |s| s.attributes[i]);
    let evade = defender.map_or(0, |s| s.attributes[i]);
    (10_000 + (hit - evade) * 10).clamp(5_000, 10_000)
}
pub fn lands(attacker: Option<Stats>, defender: Option<Stats>, magical: bool) -> bool {
    rand::thread_rng().gen_range(0..10_000) < hit_chance(attacker, defender, magical)
}
pub fn critical_at(
    s: Stats,
    magical: bool,
    effects: &mut crate::skills::State,
    damage: i32,
    roll: i32,
) -> i32 {
    let rating = s.attributes[if magical { 4 } else { 3 }];
    let buff = if effects.crit > 0 {
        effects.crit_chance * 100
    } else {
        0
    };
    let chance = (rating * 10 + buff).clamp(0, 7_500);
    effects.last_critical = damage > 0 && roll < chance;
    if effects.last_critical {
        damage * 3 / 2
    } else {
        damage
    }
}
pub fn critical(
    s: Stats,
    magical: bool,
    effects: &mut crate::skills::State,
    damage: i32,
    legacy_roll: i32,
) -> i32 {
    if s.attributes[if magical { 4 } else { 3 }] == 0 {
        return effects.critical(damage, legacy_roll);
    }
    critical_at(
        s,
        magical,
        effects,
        damage,
        rand::thread_rng().gen_range(0..10_000),
    )
}

/// Saved encounters retain the allocation inputs; shared battle packets expose
/// combat results, never another character's allocation array.
pub fn public_battle(mut value: Value) -> Value {
    fn scrub(value: &mut Value) {
        match value {
            Value::Object(map) => {
                if let Some(Value::Object(stats)) = map.get_mut("stats") {
                    stats.remove("attributes");
                }
                for child in map.values_mut() {
                    scrub(child);
                }
            }
            Value::Array(items) => {
                for child in items {
                    scrub(child);
                }
            }
            _ => {}
        }
    }
    scrub(&mut value);
    value
}
