//! Player-sheet skill names/effects. Numeric rules are explicitly reconstructed.
use crate::pve_rules::Stats;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::sync::LazyLock;
const DATA: &str = include_str!("../../client/assets/data/skills-v1.json");
#[derive(Deserialize)]
pub struct Skill {
    pub id: String,
    pub name: String,
    pub job: i16,
    pub school: i16,
    pub unlock_level: i32,
    pub active: bool,
    pub mp_cost: i32,
    pub damage_percent: i32,
    pub effect: String,
    pub value: i32,
    pub duration: i32,
    pub chance: i32,
    pub legacy_heal: i32,
    pub target: String,
}
pub static ITEMS: LazyLock<Vec<Skill>> = LazyLock::new(|| {
    serde_json::from_value(
        serde_json::from_str::<Value>(DATA).expect("skill catalog")["items"].clone(),
    )
    .expect("typed skill catalog")
});
static HASH: LazyLock<String> = LazyLock::new(|| {
    format!(
        "{:x}",
        Sha256::digest(DATA.replace("\r\n", "\n").as_bytes())
    )
});
pub fn item(id: &str) -> Option<&'static Skill> {
    ITEMS.iter().find(|s| s.id == id)
}
pub fn eligible(s: &Skill, job: i16, _school: i16, level: i32) -> bool {
    // Keep the original school as source metadata; unlock by job and level for now.
    s.job == job && level >= s.unlock_level
}
pub fn check(id: &str, job: i16, _school: i16, level: i32) -> Result<&'static Skill, &'static str> {
    let s = item(id).ok_or("INVALID_SKILL")?;
    if s.job != job {
        return Err("SKILL_ROLE_MISMATCH");
    }
    if level < s.unlock_level {
        return Err("SKILL_LEVEL_REQUIRED");
    }
    if !s.active {
        return Err("PASSIVE_SKILL");
    }
    Ok(s)
}
pub fn view(job: i16, school: i16, level: i32) -> Value {
    json!({"version":"skills-v1","catalog_sha256":*HASH,"available":ITEMS.iter().filter(|s|eligible(s,job,school,level)).map(|s|&s.id).collect::<Vec<_>>()})
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct State {
    pub last_skill: String,
    pub last_enemy_acted: bool,
    pub enemy_mp: i32,
    pub enemy_bleed: i32,
    pub bleed_damage: i32,
    pub enemy_poison: i32,
    pub poison_damage: i32,
    pub enemy_sleep: i32,
    pub enemy_silence: i32,
    pub regen: i32,
    pub regen_amount: i32,
    pub defense: i32,
    pub defense_percent: i32,
    pub crit: i32,
    pub crit_chance: i32,
    pub reflect_physical: i32,
    pub physical_percent: i32,
    pub reflect_magic: i32,
    pub magic_percent: i32,
    pub passive_physical: i32,
    pub passive_magic: i32,
    pub last_damage: i32,
    pub last_incoming: i32,
    pub last_reflected: i32,
    pub last_healed: i32,
}
impl State {
    pub fn new(job: i16, school: i16, level: i32, enemy_level: i32) -> Self {
        let mut state = Self {
            enemy_mp: 30 + enemy_level * 2,
            ..Self::default()
        };
        for s in ITEMS
            .iter()
            .filter(|s| eligible(s, job, school, level) && !s.active)
        {
            if s.effect == "reflect_magic" {
                state.passive_magic = s.value;
            } else {
                state.passive_physical = s.value;
            }
        }
        state
    }
    pub fn reset_turn(&mut self) {
        self.last_skill.clear();
        self.last_enemy_acted = false;
        self.last_damage = 0;
        self.last_incoming = 0;
        self.last_reflected = 0;
        self.last_healed = 0;
    }
    pub fn critical(&self, damage: i32, roll: i32) -> i32 {
        if self.crit > 0 && roll < self.crit_chance {
            damage * 3 / 2
        } else {
            damage
        }
    }
    pub fn cast(
        &mut self,
        s: &Skill,
        stats: Stats,
        hp: &mut i32,
        mp: &mut i32,
        enemy_defense: i32,
        roll: i32,
    ) -> i32 {
        self.last_skill = s.id.clone();
        *mp -= s.mp_cost;
        let damage = if s.damage_percent > 0 {
            (stats.attack * s.damage_percent / 100 - enemy_defense).max(1)
        } else {
            0
        };
        let healed = s.legacy_heal.min(stats.hp - *hp);
        *hp += healed;
        self.last_healed += healed;
        if damage > 0 {
            self.enemy_sleep = 0;
        }
        match s.effect.as_str() {
            "bleed" => {
                self.enemy_bleed = s.duration;
                self.bleed_damage = (stats.attack * s.value / 100).max(1);
            }
            "poison" => {
                self.enemy_poison = s.duration;
                self.poison_damage = (stats.attack * s.value / 100).max(1);
            }
            "sleep" => {
                if roll < s.chance {
                    self.enemy_sleep = s.duration;
                }
            }
            "silence" => {
                if roll < s.chance {
                    self.enemy_silence = s.duration;
                }
            }
            "regen" => {
                self.regen = s.duration;
                self.regen_amount = (stats.hp * s.value / 100).max(1);
            }
            "defense" => {
                self.defense = s.duration;
                self.defense_percent = s.value;
            }
            "crit" => {
                self.crit = s.duration;
                self.crit_chance = s.value;
            }
            "reflect_physical" => {
                self.reflect_physical = s.duration;
                self.physical_percent = s.value;
            }
            "reflect_magic" => {
                self.reflect_magic = s.duration;
                self.magic_percent = s.value;
            }
            "mana_steal" => {
                let stolen = s.value.min(self.enemy_mp);
                self.enemy_mp -= stolen;
                *mp = (*mp + stolen).min(stats.mp);
            }
            _ => {}
        }
        damage
    }
    pub fn after_player(&mut self, hp: &mut i32, max_hp: i32) -> i32 {
        let mut damage = 0;
        if self.enemy_bleed > 0 {
            damage += self.bleed_damage;
            self.enemy_bleed -= 1;
        }
        if self.enemy_poison > 0 {
            damage += self.poison_damage;
            self.enemy_poison -= 1;
        }
        if self.regen > 0 {
            let healed = self.regen_amount.min(max_hp - *hp);
            *hp += healed;
            self.last_healed += healed;
            self.regen -= 1;
        }
        damage
    }
    pub fn enemy_hit(&self, mut incoming: i32, magical: bool) -> (i32, i32) {
        if self.defense > 0 {
            incoming = (incoming * (100 - self.defense_percent) / 100).max(1);
        }
        let mut percent = if magical {
            self.passive_magic
        } else {
            self.passive_physical
        };
        if if magical {
            self.reflect_magic > 0
        } else {
            self.reflect_physical > 0
        } {
            percent = percent.max(if magical {
                self.magic_percent
            } else {
                self.physical_percent
            });
        }
        (incoming, incoming * percent / 100)
    }
    pub fn end_turn(&mut self) {
        for n in [
            &mut self.defense,
            &mut self.crit,
            &mut self.reflect_physical,
            &mut self.reflect_magic,
            &mut self.enemy_sleep,
            &mut self.enemy_silence,
        ] {
            *n = (*n - 1).max(0);
        }
    }
}
