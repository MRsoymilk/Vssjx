//! Cooperative, server-owned PvE. Multipliers and five-seat cap are reconstruction.
use crate::{population::ResidentDefinition, pve_rules::Stats, skills};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
pub const MAX_MEMBERS: usize = 5;
pub const TURN_MS: i64 = 30_000;
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
}
impl Battle {
    pub fn new(
        map_id: String,
        fighters: Vec<Fighter>,
        source: Vec<ResidentDefinition>,
        now: i64,
    ) -> Self {
        assert!((2..=MAX_MEMBERS).contains(&fighters.len()) && !source.is_empty());
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
            lines: vec!["队伍遭遇战开始，全员各自选择指令。".into()],
        }
    }
    pub fn active(&self) -> bool {
        self.outcome == "active"
    }
    pub fn finish(&mut self, outcome: &str) {
        self.outcome = outcome.into();
        self.lines.push(
            match outcome {
                "victory" => "战斗胜利！全队获得分配奖励。",
                "defeat" => "战斗失败，全队恢复元气。",
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
        if self.fighters[self.turn].id != who {
            return Err("TEAM_NOT_YOUR_TURN");
        }
        if !matches!(action, "attack" | "skill" | "guard" | "potion") {
            return Err("INVALID_TEAM_COMMAND");
        }
        if action != "skill" && skill.is_some() {
            return Err("INVALID_TEAM_COMMAND");
        }
        let selected = if action == "skill" {
            Some(skills::check(
                skill.ok_or("INVALID_SKILL")?,
                self.fighters[self.turn].job,
                self.fighters[self.turn].school,
                self.fighters[self.turn].level,
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
        let actor = &self.fighters[self.turn];
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
        self.events.clear();
        self.lines = vec![format!("第{}回合 · {}行动", self.round, actor.name)];
        let i = self.turn;
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
                        actor.stats,
                        &mut actor.hp,
                        &mut actor.mp,
                        enemy.definition.defense,
                        roll,
                    );
                    let damage = actor.effects.critical(damage, roll).min(enemy.hp);
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
                    });
                    if mode == "self" {
                        break;
                    }
                }
            }
        } else if action == "attack" {
            let e = &mut self.enemies[target_index.unwrap()];
            let a = &self.fighters[i];
            let damage = a
                .effects
                .critical((a.stats.attack - e.definition.defense).max(1), roll)
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
            });
        } else if action == "guard" {
            self.fighters[i].guarding = true;
            let a = &mut self.fighters[i];
            a.mp = (a.mp + 5).min(a.stats.mp);
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
            });
        }
        let a = &mut self.fighters[i];
        a.effects.after_player(&mut a.hp, a.stats.hp);
        if self.enemies.iter().all(|e| e.hp == 0) {
            self.finish("victory");
        } else {
            let next = ((i + 1)..self.fighters.len()).find(|n| self.fighters[*n].hp > 0);
            if let Some(next) = next {
                self.turn = next;
            } else {
                self.enemy_round(roll);
                self.round += 1;
                self.turn = self.fighters.iter().position(|a| a.hp > 0).unwrap_or(0);
            }
        }
        self.revision += 1;
        self.last_action_ms = now;
        self.deadline_ms = now + TURN_MS;
        if self.active() && self.round > 60 {
            self.finish("fled");
        }
        Ok(())
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
            let incoming = (e.definition.attack - a.stats.defense).max(1);
            let incoming = if a.guarding {
                (incoming / 2).max(1)
            } else {
                incoming
            };
            let (incoming, reflected) = a.effects.enemy_hit(incoming, false);
            let reflected = reflected + if a.job == 0 && a.guarding { 6 } else { 0 };
            a.hp = (a.hp - incoming).max(0);
            e.hp = (e.hp - reflected).max(0);
            self.events.push(Event {
                actor: e.slot.clone(),
                target: a.id.to_string(),
                action: "attack".into(),
                skill: String::new(),
                damage: incoming,
                healed: 0,
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
