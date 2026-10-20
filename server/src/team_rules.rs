//! Cooperative, server-owned PvE. Multipliers and five-seat cap are reconstruction.
use crate::{population::ResidentDefinition, pve_rules::Stats, skills};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use uuid::Uuid;
pub const MAX_MEMBERS: usize = 5;
pub const TURN_MS: i64 = 30_000;
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Intent {
    pub action: String,
    pub target: Option<String>,
    pub skill: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Fighter {
    pub id: Uuid,
    pub name: String,
    pub job: i16,
    pub gender: i16,
    pub school: i16,
    pub level: i32,
    pub appearance: [i32; 3],
    pub stats: Stats,
    pub hp: i32,
    pub mp: i32,
    pub potions: i32,
    pub effects: skills::State,
    pub guarding: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Enemy {
    pub slot: String,
    pub definition: ResidentDefinition,
    pub hp: i32,
    pub effects: skills::State,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Event {
    #[serde(default)]
    pub critical: bool,
    pub actor: String,
    pub target: String,
    pub action: String,
    pub skill: String,
    pub damage: i32,
    pub healed: i32,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Battle {
    pub id: Uuid,
    pub map_id: String,
    pub fighters: Vec<Fighter>,
    pub enemies: Vec<Enemy>,
    pub turn: usize,
    pub round: i32,
    pub revision: u64,
    pub outcome: String,
    pub deadline_ms: i64,
    pub last_action_ms: i64,
    pub events: Vec<Event>,
    pub lines: Vec<String>,
    #[serde(default)]
    pub commands: BTreeMap<Uuid, Intent>,
    #[serde(default)]
    pub round_revision: u64,
    #[serde(default)]
    pub events_revision: u64,
    #[serde(default)]
    pub selection_starts_ms: i64,
}
impl Battle {
    pub fn new(
        map_id: String,
        fighters: Vec<Fighter>,
        source: Vec<ResidentDefinition>,
        now: i64,
    ) -> Self {
        assert!((1..=MAX_MEMBERS).contains(&fighters.len()) && !source.is_empty());
        let extra = fighters.len() as i32 - 1;
        let enemies = source
            .into_iter()
            .take(5)
            .enumerate()
            .map(|(i, mut d)| {
                d.hp = (d.hp * (100 + 35 * extra) + 99) / 100;
                d.attack = (d.attack * (100 + 15 * extra) + 99) / 100;
                d.defense = (d.defense * (100 + 10 * extra) + 99) / 100;
                Enemy {
                    slot: format!("m{i}"),
                    hp: d.hp,
                    effects: skills::State {
                        enemy_mp: 30 + d.level * 2,
                        ..Default::default()
                    },
                    definition: d,
                }
            })
            .collect();
        Self {
            id: Uuid::new_v4(),
            map_id,
            fighters,
            enemies,
            turn: 0,
            round: 1,
            revision: 0,
            outcome: "active".into(),
            deadline_ms: now + TURN_MS,
            last_action_ms: now,
            events: vec![],
            lines: vec!["遭遇战开始，参战成员各自选择指令。".into()],
            commands: BTreeMap::new(),
            round_revision: 0,
            events_revision: 0,
            selection_starts_ms: now,
        }
    }
    pub fn active(&self) -> bool {
        self.outcome == "active"
    }
    pub fn finish(&mut self, outcome: &str) {
        self.outcome = outcome.into();
        self.lines.push(
            match outcome {
                "victory" => "战斗胜利！参战成员获得分配奖励。",
                "defeat" => "战斗失败，倒下的成员化为灵魂，请从本地图复活点寻回尸体。",
                _ => "队伍退出本次战斗，无击败奖励。",
            }
            .into(),
        );
    }
    pub fn act(
        &mut self,
        who: Uuid,
        action: &str,
        target: Option<&str>,
        skill: Option<&str>,
        now: i64,
        roll: i32,
    ) -> Result<(), &'static str> {
        if !self.active() {
            return Err("BATTLE_FINISHED");
        }
        if now < self.selection_starts_ms {
            return Err("TEAM_PLAYBACK_ACTIVE");
        }
        if now >= self.deadline_ms {
            return Err("TEAM_ROUND_EXPIRED");
        }
        let i = self
            .fighters
            .iter()
            .position(|f| f.id == who && f.hp > 0)
            .ok_or("TEAM_NOT_PARTICIPATING")?;
        if self.commands.contains_key(&who) {
            return Err("TEAM_COMMAND_LOCKED");
        }
        self.validate(i, action, target, skill)?;
        self.commands.insert(
            who,
            Intent {
                action: action.into(),
                target: target.map(str::to_owned),
                skill: skill.map(str::to_owned),
            },
        );
        self.revision += 1;
        self.last_action_ms = now;
        if self
            .fighters
            .iter()
            .filter(|f| f.hp > 0)
            .all(|f| self.commands.contains_key(&f.id))
        {
            self.resolve_round(now, roll);
        } else {
            self.turn = self
                .fighters
                .iter()
                .position(|f| f.hp > 0 && !self.commands.contains_key(&f.id))
                .unwrap_or(0);
        }
        Ok(())
    }
    fn validate(
        &self,
        i: usize,
        action: &str,
        target: Option<&str>,
        skill: Option<&str>,
    ) -> Result<(), &'static str> {
        if !matches!(action, "attack" | "skill" | "guard" | "potion") {
            return Err("INVALID_TEAM_COMMAND");
        }
        if action != "skill" && skill.is_some() {
            return Err("INVALID_TEAM_COMMAND");
        }
        let selected = if action == "skill" {
            Some(skills::check(
                skill.ok_or("INVALID_SKILL")?,
                self.fighters[i].job,
                self.fighters[i].school,
                self.fighters[i].level,
            )?)
        } else {
            None
        };
        let mode = selected.map_or("enemy", |s| s.target.as_str());
        let target_index = if action == "attack"
            || (action == "skill" && matches!(mode, "enemy" | "all_enemies"))
        {
            Some(
                self.enemies
                    .iter()
                    .position(|e| Some(e.slot.as_str()) == target && e.hp > 0)
                    .ok_or("INVALID_BATTLE_TARGET")?,
            )
        } else {
            None
        };
        let actor = &self.fighters[i];
        if selected.is_some_and(|s| actor.mp < s.mp_cost) {
            return Err("MP_INSUFFICIENT");
        }
        if action == "potion" && (actor.potions == 0 || actor.hp >= actor.stats.hp) {
            return Err(if actor.potions == 0 {
                "NO_POTION"
            } else {
                "HP_FULL"
            });
        }
        let _ = target_index;
        Ok(())
    }
    /// One shared deadline; missing/disconnected players guard together, not one per 30s.
    pub fn expire(&mut self, now: i64, roll: i32) -> bool {
        if !self.active() || now < self.deadline_ms {
            return false;
        }
        self.resolve_round(now, roll);
        true
    }
    fn resolve_round(&mut self, now: i64, roll: i32) {
        self.events.clear();
        self.lines = vec![format!(
            "第{}回合 · 指令收集结束，按站位依次行动。",
            self.round
        )];
        let commands = std::mem::take(&mut self.commands);
        for i in 0..self.fighters.len() {
            if self.fighters[i].hp <= 0 {
                continue;
            }
            let who = self.fighters[i].id;
            let default = Intent {
                action: "guard".into(),
                target: None,
                skill: None,
            };
            let mut command = commands.get(&who).cloned().unwrap_or(default.clone());
            // Earlier actors may kill a chosen enemy. Retarget deterministically, without losing MP.
            if command
                .target
                .as_ref()
                .is_some_and(|id| !self.enemies.iter().any(|e| &e.slot == id && e.hp > 0))
            {
                command.target = self
                    .enemies
                    .iter()
                    .find(|e| e.hp > 0)
                    .map(|e| e.slot.clone());
            }
            if self
                .validate(
                    i,
                    &command.action,
                    command.target.as_deref(),
                    command.skill.as_deref(),
                )
                .is_err()
            {
                command = default;
            }
            self.execute_actor(i, &command, (roll + i as i32 * 17) % 100);
            if self.enemies.iter().all(|e| e.hp == 0) {
                self.finish("victory");
                break;
            }
        }
        if self.active() {
            self.enemy_round(roll);
        }
        self.round += 1;
        self.turn = self.fighters.iter().position(|f| f.hp > 0).unwrap_or(0);
        self.revision += 1;
        self.round_revision = self.revision;
        self.events_revision = self.revision;
        // A separate presentation allowance never consumes the next 30-second input window.
        let groups = self
            .events
            .iter()
            .enumerate()
            .filter(|(n, e)| {
                *n == 0
                    || e.actor != self.events[n - 1].actor
                    || e.action != self.events[n - 1].action
                    || e.skill != self.events[n - 1].skill
            })
            .count() as i64;
        self.selection_starts_ms = now + groups * 3000 + 1000;
        self.deadline_ms = self.selection_starts_ms + TURN_MS;
        if self.active() && self.round > 60 {
            self.finish("fled");
        }
    }
    fn execute_actor(&mut self, i: usize, command: &Intent, roll: i32) {
        let who = self.fighters[i].id;
        let action = command.action.as_str();
        let selected = command.skill.as_deref().and_then(skills::item);
        let mode = selected.map_or("enemy", |s| s.target.as_str());
        let target_index = self
            .enemies
            .iter()
            .position(|e| Some(e.slot.as_str()) == command.target.as_deref() && e.hp > 0);
        self.fighters[i].effects.reset_turn();
        self.fighters[i].guarding = false;
        if let Some(s) = selected {
            let targets: Vec<usize> = if mode == "all_enemies" {
                self.enemies
                    .iter()
                    .enumerate()
                    .filter(|(_, e)| e.hp > 0)
                    .map(|(n, _)| n)
                    .collect()
            } else {
                vec![target_index.unwrap_or(0)]
            };
            if mode == "all_allies" {
                self.fighters[i].mp -= s.mp_cost;
                for ally in self.fighters.iter_mut().filter(|a| a.hp > 0) {
                    let mut temporary_mp = s.mp_cost;
                    let old = ally.hp;
                    ally.effects
                        .cast(s, ally.stats, &mut ally.hp, &mut temporary_mp, 0, roll);
                    self.events.push(Event {
                        actor: who.to_string(),
                        target: ally.id.to_string(),
                        action: "skill".into(),
                        skill: s.id.clone(),
                        damage: 0,
                        healed: ally.hp - old,
                        critical: false,
                    });
                }
            } else {
                for (n, t) in targets.into_iter().enumerate() {
                    let actor = &mut self.fighters[i];
                    let enemy = &mut self.enemies[t];
                    let old = actor.hp;
                    // Enemy debuffs belong to each enemy, self buffs to each ally.
                    Self::enemy_effects(&enemy.effects, &mut actor.effects);
                    if n > 0 {
                        actor.mp += s.mp_cost;
                    }
                    let damage = actor.effects.cast(
                        s,
                        crate::attributes::for_attack(actor.stats, actor.job, actor.job == 2),
                        &mut actor.hp,
                        &mut actor.mp,
                        enemy.definition.defense,
                        roll,
                    );
                    let damage = crate::attributes::critical(
                        actor.stats,
                        actor.job == 2,
                        &mut actor.effects,
                        damage,
                        roll,
                    )
                    .min(enemy.hp);
                    Self::enemy_effects(&actor.effects, &mut enemy.effects);
                    Self::enemy_effects(&skills::State::default(), &mut actor.effects);
                    enemy.hp -= damage;
                    self.events.push(Event {
                        actor: who.to_string(),
                        target: if mode == "self" {
                            who.to_string()
                        } else {
                            enemy.slot.clone()
                        },
                        action: action.into(),
                        skill: s.id.clone(),
                        damage,
                        healed: actor.hp - old,
                        critical: damage > 0 && actor.effects.last_critical,
                    });
                    if mode == "self" {
                        break;
                    }
                }
            }
        } else if action == "attack" {
            let e = &mut self.enemies[target_index.unwrap()];
            let a = &mut self.fighters[i];
            let power = crate::attributes::for_attack(a.stats, a.job, false);
            let damage = crate::attributes::critical(
                a.stats,
                false,
                &mut a.effects,
                (power.attack - e.definition.defense).max(1),
                roll,
            )
            .min(e.hp);
            e.hp -= damage;
            e.effects.enemy_sleep = 0;
            self.events.push(Event {
                actor: who.to_string(),
                target: e.slot.clone(),
                action: action.into(),
                skill: String::new(),
                damage,
                healed: 0,
                critical: damage > 0 && a.effects.last_critical,
            });
        } else if action == "guard" {
            self.fighters[i].guarding = true;
            let a = &mut self.fighters[i];
            a.mp = (a.mp + 5).min(a.stats.mp);
            self.events.push(Event {
                actor: who.to_string(),
                target: who.to_string(),
                action: "guard".into(),
                skill: String::new(),
                damage: 0,
                healed: 0,
                critical: false,
            });
        } else {
            let a = &mut self.fighters[i];
            a.potions -= 1;
            let healed = 45.min(a.stats.hp - a.hp);
            a.hp += healed;
            self.events.push(Event {
                actor: who.to_string(),
                target: who.to_string(),
                action: action.into(),
                skill: String::new(),
                damage: 0,
                healed,
                critical: false,
            });
        }
        let a = &mut self.fighters[i];
        a.effects.after_player(&mut a.hp, a.stats.hp);
    }
    fn enemy_effects(from: &skills::State, to: &mut skills::State) {
        to.enemy_mp = from.enemy_mp;
        to.enemy_bleed = from.enemy_bleed;
        to.bleed_damage = from.bleed_damage;
        to.enemy_poison = from.enemy_poison;
        to.poison_damage = from.poison_damage;
        to.enemy_sleep = from.enemy_sleep;
        to.enemy_silence = from.enemy_silence;
    }
    fn enemy_round(&mut self, roll: i32) {
        for (n, e) in self.enemies.iter_mut().enumerate() {
            if e.hp <= 0 {
                continue;
            }
            let dot = if e.effects.enemy_bleed > 0 {
                e.effects.bleed_damage
            } else {
                0
            } + if e.effects.enemy_poison > 0 {
                e.effects.poison_damage
            } else {
                0
            };
            e.hp = (e.hp - dot).max(0);
            e.effects.enemy_bleed = (e.effects.enemy_bleed - 1).max(0);
            e.effects.enemy_poison = (e.effects.enemy_poison - 1).max(0);
            if e.hp == 0 {
                continue;
            }
            if e.effects.enemy_sleep > 0 {
                e.effects.enemy_sleep -= 1;
                continue;
            }
            let alive: Vec<_> = self
                .fighters
                .iter()
                .enumerate()
                .filter(|(_, a)| a.hp > 0)
                .map(|(i, _)| i)
                .collect();
            if alive.is_empty() {
                break;
            }
            let i = alive[((roll.max(0) as usize) + n + self.round as usize) % alive.len()];
            let a = &mut self.fighters[i];
            let landed = crate::attributes::lands(None, Some(a.stats), false);
            let incoming = if landed {
                (e.definition.attack - a.stats.defense).max(1)
            } else {
                0
            };
            let incoming = if a.guarding && landed {
                (incoming / 2).max(1)
            } else {
                incoming
            };
            let (incoming, reflected) = if landed {
                a.effects.enemy_hit(incoming, false)
            } else {
                (0, 0)
            };
            let reflected = reflected
                + if landed && a.job == 0 && a.guarding {
                    6
                } else {
                    0
                };
            a.hp = (a.hp - incoming).max(0);
            e.hp = (e.hp - reflected).max(0);
            self.events.push(Event {
                actor: e.slot.clone(),
                target: a.id.to_string(),
                action: "attack".into(),
                skill: String::new(),
                damage: incoming,
                healed: 0,
                critical: false,
            });
        }
        for ally in &mut self.fighters {
            ally.effects.end_turn();
        }
        if self.fighters.iter().all(|a| a.hp == 0) {
            self.finish("defeat");
        } else if self.enemies.iter().all(|e| e.hp == 0) {
            self.finish("victory");
        }
    }
}
