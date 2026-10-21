//! Character-owned endless runs. Entry level and stage are frozen in the battle.
use crate::population::ResidentDefinition;
use serde::{Serialize,Deserialize};use serde_json::{Value,json};use std::sync::LazyLock;use sha2::{Digest,Sha256};
pub static DATA:LazyLock<Value>=LazyLock::new(||serde_json::from_str(include_str!("../../shared/data/endless-v1.json")).unwrap());
pub static HASH:LazyLock<String>=LazyLock::new(||format!("{:x}",Sha256::digest(include_str!("../../shared/data/endless-v1.json").replace("\r\n","\n").as_bytes())));
pub fn n(key:&str)->i32{DATA[key].as_i64().unwrap() as i32}
pub fn npc()->&'static str{DATA["npc"]["id"].as_str().unwrap()}
pub fn map()->&'static str{DATA["map_id"].as_str().unwrap()}
#[derive(Clone,Copy,Debug,PartialEq,Serialize,Deserialize)]
pub struct Run{pub stage:i32,pub level:i32}
impl Run{
    pub fn monster(self)->Result<ResidentDefinition,&'static str>{
        if !(1..=n("max_stage")).contains(&self.stage)||!(1..=60).contains(&self.level){return Err("INVALID_ENDLESS_STATE");}
        let scale=|base:&str,step:&str,growth:&str|->Result<i32,&'static str>{
            let value=(i64::from(n(base))+i64::from(self.level)*i64::from(n(step)))*(10000+i64::from(self.stage-1)*i64::from(n(growth)))/10000;
            if value>i64::from(n("max_stat")){return Err("ENDLESS_LIMIT");}Ok(value as i32)
        };
        Ok(ResidentDefinition{id:DATA["monster_id"].as_str().unwrap().into(),name:format!("试炼幻影·第{}层",self.stage),kind:"guardian".into(),art:DATA["arts"][((self.stage-1)%4) as usize].as_str().unwrap().into(),cell:[DATA["npc"]["cell"][0].as_i64().unwrap() as i32,DATA["npc"]["cell"][1].as_i64().unwrap() as i32],level:self.level,
            hp:scale("hp_base","hp_per_level","hp_step_bp")?,attack:scale("attack_base","attack_per_level","attack_step_bp")?,defense:scale("defense_base","defense_per_level","defense_step_bp")?,gold:n("gold_base")+self.level*n("gold_per_level"),xp:n("xp_base")+self.level*n("xp_per_level")})
    }
}
#[derive(Clone,Debug,PartialEq,Serialize,Deserialize)]
#[serde(default,deny_unknown_fields)]
pub struct Progress{pub stage:i32,pub best:i32,pub level:i32,pub in_progress:bool}
impl Default for Progress{fn default()->Self{Self{stage:1,best:0,level:0,in_progress:false}}}
impl Progress{
    pub fn valid(&self)->bool{(1..=n("max_stage")+1).contains(&self.stage)&&(0..=n("max_stage")).contains(&self.best)&&self.best>=self.stage-1&&(0..=60).contains(&self.level)&&if self.level==0{self.stage==1&&!self.in_progress}else{self.stage>1||self.in_progress}}
    pub fn begin(&mut self,level:i32)->Result<Run,&'static str>{
        if !self.valid(){return Err("INVALID_ENDLESS_STATE");}if self.in_progress{return Err("BATTLE_ACTIVE");}
        if self.stage>n("max_stage"){return Err("ENDLESS_LIMIT");}
        let run=Run{stage:self.stage,level:if self.level==0{level}else{self.level}};run.monster()?;
        self.level=run.level;self.in_progress=true;Ok(run)
    }
    pub fn finish(&mut self,run:Run,victory:bool)->Result<(),&'static str>{
        if !self.in_progress||self.stage!=run.stage||self.level!=run.level{return Err("INVALID_ENDLESS_STATE");}
        if victory{self.best=self.best.max(run.stage);self.stage=run.stage+1;self.in_progress=false;}else{self.stage=1;self.level=0;self.in_progress=false;}Ok(())
    }
    pub fn view(&self)->Value{json!({"version":"endless-v1","catalog_sha256":*HASH,"progress":self})}
}
