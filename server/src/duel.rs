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
pub const PLAYBACK_SECONDS: u64 = 4;
pub const MAX_ROUNDS: u64 = 50;

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
    pub speed: i32,
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
        let mut stats = Stats {
            hp: stat("hp")?,
            mp: stat("mp")?,
            attack: stat("attack")?,
            defense: stat("defense")?,
            attributes: serde_json::from_value(s["attributes"]["allocated"].clone())
                .map_err(|_| "DUEL_PROFILE_UNAVAILABLE")?,
            balance: serde_json::from_value(s["stats"].get("balance").cloned().unwrap_or(Value::Null)).map_err(|_|"DUEL_PROFILE_UNAVAILABLE")?,
        };
        let (job, school, level) = (
            number("job")? as i16,
            number("school")? as i16,
            number("level")? as i32,
        );
        if crate::skill_balance::revised(stats){stats.hp=stats.hp*crate::skill_balance::n("pvp_hp_bp")/10000;}
        let mut effects=skills::State::new(job,school,level,level);effects.enable_stun(stats);
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
            speed: 100
                + s["attributes"]["allocated"][3]
                    .as_i64()
                    .filter(|v| (0..=300).contains(v))
                    .ok_or("DUEL_PROFILE_UNAVAILABLE")? as i32,
            appearance,
            hp: stats.hp,
            mp: stats.mp,
            effects,
            guarding: false,
        })
    }
}
#[derive(Clone)]
struct Choice {
    action: String,
    skill: Option<String>,
}
#[derive(Clone, Serialize)]
pub struct Event {
    pub missed: bool,
    pub critical: bool,
    pub actor: Uuid,
    pub action: String,
    pub skill: String,
    pub damage: i32,
    pub reflected: i32,
    pub fighters: [Fighter; 2],
}
pub struct Battle {
    pub id: Uuid,
    pub fighters: [Fighter; 2],
    pub revision: u64,
    pub round: u64,
    pub decision_revision: u64,
    pub resolved_round: u64,
    choices: [Option<Choice>; 2],
    pub events: Vec<Event>,
    pub resume_at: Option<Instant>,
    pub winner: Option<Uuid>,
    pub reason: String,
    pub lines: Vec<String>,
    pub deadline: Instant,
    pub ended: Option<Instant>,
}
impl Battle {
    fn view(&self, who: Uuid, now: Instant) -> Value {
        let me = self.fighters.iter().position(|f| f.id == who).unwrap();
        crate::attributes::public_battle(json!({"id":self.id,"fighters":self.fighters,"revision":self.revision.to_string(),"round":self.round,"decision_revision":self.decision_revision.to_string(),"resolved_round":self.resolved_round,
            "phase":if self.ended.is_some(){"finished"}else if self.resume_at.is_some(){"resolving"}else{"planning"},
            "submitted":self.choices.each_ref().map(|c|c.is_some()),"your_choice":self.choices[me].as_ref().map(|c|json!({"action":c.action,"skill":c.skill})),
            "events":self.events,"winner":self.winner,"status":if self.ended.is_some(){"finished"}else{"active"},"reason":self.reason,"lines":self.lines,
            "remaining_ms":self.resume_at.unwrap_or(self.deadline).saturating_duration_since(now).as_millis().min(30000) as u64}))
    }
    pub fn finish(&mut self, winner: Option<Uuid>, reason: &str, now: Instant) {
        if self.ended.is_some() {
            return;
        }
        self.winner = winner;
        self.reason = reason.into();
        self.ended = Some(now);
        for f in &mut self.fighters{f.effects.enemy_stun=0;}
        self.resume_at = None;
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
        rolls: [i32; 3],
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
        if c.expected_revision.as_deref() != Some(self.decision_revision.to_string().as_str()) {
            return Err("DUEL_STALE_REVISION");
        }
        if c.action == "flee" {
            self.finish(Some(self.fighters[1 - me].id), "surrender", now);
            return Ok(());
        }
        if self.resume_at.is_some() {
            return Err("DUEL_RESOLVING");
        }
        if now >= self.deadline {
            return Err("DUEL_DECISION_EXPIRED");
        }
        if self.choices[me].is_some() {
            return Err("DUEL_ALREADY_SUBMITTED");
        }
        if !matches!(c.action.as_str(), "attack" | "skill" | "guard") {
            return Err("INVALID_DUEL_COMMAND");
        }
        if c.action == "skill" {
            let f = &self.fighters[me];
            let skill = skills::check(
                c.skill.as_deref().ok_or("INVALID_SKILL")?,
                f.job,
                f.school,
                f.level,
            )?;
            if f.mp < crate::skill_balance::cost(skill,f.stats) {
                return Err("MP_INSUFFICIENT");
            }
            if f.effects.remaining(&skill.id)>0{return Err("SKILL_COOLDOWN");}
        }
        self.choices[me] = Some(Choice {
            action: c.action.clone(),
            skill: c.skill.clone(),
        });
        self.revision += 1;
        if self.choices.iter().all(Option::is_some) {
            self.resolve(now, rolls);
        }
        Ok(())
    }
    fn check_end(&mut self, now: Instant) -> bool {
        let alive = self.fighters.each_ref().map(|f| f.hp > 0);
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
            true
        } else {
            false
        }
    }
    fn resolve(&mut self, now: Instant, rolls: [i32; 3]) {
        self.events.clear();
        self.lines = vec![format!("第{}回合，双方指令已锁定。", self.round)];
        self.resolved_round = self.round;
        for i in 0..2 {
            self.fighters[i].effects.reset_turn();
            // Guard is a round-wide defensive commitment, independent of initiative.
            self.fighters[i].guarding = self.choices[i].as_ref().unwrap().action == "guard"
                && self.fighters[1 - i].effects.enemy_sleep == 0
                && self.fighters[1 - i].effects.enemy_stun == 0;
        }
        let first = match self.fighters[0].speed.cmp(&self.fighters[1].speed) {
            std::cmp::Ordering::Greater => 0,
            std::cmp::Ordering::Less => 1,
            std::cmp::Ordering::Equal => (rolls[0].rem_euclid(2)) as usize,
        };
        for me in [first, 1 - first] {
            let choice = self.choices[me].as_ref().unwrap().clone();
            let skill = choice.skill.as_deref().and_then(skills::item);
            let (a, b) = self.fighters.split_at_mut(1);
            let (actor, enemy) = if me == 0 {
                (&mut a[0], &mut b[0])
            } else {
                (&mut b[0], &mut a[0])
            };
            let balanced=crate::skill_balance::revised(actor.stats);
            let dot = if balanced{0}else{(if enemy.effects.enemy_bleed > 0 {
                enemy.effects.bleed_damage
            } else {
                0
            }) + (if enemy.effects.enemy_poison > 0 {
                enemy.effects.poison_damage
            } else {
                0
            })};
            if !balanced{enemy.effects.enemy_bleed = (enemy.effects.enemy_bleed - 1).max(0);
            enemy.effects.enemy_poison = (enemy.effects.enemy_poison - 1).max(0);}
            actor.hp = (actor.hp - dot).max(0);
            let mut action = choice.action.clone();
            let mut used = String::new();
            let mut damage = 0;
            let mut missed=false;
            let mut reflected = 0;
            if dot > 0 {
                self.lines
                    .push(format!("{}受到{}点持续伤害。", actor.name, dot));
            }
            if actor.hp == 0 {
                action = "dot".into();
            } else if enemy.effects.consume_stun() {
                actor.guarding=false;
                action="stun".into();
                self.lines.push(format!("{}处于眩晕，跳过本次行动。",actor.name));
            } else if enemy.effects.enemy_sleep > 0 {
                action = "sleep".into();
                self.lines.push(format!("{}沉睡中，跳过行动。", actor.name));
            } else if choice.action == "skill"
                && (enemy.effects.enemy_silence > 0 || skill.is_none_or(|s| actor.mp < crate::skill_balance::cost(s,actor.stats)))
            {
                action = "fizzle".into();
                self.lines
                    .push(format!("{}的施法因封印或灵力不足而失败。", actor.name));
            } else {
                let roll = rolls[1 + me];
                let raw = match choice.action.as_str() {
                    "attack" => {
                        actor.mp=(actor.mp+crate::skill_balance::recovery(actor.stats,"basic_restore_bp",0)).min(actor.stats.mp);
                        if crate::attributes::lands(Some(actor.stats), Some(enemy.stats), actor.job==2&&actor.stats.balance.is_some()) {
                            actor.effects.enemy_sleep = 0;
                            let power = crate::attributes::for_attack(actor.stats, actor.job, actor.job==2&&actor.stats.balance.is_some());
                            crate::attributes::critical(
                                actor.stats, actor.job==2&&actor.stats.balance.is_some(), &mut actor.effects,
                                crate::attributes::direct_damage(power,crate::attributes::defense(enemy.stats,actor.job==2&&actor.stats.balance.is_some()),10000,0), roll,
                            )
                        } else {
                            missed=true;
                            0
                        }
                    }
                    "skill" => {
                        let s = skill.unwrap();
                        used = s.id.clone();
                        actor.effects.enemy_mp = enemy.mp;
                        let magical = actor.job == 2;
                        let directed = matches!(s.target.as_str(), "enemy" | "all_enemies");
                        if directed && !crate::attributes::lands(Some(actor.stats), Some(enemy.stats), magical) {
                            missed=true;
                            actor.mp -= crate::skill_balance::cost(s,actor.stats);
                            if balanced{actor.effects.mark(s);}
                            actor.effects.last_skill = s.id.clone();
                            0
                        } else {
                            let before_hp=actor.hp;let before_healed=actor.effects.last_healed;
                            let hit = actor.effects.cast(
                                s,
                                crate::attributes::for_attack(actor.stats, actor.job, magical),
                                &mut actor.hp,
                                &mut actor.mp,
                                crate::attributes::defense(enemy.stats,magical),
                                roll,
                            );
                            if balanced{
                                let actual=(actor.hp-before_hp)*crate::skill_balance::n("pvp_heal_bp")/10000;
                                actor.hp=before_hp+actual;actor.effects.last_healed=before_healed+actual;
                            }
                            if s.effect == "mana_steal" {
                                enemy.mp = actor.effects.enemy_mp;
                            }
                            crate::attributes::critical(actor.stats, magical, &mut actor.effects, hit, roll)
                        }
                    }
                    "guard" => {
                        actor.mp = (actor.mp + crate::skill_balance::recovery(actor.stats,"guard_restore_bp",5)).min(actor.stats.mp);
                        0
                    }
                    _ => 0,
                };
                let raw=if balanced{raw*crate::skill_balance::n("pvp_damage_bp")/10000}else{raw};
                let raw=crate::attributes::extra_reduction(raw,enemy.stats);
                let incoming = if enemy.guarding { raw / 2 } else { raw };
                (damage, reflected) = if incoming > 0 {
                    enemy
                        .effects
                        .enemy_hit(incoming, enemy.stats.attack, choice.action == "skill" && actor.job == 2)
                } else {
                    (0, 0)
                };
                enemy.hp = (enemy.hp - damage).max(0);
                actor.hp = (actor.hp - reflected).max(0);
                enemy.effects.last_incoming = damage;
                enemy.effects.last_reflected = reflected;
                actor.effects.last_missed=missed;enemy.effects.last_enemy_missed=missed;
                actor.effects.last_damage = damage;
                actor.effects.last_reflected = reflected;
                self.lines.push(format!(
                    "{}{}，造成{}点伤害。",
                    actor.name,
                    if action == "guard" {
                        "防御"
                    } else if action == "skill" {
                        skill.unwrap().name.as_str()
                    } else {
                        "攻击"
                    },
                    damage
                ));
                if reflected > 0 {
                    self.lines.push(format!("反弹{}点伤害。", reflected));
                }
            }
            self.events.push(Event {
                missed,
                critical: damage > 0 && self.fighters[me].effects.last_critical,
                actor: self.fighters[me].id,
                action,
                skill: used,
                damage,
                reflected,
                fighters: self.fighters.clone(),
            });
            if self.check_end(now) {
                break;
            }
        }
        if self.ended.is_none() {
            let mut dots=[0;2];
            for (i,f) in self.fighters.iter_mut().enumerate(){
                if crate::skill_balance::revised(f.stats){let before=f.hp;dots[i]=f.effects.end_balance_round(&mut f.hp,f.stats.hp)*crate::skill_balance::n("pvp_damage_bp")/10000;f.hp=before+(f.hp-before)*crate::skill_balance::n("pvp_heal_bp")/10000;f.effects.tick_balance();}
            }
            self.fighters[0].hp=(self.fighters[0].hp-crate::attributes::extra_reduction(dots[1],self.fighters[0].stats)).max(0);
            self.fighters[1].hp=(self.fighters[1].hp-crate::attributes::extra_reduction(dots[0],self.fighters[1].stats)).max(0);
            for f in &mut self.fighters {
                if f.effects.balance.is_none()&&f.effects.regen > 0 {
                    let heal = f.effects.regen_amount.min(f.stats.hp - f.hp);
                    f.hp += heal;
                    f.effects.regen -= 1;
                }
                let refreshed = skills::item(&f.effects.last_skill)
                    .map(|s| s.effect.as_str())
                    .unwrap_or("");
                for (name, n) in [
                    ("defense", &mut f.effects.defense),
                    ("crit", &mut f.effects.crit),
                    ("reflect_physical", &mut f.effects.reflect_physical),
                    ("reflect_magic", &mut f.effects.reflect_magic),
                ] {
                    if name != refreshed {
                        *n = (*n - 1).max(0);
                    }
                }
                f.effects.enemy_sleep = (f.effects.enemy_sleep - 1).max(0);
                f.effects.enemy_silence = (f.effects.enemy_silence - 1).max(0);
            }
            if let Some(e) = self.events.last_mut() {
                e.fighters = self.fighters.clone();
            }
            if self.check_end(now){self.revision+=1;return;}
            if self.round >= MAX_ROUNDS {
                self.finish(None, "round_limit", now);
            } else {
                self.resume_at = Some(now + Duration::from_secs(PLAYBACK_SECONDS));
            }
        }
        self.revision += 1;
    }
    fn tick(&mut self, now: Instant) -> bool {
        if self.ended.is_some() {
            return false;
        }
        if let Some(resume) = self.resume_at {
            if now < resume {
                return false;
            }
            self.resume_at = None;
            self.round += 1;
            self.decision_revision += 1;
            self.choices = [None, None];
            for f in &mut self.fighters {
                f.guarding = false;
            }
            self.deadline = now + Duration::from_secs(TURN_SECONDS);
            self.revision += 1;
            return true;
        }
        if now < self.deadline {
            return false;
        }
        for choice in &mut self.choices {
            if choice.is_none() {
                *choice = Some(Choice {
                    action: "guard".into(),
                    skill: None,
                });
            }
        }
        use rand::Rng;
        let mut rng = rand::thread_rng();
        self.resolve(
            now,
            [
                rng.gen_range(0..100),
                rng.gen_range(0..100),
                rng.gen_range(0..100),
            ],
        );
        self.lines.insert(0, "未提交的指令已默认防御。".into());
        true
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
                round: 1,
                decision_revision: 0,
                resolved_round: 0,
                choices: [None, None],
                events: vec![],
                resume_at: None,
                winner: None,
                reason: String::new(),
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
        rolls: [i32; 3],
    ) -> Result<(), &'static str> {
        let id = *self.slots.get(&who).ok_or("DUEL_NOT_FOUND")?;
        let b = self.battles.get_mut(&id).ok_or("DUEL_NOT_FOUND")?;
        b.act(who, c, now, rolls)?;
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
            .map(|b| b.view(id, now));
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
            } else if b.tick(now) {
                changed.extend(b.fighters.iter().map(|f| f.id));
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
