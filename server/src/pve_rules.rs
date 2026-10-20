//! Authoritative, versioned, single-character turn-based encounters.
use crate::population::ResidentDefinition;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use uuid::Uuid;

pub const RULES: &str = "qingyun-pve-v1";
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Action {
    Revive,
    SchoolJoin,
    AiAccept,
    AiClaim,
    AiInteract,
    AiTravel,
    AiRestore,
    Buy,
    Use,
    Discard,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantity: Option<i32>,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct Stats {
    pub hp: i32,
    pub mp: i32,
    pub attack: i32,
    pub defense: i32,
    #[serde(default, skip_serializing_if = "crate::attributes::unallocated")]
    pub attributes: [i32; 5],
}
pub fn stats(job: i16, level: i32, equipped: bool) -> Stats {
    let job = job as usize;
    Stats {
        hp: [120, 95, 85][job] + (level - 1) * 18,
        mp: [35, 45, 65][job] + (level - 1) * 8,
        attack: [18, 23, 21][job] + (level - 1) * 4 + if equipped { 5 } else { 0 },
        defense: [7, 4, 3][job] + (level - 1) * 2,
        attributes: [0; 5],
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
    #[serde(default)]
    pub skills: crate::skills::State,
    #[serde(default)]
    pub skill_rules_version: u8,
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
            skills: Default::default(),
            skill_rules_version: 0,
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
        self.turn_selected(action, job, 0, 1, stats, player_roll, enemy_roll, None, 99)
    }
    #[allow(clippy::too_many_arguments)]
    pub fn turn_selected(
        &mut self,
        action: Action,
        job: i16,
        school: i16,
        level: i32,
        stats: Stats,
        player_roll: i32,
        enemy_roll: i32,
        skill_id: Option<&str>,
        effect_roll: i32,
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
        let selected = if action == Action::Skill {
            Some(crate::skills::check(
                skill_id.unwrap_or(&format!("legacy_{job}")),
                job,
                school,
                level,
            )?)
        } else {
            None
        };
        if action != Action::Skill && skill_id.is_some() {
            return Err("INVALID_PVE_COMMAND");
        }
        if selected.is_some_and(|s| self.mp < s.mp_cost) {
            return Err("MP_INSUFFICIENT");
        }
        if action == Action::Potion && self.potions < 1 {
            return Err("NO_POTION");
        }
        if action == Action::Potion && self.hp >= stats.hp {
            return Err("HP_FULL");
        }
        if self.skill_rules_version == 0 {
            self.skills = crate::skills::State::new(job, school, level, self.enemy.level);
            self.skill_rules_version = 1;
        } else {
            // Refresh eligibility-derived passives in saved encounters without resetting buffs.
            let current = crate::skills::State::new(job, school, level, self.enemy.level);
            self.skills.passive_physical = current.passive_physical;
            self.skills.passive_magic = current.passive_magic;
        }
        self.skills.reset_turn();
        self.round += 1;
        self.revision += 1;
        let mut lines = vec![format!("第{}回合", self.round)];
        let mut damage = match action {
            Action::Attack => {
                self.skills.enemy_sleep = 0;
                let power = crate::attributes::for_attack(stats, job, false);
                crate::attributes::critical(stats, false, &mut self.skills,
                    (power.attack - self.enemy.defense + player_roll.clamp(-2, 2)).max(1), effect_roll)
            }
            Action::Skill => {
                let skill = selected.expect("selected skill");
                lines.push(format!("你施展{}。", skill.name));
                let damage = self.skills.cast(
                    skill,
                    crate::attributes::for_attack(stats, job, job == 2),
                    &mut self.hp,
                    &mut self.mp,
                    self.enemy.defense,
                    effect_roll,
                );
                crate::attributes::critical(stats, job == 2, &mut self.skills, damage, effect_roll)
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
        let dot = self.skills.after_player(&mut self.hp, stats.hp);
        damage += dot;
        if dot > 0 {
            lines.push(format!("持续效果造成{dot}点伤害。"));
        }
        if self.skills.last_healed > 0 {
            lines.push(format!("恢复{}点气血。", self.skills.last_healed));
        }
        self.skills.last_damage = damage.min(self.enemy_hp);
        if damage > 0 {
            self.enemy_hp = (self.enemy_hp - damage).max(0);
            lines.push(format!("你造成{damage}点伤害。"));
        }
        if self.enemy_hp == 0 {
            self.outcome = "victory".into();
            lines.push(format!("{}被击败！", self.enemy.name));
            self.skills.end_turn();
            return Ok(lines);
        }
        if self.skills.enemy_sleep > 0 {
            lines.push(format!("{}处于睡眠，无法行动。", self.enemy.name));
        } else {
            let mut incoming = (self.enemy.attack - stats.defense + enemy_roll.clamp(-2, 2)).max(1);
            let landed = crate::attributes::lands(None, Some(stats), false);
            if !landed { incoming = 0; }
            if action == Action::Guard {
                incoming = if landed { (incoming / 2).max(1) } else { 0 };
            }
            let (incoming, mut reflected) = if landed { self.skills.enemy_hit(incoming, false) } else { (0, 0) };
            self.skills.last_enemy_acted = true;
            self.skills.last_incoming = incoming;
            self.hp = (self.hp - incoming).max(0);
            lines.push(format!("{}出击，你受到{incoming}点伤害。", self.enemy.name));
            if landed && job == 0 && action == Action::Guard {
                reflected += 6;
            }
            reflected = reflected.min(self.enemy_hp);
            self.enemy_hp = (self.enemy_hp - reflected).max(0);
            self.skills.last_reflected = reflected;
            if reflected > 0 {
                lines.push(format!("反伤造成{reflected}点伤害。"));
            }
        }
        self.skills.end_turn();
        if self.hp == 0 {
            self.outcome = "defeat".into();
            lines.push("你力竭倒下，试炼进度保留，请以灵魂寻回尸体。".into());
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
