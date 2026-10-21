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
    #[serde(default, skip_serializing_if="Option::is_none")]
    pub elite: Option<crate::monster_combat::Elite>,
    pub slot: String,
    pub definition: ResidentDefinition,
    pub hp: i32,
    pub effects: skills::State,
    #[serde(default,skip_serializing_if="BTreeMap::is_empty")]
    pub dots:BTreeMap<String,(i32,i32)>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Event {
    #[serde(default)]
    pub missed: bool,
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
    #[serde(default)]
    pub monster_revision: u8,
    #[serde(default, skip_serializing_if="BTreeMap::is_empty")]
    pub wounds: BTreeMap<String, (i32, i32)>,
}
impl Battle {
    pub fn new(
        map_id: String,
        mut fighters: Vec<Fighter>,
        source: Vec<ResidentDefinition>,
        now: i64,
    ) -> Self {
        assert!((1..=MAX_MEMBERS).contains(&fighters.len()) && !source.is_empty());
        let extra = fighters.len() as i32 - 1;
        let balanced=fighters.iter().all(|f|f.stats.balance.is_some());
        for f in &mut fighters{f.effects.activate(f.stats);}
        let mut enemies:Vec<Enemy> = source
            .into_iter()
            .take(5)
            .enumerate()
            .map(|(i, mut d)| {
                if balanced{d=crate::skill_balance::monster(d);}
                if !balanced{
                    d.hp = (d.hp * (100 + 35 * extra) + 99) / 100;
                    d.attack = (d.attack * (100 + 15 * extra) + 99) / 100;
                    d.defense = (d.defense * (100 + 10 * extra) + 99) / 100;
                }
                Enemy {
                    elite: None,
                    slot: format!("m{i}"),
                    hp: d.hp,
                    effects: skills::State {
                        enemy_mp: 30 + d.level * 2,
                        ..Default::default()
                    },
                    definition: d,
                    dots:BTreeMap::new(),
                }
            })
            .collect();
        if balanced{
            if let Some(boss)=enemies.iter().find(|e|e.definition.kind=="boss"||e.definition.id=="boss"){
                let budget=crate::combat_balance::boss_hp(boss.definition.hp as i64,fighters.len() as i64).unwrap() as i32;
                let total:i64=enemies.iter().map(|e|e.hp as i64).sum();let mut left=budget;let count=enemies.len();
                for (i,e) in enemies.iter_mut().enumerate(){let hp=if i+1==count{left}else{((e.hp as i64*budget as i64)/total) as i32};e.hp=hp.max(1);e.definition.hp=e.hp;left-=hp;}
            }
        }
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
            monster_revision: 1,
            wounds: BTreeMap::new(),
        }
    }
    pub fn empower_hunt(&mut self) {
        let party=self.fighters.len();
        let e=&mut self.enemies[0];
        crate::monster_combat::empower(&mut e.definition,party);e.hp=e.definition.hp;
        e.elite=Some(crate::monster_combat::Elite {party_size:party,revives_left:crate::monster_combat::elite_n(party,"revives")});
        self.monster_revision=2;
        self.lines.push("同图同种怪连续挑战达到5场，精英现身！警惕连击、暴击、流血与妖躯复生。".into());
    }
    pub fn elite_hunt(&self)->bool {self.enemies.iter().any(|e|e.elite.is_some())}
    fn revive_fallen(&mut self) {
        if self.fighters.iter().all(|f|f.hp==0) {return;}
        for e in &mut self.enemies {
            if let Some(elite)=e.elite.as_mut() {
                if e.hp==0 && elite.revives_left>0 {
                    elite.revives_left-=1;
                    e.hp=(e.definition.hp*crate::monster_combat::elite_n(elite.party_size,"revive_bp")/10000).max(1);
                    e.effects=skills::State {enemy_mp:30+e.definition.level*2,..Default::default()};e.dots.clear();
                    self.events.push(Event {missed:false,actor:e.slot.clone(),target:e.slot.clone(),action:"revive".into(),skill:"monster_rebirth".into(),damage:0,healed:e.hp,critical:false});
                    self.lines.push(format!("精英·{}妖躯复生，剩余{}次复活。",e.definition.name,elite.revives_left));
                }
            }
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
        if selected.is_some_and(|s| actor.mp < crate::skill_balance::cost(s,actor.stats)) {
            return Err("MP_INSUFFICIENT");
        }
        if selected.is_some_and(|s|actor.effects.remaining(&s.id)>0){return Err("SKILL_COOLDOWN");}
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
            self.revive_fallen();
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
                    || e.action != "skill"
                    || e.target == self.events[n - 1].target
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
        let cost=selected.map_or(0,|s|crate::skill_balance::cost(s,self.fighters[i].stats));
        let mode = selected.map_or("enemy", |s| s.target.as_str());
        let target_index = self
            .enemies
            .iter()
            .position(|e| Some(e.slot.as_str()) == command.target.as_deref() && e.hp > 0);
        self.fighters[i].effects.reset_turn();
        if let Some(b)=self.fighters[i].effects.balance.as_mut(){b.targets=self.enemies.iter().filter(|e|e.hp>0).count() as i32;}
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
                self.fighters[i].mp -= cost;
                for ally in self.fighters.iter_mut().filter(|a| a.hp > 0) {
                    let mut temporary_mp = crate::skill_balance::cost(s,ally.stats);
                    let cooldowns=ally.effects.balance.as_ref().map(|b|b.cooldowns.clone());
                    let old = ally.hp;
                    let mut cast_stats=ally.stats;
                    if ally.id!=who{if let Some(b)=cast_stats.balance.as_mut(){b.builds=Default::default();}}
                    ally.effects
                        .cast(s, cast_stats, &mut ally.hp, &mut temporary_mp, 0, roll);
                    if ally.id!=who{if let Some(b)=ally.effects.balance.as_mut(){b.cooldowns=cooldowns.unwrap_or_default();}}
                    self.events.push(Event {missed:false,
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
                        actor.mp += cost;
                    }
                    let missed=crate::skill_balance::revised(actor.stats)&&s.damage_percent>0&&matches!(mode,"enemy"|"all_enemies")&&!crate::attributes::lands(Some(actor.stats),None,actor.job==2);
                    actor.effects.last_missed=missed;
                    let damage = if missed{actor.effects.miss(s,actor.stats,&mut actor.mp);0}else{actor.effects.cast(
                        s,
                        crate::attributes::for_attack(actor.stats, actor.job, actor.job == 2),
                        &mut actor.hp,
                        &mut actor.mp,
                        enemy.definition.defense,
                        roll,
                    )};
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
                    if !missed&&crate::skill_balance::revised(actor.stats)&&matches!(s.effect.as_str(),"bleed"|"poison"){
                        let ticks=if s.effect=="bleed"{enemy.effects.enemy_bleed}else{enemy.effects.enemy_poison};
                        let amount=if s.effect=="bleed"{enemy.effects.bleed_damage}else{enemy.effects.poison_damage};
                        enemy.dots.insert(format!("{who}/{}",s.effect),(ticks,amount));
                    }
                    self.events.push(Event {missed,
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
            a.mp=(a.mp+crate::skill_balance::recovery(a.stats,"basic_restore_bp",0)).min(a.stats.mp);
            let power = crate::attributes::for_attack(a.stats, a.job, a.job==2&&a.stats.balance.is_some());
            let missed=crate::skill_balance::revised(a.stats)&&!crate::attributes::lands(Some(a.stats),None,a.job==2);
            a.effects.last_missed=missed;
            let damage = if missed{0}else{crate::attributes::critical(
                a.stats,
                a.job==2&&a.stats.balance.is_some(),
                &mut a.effects,
                crate::attributes::direct_damage(power,e.definition.defense,10000,0),
                roll,
            )}
            .min(e.hp);
            e.hp -= damage;
            if !missed{e.effects.enemy_sleep = 0;}
            self.events.push(Event {missed,
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
            a.mp = (a.mp + crate::skill_balance::recovery(a.stats,"guard_restore_bp",5)).min(a.stats.mp);
            self.events.push(Event {missed:false,
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
            let healed = crate::skill_balance::potion(a.stats).min(a.stats.hp - a.hp);
            a.hp += healed;
            self.events.push(Event {missed:false,
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
        if from.balance.is_none(){if let Some(b)=to.balance.as_mut(){b.control_protection=0;}}
        if let Some(b)=from.balance.as_ref(){to.balance.get_or_insert_with(Default::default).control_protection=b.control_protection;}
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
            let balanced=self.fighters.iter().any(|f|crate::skill_balance::revised(f.stats));
            let dot = if balanced{0}else{(if e.effects.enemy_bleed > 0 {
                e.effects.bleed_damage
            } else {
                0
            }) + if e.effects.enemy_poison > 0 {
                e.effects.poison_damage
            } else {
                0
            }};
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
            let magical=balanced&&crate::skill_balance::monster_magical(&e.definition,self.round,e.effects.enemy_mp,e.effects.enemy_silence>0);
            let plan=crate::monster_combat::elite_plan(e.elite.as_ref(),&e.definition, if self.monster_revision>0 {(roll+n as i32*31).rem_euclid(100)}else{99},magical,e.effects.enemy_silence>0);
            if plan.magical{e.effects.enemy_mp-=10;}
            let chosen = alive[((roll.max(0) as usize) + n + self.round as usize) % alive.len()];
            let targets = if plan.all {alive} else {vec![chosen]};
            if !plan.skill.is_empty(){self.lines.push(format!("{}施展{}！",e.definition.name,crate::monster_combat::name(&plan.skill)));}
            for hit in 0..plan.hits {
                if e.hp<=0 {break;}
                for &i in &targets {
                    let a=&mut self.fighters[i];
                    if a.hp<=0 || e.hp<=0 {continue;}
                    let landed=crate::attributes::lands(None,Some(a.stats),plan.magical);
                    a.effects.last_enemy_missed=!landed;
                    let raw=if landed{crate::attributes::incoming(e.definition.attack,e.definition.level,a.stats,plan.magical,0)*plan.coefficient/10000}else{0};
                    let (incoming,critical)=if self.monster_revision>0{crate::monster_combat::elite_critical(e.elite.as_ref(),&e.definition,raw,(roll*37+n as i32*19+hit as i32*43+i as i32*11).rem_euclid(100))}else{(raw,false)};
                    let incoming=if landed&&a.guarding{(incoming/2).max(1)}else{incoming};
                    let (incoming,reflected)=if landed{a.effects.enemy_hit(incoming.max(1),plan.magical)}else{(0,0)};
                    let reflected=(reflected+if landed&&a.job==0&&a.guarding{6}else{0}).min(e.hp);
                    let damage=incoming.min(a.hp);
                    a.hp=(a.hp-incoming).max(0);e.hp-=reflected;
                    self.events.push(Event{missed:!landed,actor:e.slot.clone(),target:a.id.to_string(),action:if plan.skill.is_empty(){"attack"}else{"skill"}.into(),skill:plan.skill.clone(),damage,healed:0,critical});
                    if reflected>0{self.events.push(Event{missed:false,actor:a.id.to_string(),target:e.slot.clone(),action:"dot".into(),skill:String::new(),damage:reflected,healed:0,critical:false});}
                    if plan.bleed&&damage>0&&a.hp>0{
                        let amount=(incoming*crate::monster_combat::n("bleed_bp")/10000).max(1);
                        let wound=self.wounds.entry(a.id.to_string()).or_insert((0,0));
                        wound.0=crate::monster_combat::n("bleed_rounds");wound.1=wound.1.max(amount);
                        self.lines.push(format!("{}受到撕裂，流血{}回合。",a.name,wound.0));
                    }
                }
            }
        }
        for ally in &mut self.fighters {
            if ally.hp>0{let before=ally.hp;ally.effects.end_balance_round(&mut ally.hp,ally.stats.hp);
                if ally.hp>before{self.events.push(Event{missed:false,actor:ally.id.to_string(),target:ally.id.to_string(),action:"regen".into(),skill:String::new(),damage:0,healed:ally.hp-before,critical:false});}
            }
            if let Some((ticks,amount))=self.wounds.get_mut(&ally.id.to_string()){
                if *ticks>0&&ally.hp>0{let damage=(*amount).min(ally.hp);ally.hp-=damage;*ticks-=1;
                    self.events.push(Event{missed:false,actor:ally.id.to_string(),target:ally.id.to_string(),action:"dot".into(),skill:"monster_bleed".into(),damage,healed:0,critical:false});
                }
            }
            ally.effects.end_turn();
        }
        self.wounds.retain(|_,(ticks,_)|*ticks>0);
        for e in &mut self.enemies{
            if !e.dots.is_empty(){let mut total=0;for (ticks,amount) in e.dots.values_mut(){if *ticks>0{total+=*amount;*ticks-=1;}}let dealt=total.min(e.hp);e.hp=(e.hp-total).max(0);e.dots.retain(|_,(ticks,_)|*ticks>0);
                if dealt>0{self.events.push(Event{missed:false,actor:e.slot.clone(),target:e.slot.clone(),action:"dot".into(),skill:String::new(),damage:dealt,healed:0,critical:false});}
            }
            e.effects.tick_balance();
            e.effects.enemy_silence=(e.effects.enemy_silence-1).max(0);
        }
        self.revive_fallen();
        if self.fighters.iter().all(|a| a.hp == 0) {
            self.finish("defeat");
        } else if self.enemies.iter().all(|e| e.hp == 0) {
            self.finish("victory");
        }
    }
}
