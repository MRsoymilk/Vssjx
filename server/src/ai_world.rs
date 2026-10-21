//! Synthetic expansion, kept separate from recovered content and legacy quest masks.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::BTreeMap, sync::LazyLock};
use sha2::{Digest, Sha256};

pub const BYTES: &str = include_str!("../../shared/data/ai-world-v1.json");
pub static CATALOG: LazyLock<Value> = LazyLock::new(|| {
    let mut value:Value=serde_json::from_str(BYTES).expect("AI world bundle");
    let home=value["maps"].as_array_mut().unwrap().iter_mut().find(|m|m["map_id"]==crate::endless::map()).expect("endless home map");
    home["residents"].as_array_mut().unwrap().push(crate::endless::DATA["npc"].clone());value
});
static HASH: LazyLock<String> = LazyLock::new(||format!("{:x}",Sha256::digest(BYTES.replace("\r\n","\n").as_bytes())));
static MONSTER_COUNT: LazyLock<usize> = LazyLock::new(||maps().iter().flat_map(|m|m["residents"].as_array().unwrap()).filter(|r|r["kind"]!="npc").count());
pub fn hash() -> String { HASH.clone() }
pub fn maps() -> &'static Vec<Value> { CATALOG["maps"].as_array().expect("AI maps") }
pub fn map(id: &str) -> Option<&'static Value> { maps().iter().find(|m|m["map_id"]==id) }
pub fn quest(id: &str) -> Option<&'static Value> { maps().iter().flat_map(|m|m["quests"].as_array().unwrap()).find(|q|q["id"]==id) }
pub fn resident(id: &str) -> Option<&'static Value> { maps().iter().flat_map(|m|m["residents"].as_array().unwrap()).find(|r|r["id"]==id) }
pub fn cell(v: &Value) -> [i32;2] { [v[0].as_i64().unwrap() as i32,v[1].as_i64().unwrap() as i32] }
pub fn station(id: &str) -> [i32;2] { if let Some(m)=map(id){cell(&m["portal"]["cell"])}else if id=="qingyun_trail"{[3,16]}else{[12,16]} }
pub fn exit_target(map_id:&str,point:[i32;2])->Option<String>{
    if map(map_id).is_none(){
        if point==station(map_id){return Some("ai_001".into());}
        if (map_id=="qingyun_trail"&&point==[28,16])||(map_id=="ancient_ruins"&&point==[3,16]){return Some(if map_id=="qingyun_trail"{"ancient_ruins"}else{"qingyun_trail"}.into());}
        return None;
    }
    map(map_id)?.get("exits")?.as_array()?.iter().find(|e|e.get("cells").and_then(Value::as_array).map_or_else(||cell(&e["cell"])==point,|cells|cells.iter().any(|c|cell(c)==point)))?.get("target_map")?.as_str().map(str::to_owned)
}
pub fn target_cell(map_id: &str, target: &str) -> Option<[i32;2]> {
    let r=if let Some(q)=quest(target) { resident(q["giver"].as_str()?)? } else {resident(target)?};
    let m=map(map_id)?;
    m["residents"].as_array()?.iter().any(|v|v["id"]==r["id"]).then(||cell(&r["cell"]))
}
#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default,deny_unknown_fields)]
pub struct Progress {
    pub completed: Vec<String>,
    pub active: BTreeMap<String,Vec<i32>>,
    pub respawns: BTreeMap<String,i64>,
}
impl Progress {
    pub fn valid(&self) -> bool {
        self.completed.len()<=642 && self.active.len()<=3 && self.respawns.len()<=*MONSTER_COUNT &&
        self.completed.iter().enumerate().all(|(i,id)|quest(id).is_some()&&!self.completed[..i].contains(id)) &&
        self.active.iter().all(|(id,counts)|quest(id).is_some_and(|q|!self.completed.contains(id)&&counts.len()==q["objectives"].as_array().unwrap().len()&&counts.iter().zip(q["objectives"].as_array().unwrap()).all(|(n,o)|*n>=0&&i64::from(*n)<=o["count"].as_i64().unwrap()))) &&
        self.respawns.iter().all(|(id,t)|resident(id).is_some_and(|r|r["kind"]!="npc")&&(0..=253_402_300_799_999).contains(t))
    }
    pub fn view(&self, map_id: &str) -> Value {
        let completed:Vec<_>=self.completed.iter().filter(|id|quest(id).is_some_and(|q|q["map_id"]==map_id)).collect();
        let respawns:BTreeMap<_,_>=self.respawns.iter().filter(|(id,_)|target_cell(map_id,id).is_some()).collect();
        json!({"version":"ai-world-v1","catalog_sha256":hash(),"completed":completed,"completed_count":self.completed.len(),"active":self.active,"respawns":respawns})
    }
    pub fn accept(&mut self,id:&str,map_id:&str,level:i32)->Result<(),&'static str>{
        let q=quest(id).filter(|q|q["map_id"]==map_id).ok_or("AI_INVALID_TARGET")?;
        if self.completed.iter().any(|v|v==id)||self.active.contains_key(id){return Err("QUEST_ALREADY_ACCEPTED");}
        if self.active.len()>=3{return Err("AI_QUEST_LIMIT");}
        if i64::from(level)<q["min_level"].as_i64().unwrap(){return Err("AI_LEVEL_REQUIRED");}
        let pre=q["prerequisite"].as_str().unwrap();
        if !pre.is_empty()&&!self.completed.iter().any(|v|v==pre){return Err("AI_PREREQUISITE");}
        self.active.insert(id.into(),vec![0;q["objectives"].as_array().unwrap().len()]);Ok(())
    }
    pub fn event(&mut self,kind:&str,target:&str)->bool{
        let mut changed=false;
        for (id,counts) in &mut self.active {
            let goals=quest(id).unwrap()["objectives"].as_array().unwrap();
            for (i,g) in goals.iter().enumerate(){
                if g["kind"]==kind&&g["target"]==target&&counts[i]<g["count"].as_i64().unwrap() as i32&&
                    (kind!="interact"||counts[..i].iter().zip(&goals[..i]).all(|(n,o)|i64::from(*n)>=o["count"].as_i64().unwrap())) {
                    counts[i]+=1;changed=true;
                }
            }
        } changed
    }
    pub fn claim(&mut self,id:&str)->Result<(i32,i32),&'static str>{
        let q=quest(id).ok_or("AI_INVALID_TARGET")?;
        let counts=self.active.get(id).ok_or("QUEST_NOT_READY")?;
        if counts.iter().zip(q["objectives"].as_array().unwrap()).any(|(n,o)|i64::from(*n)<o["count"].as_i64().unwrap()){return Err("QUEST_NOT_READY");}
        self.active.remove(id);self.completed.push(id.into());
        Ok((q["gold"].as_i64().unwrap() as i32,q["xp"].as_i64().unwrap() as i32))
    }
}
