//! Reconstructed attribute rules; committed allocations are monotonic and level bounded.
use crate::pve_rules::{self, Stats};
use rand::Rng;
use serde_json::{Value, json};
use serde::{Serialize,Deserialize};
#[derive(Clone,Copy,Debug,Serialize,Deserialize)]
pub struct BalanceStats {
    #[serde(default)]
    pub skills_revision:u8,
    pub level:i32,pub physical_attack:i32,pub magic_attack:i32,
    pub physical_defense:i32,pub magic_defense:i32,
    pub ratings:[i32;2],
    #[serde(default)] pub crit_bonus:[i32;2],
    #[serde(default)] pub hit_bonus:[i32;2],
    #[serde(default)] pub evade_bonus:[i32;2],
    #[serde(default)] pub crit_damage_bp:i32,
    #[serde(default)] pub increased_bp:i32,
    #[serde(default)] pub dot_bp:i32,
    #[serde(default)] pub penetration_bp:i32,
    #[serde(default)] pub reduction_bp:i32,
    #[serde(default,skip_serializing_if="crate::builds::Snapshot::empty")] pub builds:crate::builds::Snapshot,
}
pub fn balanced_stats(job:i16,level:i32,equipped:bool,a:[i32;5])->Stats{
    let p=crate::combat_balance::profile(job as i64,level as i64,a.map(i64::from)).expect("validated character attributes");
    let mut s=Stats{hp:p.hp as i32,mp:p.mp as i32,attack:if job==2{p.magic_attack}else{p.physical_attack} as i32,defense:p.physical_defense as i32,attributes:a,
        balance:Some(BalanceStats{skills_revision:1,level,physical_attack:p.physical_attack as i32,magic_attack:p.magic_attack as i32,physical_defense:p.physical_defense as i32,magic_defense:p.magic_defense as i32,ratings:[a[3],a[4]],crit_bonus:[0;2],hit_bonus:[0;2],evade_bonus:[0;2],crit_damage_bp:0,increased_bp:0,dot_bp:0,penetration_bp:0,reduction_bp:0,builds:Default::default()})};
    if equipped{gear_bonus(&mut s,5,0);}
    s
}
pub fn gear_bonus(s:&mut Stats,attack:i32,defense:i32){
    s.attack+=attack;s.defense+=defense;
    if let Some(b)=s.balance.as_mut(){b.physical_attack+=attack;b.magic_attack+=attack;b.physical_defense+=defense;b.magic_defense+=defense;}
}
pub fn balanced_profile(job:i16,level:i32,equipped:bool,a:[i32;5])->Value{
    let s=balanced_stats(job,level,equipped,a);profile_for(s,job,level,a)
}
pub fn profile_for(s:Stats,job:i16,level:i32,a:[i32;5])->Value{
    let b=s.balance.expect("balanced profile");
    json!({"version":VERSION,"formula_revision":3,"allocated":a,"available":available(level,a),"recommended":balanced_recommended(job,level,a),
        "combat":{"hp":s.hp,"mp":s.mp,"physical_attack":b.physical_attack,"magic_attack":b.magic_attack,
        "physical_defense":b.physical_defense,"magic_defense":b.magic_defense,"physical_crit":b.ratings[0]+b.crit_bonus[0],"magic_crit":b.ratings[1]+b.crit_bonus[1],
        "physical_hit":b.ratings[0]+b.hit_bonus[0],"magic_hit":b.ratings[1]+b.hit_bonus[1],"physical_evasion":b.ratings[0]+b.evade_bonus[0],"magic_evasion":b.ratings[1]+b.evade_bonus[1],"damage_reduction":b.reduction_bp.min(2500)/100}})
}
pub fn balanced_recommended(job:i16,level:i32,a:[i32;5])->[i32;5]{
    let mut result=a;let pattern=crate::combat_balance::RULES.recommended_patterns[job as usize];
    for i in 0..available(level,a){result[pattern[i as usize%5]]+=1;}result
}
pub fn defense(s:Stats,magical:bool)->i32{s.balance.map_or(s.defense,|b|if magical{b.magic_defense}else{b.physical_defense})}
pub fn direct_damage(s:Stats,defense:i32,coefficient_bp:i32,variance:i32)->i32{
    if let Some(b)=s.balance{
        crate::combat_balance::damage(&crate::combat_balance::Hit{attack:(s.attack+variance).max(0) as i64,defense:defense.max(0) as i64,level:b.level as i64,coefficient_bp:coefficient_bp as i64,increased_bp:b.increased_bp as i64,penetration_bp:b.penetration_bp as i64,..Default::default()}).expect("bounded combat inputs").damage as i32
    }else{(s.attack*coefficient_bp/10000-defense+variance).max(1)}
}
pub fn incoming(attack:i32,level:i32,defender:Stats,magical:bool,variance:i32)->i32{
    if let Some(b)=defender.balance{crate::combat_balance::damage(&crate::combat_balance::Hit{attack:(attack+variance).max(0) as i64,defense:defense(defender,magical).max(0) as i64,level:level.clamp(1,60) as i64,extra_reduction_bp:b.reduction_bp as i64,..Default::default()}).expect("bounded monster").damage as i32}
    else{(attack-defender.defense+variance).max(1)}
}
pub fn dot_damage(mut stats:Stats,defense:i32,coefficient:i32)->i32{
    if let Some(b)=stats.balance.as_mut(){b.increased_bp+=b.dot_bp;}
    direct_damage(stats,defense,coefficient,0)
}
pub fn extra_reduction(damage:i32,defender:Stats)->i32{
    (i64::from(damage)*i64::from(10000-defender.balance.map_or(0,|b|b.reduction_bp.clamp(0,2500)))/10000) as i32
}
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
    if let Some(b)=s.balance{s.attack=if magical{b.magic_attack}else{b.physical_attack};return s;}
    let main = if job == 2 { 1 } else { 2 };
    let selected = if magical { 1 } else { 2 };
    s.attack += 2 * (s.attributes[selected] - s.attributes[main]);
    s
}

/// Ratings are not percentages. One rating = 0.1 percentage points; hit cancels
/// evasion, with a 50% hit floor. New rolls are independent of skill proc rolls.
pub fn hit_chance(attacker: Option<Stats>, defender: Option<Stats>, magical: bool) -> i32 {
    if attacker.is_some_and(|s|s.balance.is_some())||defender.is_some_and(|s|s.balance.is_some()){
        let i=usize::from(magical);let a=attacker.and_then(|s|s.balance);let d=defender.and_then(|s|s.balance);
        return crate::combat_balance::hit_chance(a.or(d).unwrap().level as i64,a.map_or(0,|b|b.ratings[i]+b.hit_bonus[i]) as i64,d.map_or(0,|b|b.ratings[i]+b.evade_bonus[i]) as i64).unwrap() as i32;
    }
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
    let chance = if let Some(b)=s.balance{crate::combat_balance::critical_chance(b.level as i64,(b.ratings[usize::from(magical)]+b.crit_bonus[usize::from(magical)]) as i64,buff as i64).unwrap() as i32}else{(rating * 10 + buff).clamp(0, 7_500)};
    effects.last_critical = damage > 0 && roll < chance;
    if effects.last_critical {
        if let Some(b)=s.balance{(i64::from(damage)*i64::from((15000+b.crit_damage_bp).min(22500))/10000) as i32}else{damage * 3 / 2}
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
    if s.balance.is_none()&&s.attributes[if magical { 4 } else { 3 }] == 0 {
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
