//! Authoritative, versioned, single-character turn-based encounters.
use crate::population::ResidentDefinition;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use uuid::Uuid;

pub const RULES: &str = "qingyun-pve-v1";
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Equip,
    Unequip,
    Transfer,
    Allocate,
    Accept,
    Claim,
    Restore,
    Challenge,
    Attack,
    Skill,
    Guard,
    Potion,
    Flee,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub operation_id: Uuid,
    pub action: Action,
    pub target: Option<String>,
    pub battle_id: Option<Uuid>,
    pub expected_revision: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attributes: Option<[i32; 5]>,
}
#[derive(Clone, Copy, Debug, Serialize)]
pub struct Stats {
    pub hp: i32,
    pub mp: i32,
    pub attack: i32,
    pub defense: i32,
}
pub fn stats(job: i16, level: i32, equipped: bool) -> Stats {
    let job = job as usize;
    Stats {
        hp: [120, 95, 85][job] + (level - 1) * 18,
        mp: [35, 45, 65][job] + (level - 1) * 8,
        attack: [18, 23, 21][job] + (level - 1) * 4 + if equipped { 5 } else { 0 },
        defense: [7, 4, 3][job] + (level - 1) * 2,
    }
}
pub fn mask(id: &str) -> Option<i32> {
    match id {
        "wolf_a" => Some(1),
        "wolf_b" => Some(2),
        "wolf_c" => Some(4),
        "spirit" => Some(8),
        "guardian" => Some(16),
        "boss" => Some(32),
        _ => None,
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Battle {
    pub id: Uuid,
    pub enemy: ResidentDefinition,
    pub hp: i32,
    pub mp: i32,
    pub potions: i32,
    pub enemy_hp: i32,
    pub round: u32,
    pub revision: u64,
    pub outcome: String,
}
impl Battle {
    pub fn new(enemy: ResidentDefinition, hp: i32, mp: i32, potions: i32) -> Self {
        Self {
            id: Uuid::new_v4(),
            enemy_hp: enemy.hp,
            enemy,
            hp,
            mp,
            potions,
            round: 0,
            revision: 0,
            outcome: "active".into(),
        }
    }
    pub fn view(&self) -> Value {
        let mut value = serde_json::to_value(self).expect("battle view");
        value["revision"] = json!(self.revision.to_string());
        value
    }
    pub fn turn(
        &mut self,
        action: Action,
        job: i16,
        stats: Stats,
        player_roll: i32,
        enemy_roll: i32,
    ) -> Result<Vec<String>, &'static str> {
        if self.outcome != "active" {
            return Err("BATTLE_FINISHED");
        }
        if !matches!(
            action,
            Action::Attack | Action::Skill | Action::Guard | Action::Potion | Action::Flee
        ) {
            return Err("INVALID_BATTLE_ACTION");
        }
        if action == Action::Skill && self.mp < 9 {
            return Err("MP_INSUFFICIENT");
        }
        if action == Action::Potion && self.potions < 1 {
            return Err("NO_POTION");
        }
        if action == Action::Potion && self.hp >= stats.hp {
            return Err("HP_FULL");
        }
        self.round += 1;
        self.revision += 1;
        let mut lines = vec![format!("第{}回合", self.round)];
        let damage = match action {
            Action::Attack => (stats.attack - self.enemy.defense + player_roll.clamp(-2, 2)).max(1),
            Action::Skill => {
                self.mp -= 9;
                if job == 2 {
                    self.hp = (self.hp + 16).min(stats.hp);
                }
                (stats.attack * 18 / 10 - self.enemy.defense).max(1)
            }
            Action::Guard => {
                self.mp = (self.mp + 5).min(stats.mp);
                lines.push("凝神防御，恢复5点灵力。".into());
                0
            }
            Action::Potion => {
                self.potions -= 1;
                self.hp = (self.hp + 45).min(stats.hp);
                lines.push("服用回春散，恢复元气。".into());
                0
            }
            Action::Flee => {
                self.outcome = "fled".into();
                lines.push("你退出了遭遇战。".into());
                return Ok(lines);
            }
            _ => unreachable!(),
        };
        if damage > 0 {
            self.enemy_hp = (self.enemy_hp - damage).max(0);
            lines.push(format!("你造成{damage}点伤害。"));
        }
        if self.enemy_hp == 0 {
            self.outcome = "victory".into();
            lines.push(format!("{}被击败！", self.enemy.name));
            return Ok(lines);
        }
        let mut incoming = (self.enemy.attack - stats.defense + enemy_roll.clamp(-2, 2)).max(1);
        if action == Action::Guard {
            incoming = (incoming / 2).max(1);
        }
        self.hp = (self.hp - incoming).max(0);
        lines.push(format!("{}出击，你受到{incoming}点伤害。", self.enemy.name));
        if job == 0 && action == Action::Guard {
            self.enemy_hp = (self.enemy_hp - 6).max(0);
            lines.push("力士反震造成6点伤害。".into());
        }
        if self.hp == 0 {
            self.outcome = "defeat".into();
            lines.push("道人护持，你恢复元气，试炼进度保留。".into());
        } else if self.enemy_hp == 0 {
            self.outcome = "victory".into();
            lines.push(format!("{}被击败！", self.enemy.name));
        } else if self.round >= 30 {
            self.outcome = "fled".into();
            lines.push("三十回合已过，遭遇战结束。".into());
        }
        Ok(lines)
    }
}
