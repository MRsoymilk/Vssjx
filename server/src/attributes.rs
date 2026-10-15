//! Reconstructed attribute rules; committed allocations are monotonic and level bounded.
use crate::pve_rules::{self, Stats};
use serde_json::{Value, json};
pub const VERSION: &str = "attributes-v1";
pub fn stats(job: i16, level: i32, equipped: bool, a: [i32; 5]) -> Stats {
    let mut s = pve_rules::stats(job, level, equipped);
    s.hp += a[0] * 8 + a[2] * 2;
    s.mp += a[1] * 5 + a[4] * 2;
    s.attack += if job == 2 {
        a[1] * 2 + a[3]
    } else {
        a[2] * 2 + a[3]
    };
    s.defense += a[0] / 2 + a[3] + a[4] * 2;
    s
}
pub fn available(level: i32, a: [i32; 5]) -> i32 {
    level * 5 - a.iter().sum::<i32>()
}
pub fn recommended(job: i16, level: i32, a: [i32; 5]) -> [i32; 5] {
    let pattern = match job {
        0 => [0, 0, 0, 2, 4],
        1 => [0, 2, 2, 2, 3],
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
    json!({"version":VERSION,"allocated":a,"available":available(level,a),"recommended":recommended(job,level,a),
        "combat":{"hp":s.hp,"mp":s.mp,"physical_attack":base.attack+a[2]*2+a[3],"magic_attack":base.attack+a[1]*2+a[3],
        "physical_defense":s.defense,"magic_defense":s.defense,"physical_crit":0,"magic_crit":0,
        "physical_hit":100,"magic_hit":100,"physical_evasion":0,"magic_evasion":0,"damage_reduction":0}})
}
