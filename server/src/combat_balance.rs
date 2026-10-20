//! Versioned v1 kernel; legacy encounters explicitly retain legacy adapters.
//! Integer basis points; floor each stage, cap each multiplier once.
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

#[derive(Deserialize)]
pub struct Rules {
    pub version: String,
    pub basis: i64,
    pub max_level: i64,
    pub points_per_level: i64,
    pub recommended_patterns: [[usize;5];3],
    pub max_value: i64,
    pub hp_base: [i64; 3],
    pub hp_growth: [i64; 3],
    pub mp_base: [i64; 3],
    pub mp_growth: i64,
    pub physical_base: [i64; 3],
    pub magic_base: [i64; 3],
    pub attack_growth: i64,
    pub defense_base: [i64; 3],
    pub defense_growth: i64,
    pub vitality_hp: i64,
    pub spirit_mp: i64,
    pub primary_attack: i64,
    pub armor_constant: i64,
    pub armor_per_level: i64,
    pub armor_cap_bp: i64,
    pub penetration_cap_bp: i64,
    pub increased_cap_bp: i64,
    pub extra_reduction_cap_bp: i64,
    pub critical_base_bp: i64,
    pub critical_rating_bonus_bp: i64,
    pub critical_cap_bp: i64,
    pub critical_damage_base_bp: i64,
    pub critical_damage_cap_bp: i64,
    pub rating_constant: i64,
    pub rating_per_level: i64,
    pub hit_base_bp: i64,
    pub hit_rating_bonus_bp: i64,
    pub hit_floor_bp: i64,
    pub hit_cap_bp: i64,
    pub legendary_cap_bp: i64,
    pub skill_coefficient_cap_bp: i64,
    pub aoe_budget_bp: i64,
    pub max_combatants: i64,
    pub boss_hp_per_member_bp: i64,
}
pub static RULES: LazyLock<Rules> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../../shared/data/balance-v1.json"))
        .expect("authored balance contract")
});
fn level(value: i64) -> Result<(), &'static str> {
    if (1..=RULES.max_level).contains(&value) {
        Ok(())
    } else {
        Err("INVALID_LEVEL")
    }
}
fn values(input: &[i64]) -> Result<(), &'static str> {
    if input.iter().all(|v| (0..=RULES.max_value).contains(v)) {
        Ok(())
    } else {
        Err("INVALID_VALUE")
    }
}

#[derive(Debug, Serialize, PartialEq)]
pub struct Profile {
    pub hp: i64,
    pub mp: i64,
    pub physical_attack: i64,
    pub magic_attack: i64,
    pub physical_defense: i64,
    pub magic_defense: i64,
    pub available: i64,
}
pub fn profile(job: i64, l: i64, a: [i64; 5]) -> Result<Profile, &'static str> {
    level(l)?;
    values(&a)?;
    if !(0..=2).contains(&job) {
        return Err("INVALID_JOB");
    }
    let available = l * RULES.points_per_level - a.iter().sum::<i64>();
    if available < 0 {
        return Err("ATTRIBUTE_POINTS_EXCEEDED");
    }
    let j = job as usize;
    let growth = l - 1;
    let defense = RULES.defense_base[j] + growth * RULES.defense_growth;
    Ok(Profile {
        hp: RULES.hp_base[j] + growth * RULES.hp_growth[j] + a[0] * RULES.vitality_hp,
        mp: RULES.mp_base[j] + growth * RULES.mp_growth + a[0] + a[1] * RULES.spirit_mp + a[2],
        physical_attack: RULES.physical_base[j]
            + growth * RULES.attack_growth
            + a[2] * RULES.primary_attack,
        magic_attack: RULES.magic_base[j]
            + growth * RULES.attack_growth
            + a[1] * RULES.primary_attack,
        physical_defense: defense,
        magic_defense: defense + a[4] / 2,
        available,
    })
}
fn basis() -> i64 {
    RULES.basis
}
fn crit_multiplier() -> i64 {
    RULES.critical_damage_base_bp
}
#[derive(Clone, Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Hit {
    pub attack: i64,
    pub defense: i64,
    pub level: i64,
    pub coefficient_bp: i64,
    pub increased_bp: i64,
    pub penetration_bp: i64,
    pub flat_penetration: i64,
    pub critical: bool,
    pub critical_multiplier_bp: i64,
    pub extra_reduction_bp: i64,
    pub legendary_bp: i64,
    pub guarding: bool,
}
impl Default for Hit {
    fn default() -> Self {
        Self {
            attack: 0,
            defense: 0,
            level: 1,
            coefficient_bp: basis(),
            increased_bp: 0,
            penetration_bp: 0,
            flat_penetration: 0,
            critical: false,
            critical_multiplier_bp: crit_multiplier(),
            extra_reduction_bp: 0,
            legendary_bp: basis(),
            guarding: false,
        }
    }
}
#[derive(Debug, Serialize, PartialEq)]
pub struct Damage {
    pub damage: i64,
    pub effective_defense: i64,
    pub reduction_bp: i64,
}
pub fn damage(h: &Hit) -> Result<Damage, &'static str> {
    level(h.level)?;
    values(&[
        h.attack,
        h.defense,
        h.coefficient_bp,
        h.increased_bp,
        h.penetration_bp,
        h.flat_penetration,
        h.critical_multiplier_bp,
        h.extra_reduction_bp,
        h.legendary_bp,
    ])?;
    if h.coefficient_bp > RULES.skill_coefficient_cap_bp {
        return Err("INVALID_COEFFICIENT");
    }
    let b = RULES.basis;
    let effective = (h.defense * (b - h.penetration_bp.min(RULES.penetration_cap_bp)) / b
        - h.flat_penetration)
        .max(0);
    let k = RULES.armor_constant + RULES.armor_per_level * h.level;
    let reduction = (effective * b / (effective + k)).min(RULES.armor_cap_bp);
    let mut n = h.attack * h.coefficient_bp / b;
    n = n * (b + h.increased_bp.min(RULES.increased_cap_bp)) / b;
    n = n * (b - reduction) / b;
    if h.critical {
        n = n * h
            .critical_multiplier_bp
            .clamp(b, RULES.critical_damage_cap_bp)
            / b;
    }
    n = n * (b - h.extra_reduction_bp.min(RULES.extra_reduction_cap_bp)) / b;
    n = n * h.legendary_bp.clamp(b, RULES.legendary_cap_bp) / b;
    if h.guarding {
        n /= 2;
    }
    if h.attack > 0 && h.coefficient_bp > 0 {
        n = n.max(1);
    }
    Ok(Damage {
        damage: n,
        effective_defense: effective,
        reduction_bp: reduction,
    })
}
pub fn critical_chance(l: i64, rating: i64, bonus: i64) -> Result<i64, &'static str> {
    level(l)?;
    values(&[rating, bonus])?;
    Ok((RULES.critical_base_bp
        + RULES.critical_rating_bonus_bp * rating
            / (rating + RULES.rating_constant + RULES.rating_per_level * l)
        + bonus)
        .min(RULES.critical_cap_bp))
}
pub fn hit_chance(l: i64, hit: i64, evasion: i64) -> Result<i64, &'static str> {
    level(l)?;
    values(&[hit, evasion])?;
    let delta = hit - evasion;
    Ok((RULES.hit_base_bp
        + RULES.hit_rating_bonus_bp * delta
            / (delta.abs() + RULES.rating_constant + RULES.rating_per_level * l))
        .clamp(RULES.hit_floor_bp, RULES.hit_cap_bp))
}
pub fn aoe_coefficient(coefficient: i64, targets: i64) -> Result<i64, &'static str> {
    if !(1..=RULES.max_combatants).contains(&targets)
        || !(0..=RULES.skill_coefficient_cap_bp).contains(&coefficient)
    {
        return Err("INVALID_AOE");
    }
    Ok(coefficient.min(RULES.aoe_budget_bp / targets))
}
pub fn boss_hp(hp: i64, members: i64) -> Result<i64, &'static str> {
    values(&[hp])?;
    if !(1..=RULES.max_combatants).contains(&members) {
        return Err("INVALID_PARTY_SIZE");
    }
    Ok(hp * (RULES.basis + RULES.boss_hp_per_member_bp * (members - 1)) / RULES.basis)
}
