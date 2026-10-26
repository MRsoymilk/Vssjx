//! Player-sheet skill names/effects. Numeric rules are explicitly reconstructed.
use crate::pve_rules::Stats;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::sync::LazyLock;
use std::collections::BTreeMap;
#[derive(Clone,Debug,Default,Serialize,Deserialize)]
#[serde(default)]
pub struct BalanceState{
    #[serde(default,skip_serializing_if="is_zero")]
    pub stun_revision:u8,
    pub cooldowns:BTreeMap<String,i32>,
    pub targets:i32,
    pub control_protection:i32,
    pub last_enemy_magical:bool,
}
const DATA: &str = include_str!("../../client/assets/data/skills-v1.json");
fn is_zero(value:&u8)->bool{*value==0}
#[derive(Deserialize)]
pub struct Stun {pub chance:i32,pub actions:i32,pub cooldown:i32}
#[derive(Deserialize)]
pub struct Skill {
    #[serde(default)]
    pub stun:Option<Stun>,
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
    json!({"version":"skills-v1","catalog_sha256":*HASH,"balance_sha256":format!("{:x}",Sha256::digest(include_bytes!("../../shared/data/skill-balance-v1.json"))),"available":ITEMS.iter().filter(|s|eligible(s,job,school,level)).map(|s|&s.id).collect::<Vec<_>>()})
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct State {
    #[serde(default,skip_serializing_if="crate::skill_proficiency::Progress::is_empty")]
    pub proficiency:crate::skill_proficiency::Progress,
    #[serde(default,skip_serializing_if="stun_is_zero")]
    pub last_skill_level:i32,
    #[serde(default,skip_serializing_if="stun_is_zero")]
    pub enemy_stun:i32,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub builds:Option<crate::builds::Progress>,
    #[serde(skip_serializing_if="not_critical")]
    pub last_missed: bool,
    #[serde(skip_serializing_if="not_critical")]
    pub last_enemy_missed: bool,
    #[serde(default,skip_serializing_if="Option::is_none")]
    pub balance:Option<BalanceState>,
    #[serde(skip_serializing_if = "not_critical")]
    pub last_critical: bool,
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
fn not_critical(value: &bool) -> bool {
    !*value
}
fn stun_is_zero(value:&i32)->bool{*value==0}
impl State {
    pub fn with_proficiency(mut self,progress:crate::skill_proficiency::Progress)->Self{self.proficiency=progress;self}
    pub fn practice(&mut self,id:&str){self.last_skill_level=i32::from(self.proficiency.record(id));}
    // Enable only at encounter creation. Deserializing an in-flight battle must
    // not opt it into new mechanics or a new cooldown halfway through combat.
    pub fn enable_stun(&mut self,stats:Stats){self.activate(stats);if let Some(b)=self.balance.as_mut(){b.stun_revision=1;}}
    pub fn stun_enabled(&self)->bool{self.balance.as_ref().is_some_and(|b|b.stun_revision==1)}
    pub fn consume_stun(&mut self)->bool{if self.enemy_stun<=0{return false;}self.enemy_stun-=1;true}
    pub fn miss(&mut self,s:&Skill,stats:Stats,mp:&mut i32){self.activate(stats);self.last_skill=s.id.clone();self.last_missed=true;*mp-=crate::skill_balance::cost(s,stats);self.mark(s);self.last_critical=false;}
    pub fn activate(&mut self,stats:Stats){if crate::skill_balance::revised(stats)&&self.balance.is_none(){self.balance=Some(BalanceState{targets:1,..Default::default()});}}
    pub fn remaining(&self,id:&str)->i32{self.balance.as_ref().and_then(|b|b.cooldowns.get(id)).copied().unwrap_or(0)}
    pub fn mark(&mut self,s:&Skill){let cooldown=crate::skill_balance::cooldown_for(s,self.stun_enabled());if let Some(b)=self.balance.as_mut(){b.cooldowns.insert(s.id.clone(),cooldown+1);}}
    pub fn tick_balance(&mut self){if let Some(b)=self.balance.as_mut(){for v in b.cooldowns.values_mut(){*v=(*v-1).max(0);}b.cooldowns.retain(|_,v|*v>0);b.control_protection=(b.control_protection-1).max(0);}}
    pub fn end_balance_round(&mut self,hp:&mut i32,max_hp:i32)->i32{
        if self.balance.is_none(){return 0;}
        let mut damage=0;
        if self.enemy_bleed>0{damage+=self.bleed_damage;self.enemy_bleed-=1;}
        if self.enemy_poison>0{damage+=self.poison_damage;self.enemy_poison-=1;}
        if self.regen>0&&*hp>0{let healed=self.regen_amount.min(max_hp-*hp);*hp+=healed;self.last_healed+=healed;self.regen-=1;}
        damage
    }
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
        self.last_skill_level=0;
        if let Some(p)=self.builds.as_mut(){p.used=false;p.bonus_bp=0;p.dot_bp=0;}
        if let Some(b)=self.balance.as_mut(){b.last_enemy_magical=false;}
        self.last_critical = false;
        self.last_missed=false;self.last_enemy_missed=false;
        self.last_skill.clear();
        self.last_enemy_acted = false;
        self.last_damage = 0;
        self.last_incoming = 0;
        self.last_reflected = 0;
        self.last_healed = 0;
    }
    pub fn critical(&mut self, damage: i32, roll: i32) -> i32 {
        self.last_critical = damage > 0 && self.crit > 0 && roll < self.crit_chance;
        if self.last_critical {
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
        let revised=crate::skill_balance::revised(stats);
        self.activate(stats);
        *mp -= crate::skill_balance::cost(s,stats);
        if revised{self.mark(s);}
        let damage = if s.damage_percent > 0 {
            crate::attributes::direct_damage(stats,enemy_defense,if revised{crate::skill_balance::coefficient(s,self.balance.as_ref().unwrap().targets)}else{s.damage_percent*100},0)
        } else {
            0
        };
        let healed = s.legacy_heal.min(stats.hp - *hp);
        *hp += healed;
        self.last_healed += healed;
        if damage > 0 {
            self.enemy_sleep = 0;
        }
        let mut stolen_amount=0;
        let mut control_applied=false;
        match s.effect.as_str() {
            "bleed" => {
                self.enemy_bleed = if revised{crate::skill_balance::n("dot_ticks")}else{s.duration};
                self.bleed_damage = if revised{crate::attributes::dot_damage(stats,enemy_defense,crate::skill_balance::n("dot_tick_bp"))}else{(stats.attack * s.value / 100).max(1)};
            }
            "poison" => {
                self.enemy_poison = if revised{crate::skill_balance::n("dot_ticks")}else{s.duration};
                self.poison_damage = if revised{crate::attributes::dot_damage(stats,enemy_defense,crate::skill_balance::n("dot_tick_bp"))}else{(stats.attack * s.value / 100).max(1)};
            }
            "sleep" => {
                if roll < if revised{crate::skill_balance::n("control_chance")}else{s.chance} && self.balance.as_ref().is_none_or(|b|b.control_protection==0) {
                    self.enemy_sleep = if revised{crate::skill_balance::n("control_duration")}else{s.duration};
                    control_applied=true;
                    if let Some(b)=self.balance.as_mut(){b.control_protection=crate::skill_balance::n("control_protection");}
                }
            }
            "silence" => {
                if roll < if revised{crate::skill_balance::n("control_chance")}else{s.chance} && self.balance.as_ref().is_none_or(|b|b.control_protection==0) {
                    self.enemy_silence = if revised{crate::skill_balance::n("control_duration")}else{s.duration};
                    control_applied=true;
                    if let Some(b)=self.balance.as_mut(){b.control_protection=crate::skill_balance::n("control_protection");}
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
                stolen_amount=stolen;
                self.enemy_mp -= stolen;
                *mp = (*mp + stolen).min(stats.mp);
            }
            _ => {}
        }
        if self.stun_enabled() && let Some(stun)=s.stun.as_ref()
            && roll<stun.chance && self.balance.as_ref().is_some_and(|b|b.control_protection==0) {
            self.enemy_stun=stun.actions;
            self.balance.as_mut().unwrap().control_protection=crate::skill_balance::n("control_protection");
        }
        crate::builds::cast(s,stats,self,hp,mp,damage,stolen_amount,control_applied)
    }
    pub fn after_player(&mut self, hp: &mut i32, max_hp: i32) -> i32 {
        if self.balance.is_some(){return 0;}
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
    pub fn enemy_hit(&self, mut incoming: i32, own_attack: i32, magical: bool) -> (i32, i32) {
        if incoming <= 0 { return (0, 0); }
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
        // Reflection uses the defender's own attack, not the attacker's damage.
        (incoming, own_attack.max(0) * percent / 100)
    }
    pub fn end_turn(&mut self) {
        self.tick_balance();
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
