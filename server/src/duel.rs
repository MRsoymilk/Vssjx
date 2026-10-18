//! Consensual sparring. Combat is ephemeral; permanent resources are never written.
use crate::{pve_rules::Stats, skills};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    time::{Duration, Instant},
};
use uuid::Uuid;

pub const INVITE_SECONDS: u64 = 30;
pub const REJECT_SECONDS: i64 = 300;
pub const TURN_SECONDS: u64 = 30;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Command {
    pub request_id: Uuid,
    pub action: String,
    pub target: Option<Uuid>,
    pub invite_id: Option<Uuid>,
    pub battle_id: Option<Uuid>,
    pub expected_revision: Option<String>,
    pub skill: Option<String>,
}
impl Command {
    pub fn valid(&self) -> bool {
        self.request_id.get_version_num() == 4
            && match self.action.as_str() {
                "invite" => {
                    self.target.is_some()
                        && self.invite_id.is_none()
                        && self.battle_id.is_none()
                        && self.expected_revision.is_none()
                        && self.skill.is_none()
                }
                "accept" | "reject" | "cancel" => {
                    self.target.is_none()
                        && self.invite_id.is_some()
                        && self.battle_id.is_none()
                        && self.expected_revision.is_none()
                        && self.skill.is_none()
                }
                "attack" | "skill" | "guard" | "flee" => {
                    self.target.is_none()
                        && self.invite_id.is_none()
                        && self.battle_id.is_some()
                        && self
                            .expected_revision
                            .as_ref()
                            .is_some_and(|s| s.len() <= 20 && s.parse::<u64>().is_ok())
                        && (if self.action == "skill" {
                            self.skill.as_ref().is_some_and(|s| s.len() <= 32)
                        } else {
                            self.skill.is_none()
                        })
                }
                _ => false,
            }
    }
}
#[derive(Clone)]
pub struct Offer {
    pub id: Uuid,
    pub from: Uuid,
    pub to: Uuid,
    pub from_name: String,
    pub to_name: String,
    pub expires: Instant,
}
impl Offer {
    fn view(&self, now: Instant) -> Value {
        json!({"id":self.id,"from":self.from,"to":self.to,"from_name":self.from_name,"to_name":self.to_name,"remaining_ms":self.expires.saturating_duration_since(now).as_millis() as u64})
    }
}
#[derive(Clone, Serialize)]
pub struct Fighter {
    pub id: Uuid,
    pub name: String,
    pub job: i16,
    pub gender: i16,
    pub school: i16,
    pub level: i32,
    pub stats: Stats,
    pub appearance: [i32; 3],
    pub hp: i32,
    pub mp: i32,
    pub effects: skills::State,
    pub guarding: bool,
}
impl Fighter {
    pub fn from_snapshot(value: &Value, appearance: [i32; 3]) -> Result<Self, &'static str> {
        let s = &value["state"];
        if s["battle"]["outcome"] == "active" {
            return Err("BATTLE_ACTIVE");
        }
        let c = &s["character"];
        let number = |key: &str| c[key].as_i64().ok_or("DUEL_PROFILE_UNAVAILABLE");
        let stat = |key: &str| {
            s["stats"][key]
                .as_i64()
                .map(|v| v as i32)
                .ok_or("DUEL_PROFILE_UNAVAILABLE")
        };
        let stats = Stats {
            hp: stat("hp")?,
            mp: stat("mp")?,
            attack: stat("attack")?,
            defense: stat("defense")?,
        };
        let (job, school, level) = (
            number("job")? as i16,
            number("school")? as i16,
            number("level")? as i32,
        );
        Ok(Self {
            id: serde_json::from_value(c["id"].clone()).map_err(|_| "DUEL_PROFILE_UNAVAILABLE")?,
            name: c["display_name"]
                .as_str()
                .ok_or("DUEL_PROFILE_UNAVAILABLE")?
                .into(),
            job,
            gender: number("gender")? as i16,
            school,
            level,
            stats,
            appearance,
            hp: stats.hp,
            mp: stats.mp,
            effects: skills::State::new(job, school, level, level),
            guarding: false,
        })
    }
}
pub struct Battle {
    pub id: Uuid,
    pub fighters: [Fighter; 2],
    pub revision: u64,
    pub turn: usize,
    pub winner: Option<Uuid>,
    pub reason: String,
    pub last_actor: Option<Uuid>,
    pub last_action: String,
    pub last_skill: String,
    pub lines: Vec<String>,
    pub deadline: Instant,
    pub ended: Option<Instant>,
}
impl Battle {
    fn view(&self, now: Instant) -> Value {
        json!({"id":self.id,"fighters":self.fighters,"revision":self.revision.to_string(),"turn":self.fighters[self.turn].id,"winner":self.winner,"status":if self.ended.is_some(){"finished"}else{"active"},"reason":self.reason,"last_actor":self.last_actor,"last_action":self.last_action,"last_skill":self.last_skill,"lines":self.lines,"remaining_ms":self.deadline.saturating_duration_since(now).as_millis() as u64})
    }
    pub fn finish(&mut self, winner: Option<Uuid>, reason: &str, now: Instant) {
        if self.ended.is_some() {
            return;
        }
        if reason != "knockout" {
            self.last_actor = None;
            self.last_action = "flee".into();
            self.last_skill.clear();
        }
        self.winner = winner;
        self.reason = reason.into();
        self.ended = Some(now);
        self.revision += 1;
        self.lines.push(match winner {
            Some(id) => format!(
                "{}赢得了本次决斗。",
                self.fighters.iter().find(|f| f.id == id).unwrap().name
            ),
            None => "决斗结束，双方平局。".into(),
        });
    }
    pub fn act(
        &mut self,
        who: Uuid,
        c: &Command,
        now: Instant,
        roll: i32,
    ) -> Result<(), &'static str> {
        if self.ended.is_some() {
            return Err("DUEL_FINISHED");
        }
        let me = self
            .fighters
            .iter()
            .position(|f| f.id == who)
            .ok_or("DUEL_FORBIDDEN")?;
        if c.battle_id != Some(self.id) {
            return Err("DUEL_NOT_FOUND");
        }
        if c.expected_revision.as_deref() != Some(self.revision.to_string().as_str()) {
            return Err("DUEL_STALE_REVISION");
        }
        if c.action == "flee" {
            self.finish(Some(self.fighters[1 - me].id), "surrender", now);
            return Ok(());
        }
        if me != self.turn {
            return Err("DUEL_NOT_YOUR_TURN");
        }
        let skill = if c.action == "skill" {
            Some(skills::check(
                c.skill.as_deref().ok_or("INVALID_SKILL")?,
                self.fighters[me].job,
                self.fighters[me].school,
                self.fighters[me].level,
            )?)
        } else {
            None
        };
        let silence = self.fighters[1 - me].effects.enemy_silence > 0;
        if skill.is_some() && silence {
            return Err("DUEL_SILENCED");
        }
        if skill.is_some_and(|s| self.fighters[me].mp < s.mp_cost) {
            return Err("MP_INSUFFICIENT");
        }
        let (a, b) = self.fighters.split_at_mut(1);
        let (actor, enemy) = if me == 0 {
            (&mut a[0], &mut b[0])
        } else {
            (&mut b[0], &mut a[0])
        };
        actor.effects.reset_turn();
        enemy.effects.reset_turn();
        // Enemy-targeted counters belong to the caster. Tick on the affected player's turn.
        let dot = (if enemy.effects.enemy_bleed > 0 {
            enemy.effects.bleed_damage
        } else {
            0
        }) + (if enemy.effects.enemy_poison > 0 {
            enemy.effects.poison_damage
        } else {
            0
        });
        enemy.effects.enemy_bleed = (enemy.effects.enemy_bleed - 1).max(0);
        enemy.effects.enemy_poison = (enemy.effects.enemy_poison - 1).max(0);
        actor.hp = (actor.hp - dot).max(0);
        actor.guarding = false;
        self.lines = vec![format!("轮到{}行动。", actor.name)];
        if dot > 0 {
            self.lines.push(format!("持续伤害：{}。", dot));
        }
        let asleep = enemy.effects.enemy_sleep > 0;
        self.last_action = c.action.clone();
        self.last_skill = String::new();
        self.last_actor = Some(who);
        if actor.hp > 0 && !asleep {
            let damage = match c.action.as_str() {
                "attack" => {
                    actor.effects.enemy_sleep = 0;
                    actor
                        .effects
                        .critical((actor.stats.attack - enemy.stats.defense).max(1), roll)
                }
                "skill" => {
                    let s = skill.unwrap();
                    self.last_skill = s.id.clone();
                    actor.effects.enemy_mp = enemy.mp;
                    let damage = actor.effects.cast(
                        s,
                        actor.stats,
                        &mut actor.hp,
                        &mut actor.mp,
                        enemy.stats.defense,
                        roll,
                    );
                    if s.effect == "mana_steal" {
                        enemy.mp = actor.effects.enemy_mp;
                    }
                    actor.effects.critical(damage, roll)
                }
                "guard" => {
                    actor.guarding = true;
                    actor.mp = (actor.mp + 5).min(actor.stats.mp);
                    0
                }
                _ => return Err("INVALID_DUEL_COMMAND"),
            };
            let incoming = if enemy.guarding { damage / 2 } else { damage };
            let (hit, reflection) = if incoming > 0 {
                enemy
                    .effects
                    .enemy_hit(incoming, c.action == "skill" && actor.job == 2)
            } else {
                (0, 0)
            };
            enemy.hp = (enemy.hp - hit).max(0);
            actor.hp = (actor.hp - reflection).max(0);
            enemy.effects.last_incoming = hit;
            enemy.effects.last_reflected = reflection;
            actor.effects.last_damage = hit;
            actor.effects.last_reflected = reflection;
            self.lines.push(format!(
                "{}{}，造成{}点伤害。",
                actor.name,
                if c.action == "guard" {
                    "防御"
                } else if c.action == "skill" {
                    skill.unwrap().name.as_str()
                } else {
                    "攻击"
                },
                hit
            ));
            if reflection > 0 {
                self.lines.push(format!("反弹{}点伤害。", reflection));
            }
        } else if asleep {
            self.last_action = "sleep".into();
            self.lines.push(format!("{}沉睡中，跳过行动。", actor.name));
        }
        if actor.effects.regen > 0 {
            let heal = actor.effects.regen_amount.min(actor.stats.hp - actor.hp);
            actor.hp += heal;
            actor.effects.regen -= 1;
        }
        // Caster buffs last through the opponent's turn; enemy debuffs tick when applied.
        enemy.effects.end_turn();
        let alive = [self.fighters[0].hp > 0, self.fighters[1].hp > 0];
        self.revision += 1;
        self.turn = 1 - me;
        self.deadline = now + Duration::from_secs(TURN_SECONDS);
        if !alive[0] || !alive[1] {
            self.finish(
                if alive[0] {
                    Some(self.fighters[0].id)
                } else if alive[1] {
                    Some(self.fighters[1].id)
                } else {
                    None
                },
                "knockout",
                now,
            );
        } else if self.revision >= 100 {
            self.finish(None, "round_limit", now);
        }
        Ok(())
    }
}

#[derive(Default)]
pub struct Arena {
    pub offers: HashMap<Uuid, Offer>,
    pub battles: HashMap<Uuid, Battle>,
    pub slots: HashMap<Uuid, Uuid>,
    revisions: HashMap<Uuid, u64>,
    notices: HashMap<Uuid, String>,
    requests: HashMap<Uuid, VecDeque<(Uuid, String, Value)>>,
    last_request: HashMap<Uuid, Instant>,
}
impl Arena {
    pub fn touch(&mut self, ids: &[Uuid], notice: &str) {
        for id in ids {
            *self.revisions.entry(*id).or_default() += 1;
            if !notice.is_empty() {
                self.notices.insert(*id, notice.into());
            }
        }
    }
    pub fn active(&self, id: Uuid) -> bool {
        self.slots
            .get(&id)
            .and_then(|b| self.battles.get(b))
            .is_some_and(|b| b.ended.is_none())
    }
    pub fn offered(&self, id: Uuid) -> bool {
        self.offers.values().any(|o| o.from == id || o.to == id)
    }
    pub fn cached(&self, id: Uuid, c: &Command) -> Option<Value> {
        self.requests.get(&id)?.iter().find(|r|r.0==c.request_id).map(|r|if r.1==serde_json::to_string(c).unwrap(){r.2.clone()}else{json!({"type":"duel.result","request_id":c.request_id,"ok":false,"code":"DUEL_ID_CONFLICT","retry_after_ms":0})})
    }
    pub fn admit(&mut self, id: Uuid, now: Instant) -> bool {
        if self
            .last_request
            .get(&id)
            .is_some_and(|last| now.saturating_duration_since(*last) < Duration::from_millis(200))
        {
            return false;
        }
        self.last_request.insert(id, now);
        true
    }
    pub fn remember(&mut self, id: Uuid, c: &Command, result: Value) {
        let queue = self.requests.entry(id).or_default();
        queue.push_back((c.request_id, serde_json::to_string(c).unwrap(), result));
        while queue.len() > 32 {
            queue.pop_front();
        }
    }
    pub fn invite(
        &mut self,
        from: Uuid,
        to: Uuid,
        from_name: String,
        to_name: String,
        now: Instant,
    ) -> Result<Uuid, &'static str> {
        if from == to {
            return Err("DUEL_SELF");
        }
        if self.active(from) || self.active(to) || self.offered(from) || self.offered(to) {
            return Err("DUEL_BUSY");
        }
        let id = Uuid::new_v4();
        self.offers.insert(
            id,
            Offer {
                id,
                from,
                to,
                from_name,
                to_name,
                expires: now + Duration::from_secs(INVITE_SECONDS),
            },
        );
        self.touch(&[from, to], "决斗邀请已发送。");
        Ok(id)
    }
    pub fn remove_offer(&mut self, id: Uuid, notice: &str) {
        if let Some(o) = self.offers.remove(&id) {
            self.touch(&[o.from, o.to], notice);
        }
    }
    pub fn start(
        &mut self,
        offer: Uuid,
        who: Uuid,
        fighters: [Fighter; 2],
        first: usize,
        now: Instant,
    ) -> Result<Uuid, &'static str> {
        let o = self.offers.get(&offer).ok_or("DUEL_INVITE_EXPIRED")?;
        if o.to != who || fighters[0].id != o.from || fighters[1].id != o.to {
            return Err("DUEL_FORBIDDEN");
        }
        if o.expires <= now {
            return Err("DUEL_INVITE_EXPIRED");
        }
        if self.active(o.from) || self.active(o.to) {
            return Err("DUEL_BUSY");
        }
        let ids = [o.from, o.to];
        let id = Uuid::new_v4();
        self.offers.remove(&offer);
        self.battles.insert(
            id,
            Battle {
                id,
                fighters,
                revision: 0,
                turn: first,
                winner: None,
                reason: String::new(),
                last_actor: None,
                last_action: String::new(),
                last_skill: String::new(),
                lines: vec!["双方已确认，决斗开始。".into()],
                deadline: now + Duration::from_secs(TURN_SECONDS),
                ended: None,
            },
        );
        let old: Vec<_> = ids
            .into_iter()
            .filter_map(|who| self.slots.insert(who, id))
            .collect();
        for previous in old {
            if !self.slots.values().any(|battle| *battle == previous) {
                self.battles.remove(&previous);
            }
        }
        self.touch(&ids, "双方已确认，决斗开始。");
        Ok(id)
    }
    pub fn act(
        &mut self,
        who: Uuid,
        c: &Command,
        now: Instant,
        roll: i32,
    ) -> Result<(), &'static str> {
        let id = *self.slots.get(&who).ok_or("DUEL_NOT_FOUND")?;
        let b = self.battles.get_mut(&id).ok_or("DUEL_NOT_FOUND")?;
        b.act(who, c, now, roll)?;
        let ids = [b.fighters[0].id, b.fighters[1].id];
        self.touch(&ids, "");
        Ok(())
    }
    pub fn packet(&self, id: Uuid, since: Option<u64>, now: Instant) -> Option<(u64, Value)> {
        let rev = *self.revisions.get(&id).unwrap_or(&0);
        if since == Some(rev) {
            return None;
        }
        let incoming = self
            .offers
            .values()
            .find(|o| o.to == id)
            .map(|o| o.view(now));
        let outgoing = self
            .offers
            .values()
            .find(|o| o.from == id)
            .map(|o| o.view(now));
        let battle = self
            .slots
            .get(&id)
            .and_then(|b| self.battles.get(b))
            .map(|b| b.view(now));
        Some((
            rev,
            json!({"type":"duel.state","revision":rev.to_string(),"incoming":incoming,"outgoing":outgoing,"battle":battle,"notice":self.notices.get(&id).map_or("",String::as_str)}),
        ))
    }
    pub fn tick(&mut self, now: Instant, available: &HashMap<Uuid, (bool, bool)>) {
        let expired: Vec<_> = self
            .offers
            .values()
            .filter(|o| {
                o.expires <= now
                    || !available.get(&o.from).is_some_and(|v| v.0 && v.1)
                    || !available.get(&o.to).is_some_and(|v| v.0 && v.1)
            })
            .map(|o| o.id)
            .collect();
        for id in expired {
            self.remove_offer(id, "决斗邀请已失效。");
        }
        let mut changed = Vec::new();
        for b in self.battles.values_mut().filter(|b| b.ended.is_none()) {
            let lost = b
                .fighters
                .iter()
                .position(|f| !available.get(&f.id).is_some_and(|v| v.0));
            if let Some(i) = lost {
                b.finish(Some(b.fighters[1 - i].id), "disconnect", now);
            } else if b.deadline <= now {
                b.finish(Some(b.fighters[1 - b.turn].id), "turn_timeout", now);
            }
            if b.ended.is_some() {
                changed.extend(b.fighters.iter().map(|f| f.id));
            }
        }
        self.touch(&changed, "");
        let old: Vec<_> = self
            .battles
            .values()
            .filter(|b| {
                b.ended
                    .is_some_and(|t| now.saturating_duration_since(t) >= Duration::from_secs(60))
            })
            .map(|b| b.id)
            .collect();
        for id in old {
            self.battles.remove(&id);
            let ids: Vec<_> = self
                .slots
                .iter()
                .filter(|(_, b)| **b == id)
                .map(|(a, _)| *a)
                .collect();
            for who in &ids {
                self.slots.remove(who);
            }
            self.touch(&ids, "");
        }
        self.requests.retain(|id, _| available.contains_key(id));
        self.last_request.retain(|id, _| available.contains_key(id));
        self.revisions.retain(|id, _| available.contains_key(id));
        self.notices.retain(|id, _| available.contains_key(id));
    }
}
