//! Character-owned rolled equipment. All writes share the PvE receipt transaction.
use crate::{shop,pve_rules::Stats,attributes};
use serde::{Serialize,Deserialize};
use serde_json::{Value,json};
use std::{collections::{BTreeMap,BTreeSet},sync::LazyLock};
use uuid::Uuid;
pub static DATA:LazyLock<Value>=LazyLock::new(||serde_json::from_str(include_str!("../../shared/data/loot-v1.json")).unwrap());
fn n(key:&str)->i32{DATA[key].as_i64().unwrap() as i32}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
pub struct Affix{pub kind:String,pub value:i32}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
pub struct Item{
    pub id:Uuid,pub template:String,pub level:i32,pub quality:String,pub equipped:bool,
    pub legacy:bool,pub affixes:Vec<Affix>,
    #[serde(default)] pub upgrade:i32,
    #[serde(default)] pub reroll_index:Option<usize>,
    #[serde(default)] pub legendary:Option<String>,
    #[serde(default)] pub set_id:Option<String>,
    #[serde(default)] pub skin:Option<String>,
    #[serde(default)] pub legacy_attack:i32,
    #[serde(default)] pub legacy_defense:i32,
}
#[derive(Clone,Debug,Serialize,Deserialize,PartialEq)]
#[serde(default)]
pub struct State{
    pub version:i32,pub items:Vec<Item>,pub pending:Vec<Item>,pub scrap:i32,pub essence:i32,
    pub kills:i32,pub bosses:i32,pub difficulty:i32,pub skins:BTreeSet<String>,
}
impl Default for State{fn default()->Self{Self{version:1,items:vec![],pending:vec![],scrap:0,essence:0,kills:0,bosses:0,difficulty:1,skins:BTreeSet::new()}}}
#[derive(Clone)]
pub struct Dice(pub u32);
impl Dice{pub fn next(&mut self,limit:usize)->usize{self.0=self.0.wrapping_mul(1664525).wrapping_add(1013904223);self.0 as usize%limit}}
pub fn range(kind:&str,level:i32)->Option<(i32,i32)>{let v=DATA["affixes"].get(kind)?;Some(((v[0].as_i64()? as i32*level/60).max(1),(v[1].as_i64()? as i32*level/60).max(1)))}
impl Item{
    pub fn definition(&self)->&'static shop::Item{shop::item(&self.template).expect("validated equipment template")}
    pub fn slot(&self)->&str{&self.definition().slot}
    pub fn valid(&self,job:i16,gender:i16)->bool{
        let Some(d)=shop::item(&self.template)else{return false;};
        if !d.equipment()||d.equip_error(job,gender).is_some()||self.id.get_version_num()!=4||!(1..=60).contains(&self.level)||!(0..=6).contains(&self.upgrade){return false;}
        let Some(count)=DATA["quality_affixes"].get(&self.quality).and_then(Value::as_u64)else{return false;};
        if self.legacy!=(self.quality=="legacy")||self.affixes.len()!=count as usize{return false;}
        if self.legacy&&(self.level!=1||self.upgrade!=0||self.legacy_attack!=d.attack||self.legacy_defense!=d.defense){return false;}
        if self.legendary.is_some()||self.set_id.is_some(){return false;} // Activated with the build catalog in stage C.
        if self.reroll_index.is_some_and(|i|i>=self.affixes.len()){return false;}
        if let Some(skin)=&self.skin{if shop::item(skin).is_none_or(|s|s.slot!=d.slot||s.equip_error(job,gender).is_some()){return false;}}
        let mut seen=BTreeSet::new();
        self.affixes.iter().all(|a|seen.insert(&a.kind)&&DATA["pools"][&d.slot].as_array().unwrap().iter().any(|v|v.as_str()==Some(&a.kind))&&range(&a.kind,self.level).is_some_and(|(lo,hi)|a.value>=lo&&a.value<=hi))
    }
    pub fn base(&self)->(i32,i32,i32,i32){
        if self.legacy{return (self.legacy_attack,self.legacy_defense,0,0);}
        let d=&DATA["base"][self.slot()];let v=|key:&str|d[key].as_i64().unwrap() as i32;let scale=100+2*self.upgrade;
        ((v("power_base")+self.level*v("power_step"))*scale/100,(v("defense_base")+self.level*v("defense_step_bp")/10000)*scale/100,self.level*v("hp_step")*scale/100,self.level*v("mp_step")*scale/100)
    }
}
pub fn roll(template:&str,level:i32,quality:&str,seed:u32,id:Uuid)->Result<Item,&'static str>{
    let d=shop::item(template).filter(|d|d.equipment()).ok_or("INVALID_EQUIPMENT")?;
    if !(1..=60).contains(&level)||!matches!(quality,"white"|"blue"|"yellow"){return Err("INVALID_LOOT_QUALITY");}
    let count=DATA["quality_affixes"][quality].as_u64().unwrap() as usize;
    let mut dice=Dice(seed);let mut pool:Vec<String>=DATA["pools"][&d.slot].as_array().unwrap().iter().map(|v|v.as_str().unwrap().into()).collect();let mut affixes=vec![];
    for _ in 0..count{let kind=pool.remove(dice.next(pool.len()));let (lo,hi)=range(&kind,level).unwrap();let value=lo+dice.next((hi-lo+1) as usize) as i32;affixes.push(Affix{kind,value});}
    Ok(Item{id,template:template.into(),level,quality:quality.into(),equipped:false,legacy:false,affixes,upgrade:0,reroll_index:None,legendary:None,set_id:None,skin:None,legacy_attack:0,legacy_defense:0})
}
impl State{
    pub fn valid(&self,job:i16,gender:i16)->bool{
        if self.version!=1||self.items.len()>90||self.pending.len()>20||!(0..=1000000000).contains(&self.scrap)||!(0..=1000000000).contains(&self.essence)||!(0..=1000000000).contains(&self.kills)||!(0..=1000000000).contains(&self.bosses)||!(1..=3).contains(&self.difficulty){return false;}
        let mut ids=BTreeSet::new();let mut slots=BTreeSet::new();let mut legacy=BTreeSet::new();
        for i in self.items.iter().chain(self.pending.iter()){
            if !i.valid(job,gender)||!ids.insert(i.id)||i.legacy&&!legacy.insert(&i.template){return false;}
            if i.equipped&&(!slots.insert(i.slot())||self.pending.iter().any(|p|p.id==i.id)){return false;}
        }
        self.skins.len()<=shop::ITEMS.len()&&self.skins.iter().all(|id|shop::item(id).is_some_and(|d|d.equipment()&&d.equip_error(job,gender).is_none()))
    }
    pub fn sync_legacy(&mut self,gear:&BTreeMap<String,bool>,job:i16,gender:i16){
        self.items.retain(|i|!i.legacy||gear.contains_key(&i.template));
        for (id,on) in gear{
            let Some(d)=shop::item(id).filter(|d|d.equipment()&&d.equip_error(job,gender).is_none())else{continue;};
            self.skins.insert(id.clone());
            if let Some(i)=self.items.iter_mut().find(|i|i.legacy&&i.template==*id){i.equipped=*on;}
            else{self.items.push(Item{id:Uuid::new_v4(),template:id.clone(),level:1,quality:"legacy".into(),equipped:*on,legacy:true,affixes:vec![],upgrade:0,reroll_index:None,legendary:None,set_id:None,skin:None,legacy_attack:d.attack,legacy_defense:d.defense});}
        }
    }
    pub fn extra_bag(&self)->usize{self.items.iter().filter(|i|!i.legacy&&!i.equipped).count()}
    pub fn can_fight(&self)->bool{self.pending.len()+3<=n("pending_limit") as usize}
    pub fn empty_slot(&mut self,slot:&str){for i in &mut self.items{if i.slot()==slot{i.equipped=false;}}}
    pub fn apply(&mut self,action:&str,id:Uuid,gear:&mut BTreeMap<String,bool>,level:i32,bag_count:usize)->Result<(),&'static str>{
        if action=="gear_claim"{
            if bag_count>=60{return Err("BAG_FULL");}
            let index=self.pending.iter().position(|i|i.id==id).ok_or("INSTANCE_NOT_OWNED")?;
            self.items.push(self.pending.remove(index));return Ok(());
        }
        let item=self.items.iter().find(|i|i.id==id).cloned().ok_or("INSTANCE_NOT_OWNED")?;
        if item.level>level&&action=="gear_equip"{return Err("EQUIPMENT_LEVEL_REQUIRED");}
        if action=="gear_equip"{
            self.empty_slot(item.slot());
            for (key,on) in gear.iter_mut(){if shop::item(key).is_some_and(|d|d.slot==item.slot()){*on=false;}}
            self.items.iter_mut().find(|i|i.id==id).unwrap().equipped=true;
            if item.legacy{gear.insert(item.template,true);}
        }else if action=="gear_unequip"{
            if !item.equipped{return Err("NOT_EQUIPPED");}
            if bag_count>=60{return Err("BAG_FULL");}
            self.items.iter_mut().find(|i|i.id==id).unwrap().equipped=false;
            if item.legacy{gear.insert(item.template,false);}
        }else{return Err("INVALID_LOOT_COMMAND");}
        Ok(())
    }
    pub fn reward(&mut self,job:i16,gender:i16,level:i32,boss:bool,bag_count:usize,seed:u32)->Vec<Uuid>{
        let mut dice=Dice(seed);self.kills=(self.kills+1).min(1000000000);if boss{self.bosses=(self.bosses+1).min(1000000000);}
        if !boss&&dice.next(100)>=n("normal_drop_percent") as usize{return vec![];}
        let count=if boss{n("boss_drops")}else{1};let mut gained=vec![];let mut used=bag_count;
        for _ in 0..count{
            let exact=dice.next(100)<80;
            let candidates:Vec<_>=shop::ITEMS.iter().filter(|d|d.equipment()&&d.equip_error(job,gender).is_none()&&if exact{d.job==job}else{d.job<0}).collect();
            let candidates=if candidates.is_empty(){shop::ITEMS.iter().filter(|d|d.equipment()&&d.equip_error(job,gender).is_none()).collect()}else{candidates};
            let d=candidates[dice.next(candidates.len())];let quality=match dice.next(100){0..=24=>"white",25..=69=>"blue",_=>"yellow"};
            let item=roll(&d.id,level.clamp(1,60),quality,dice.next(u32::MAX as usize) as u32,Uuid::new_v4()).unwrap();
            self.skins.insert(d.id.clone());gained.push(item.id);
            if used<60{self.items.push(item);used+=1;}else{assert!(self.pending.len()<20,"reserved loot storage");self.pending.push(item);}
        }
        gained
    }
    pub fn look(&self,mut original:[i32;3])->[i32;3]{
        for i in self.items.iter().filter(|i|i.equipped&&!i.legacy){let d=shop::item(i.skin.as_deref().unwrap_or(&i.template)).unwrap();match i.slot(){"weapon"=>original[0]=d.visual,"armor"=>original[1]=d.visual,"hat"=>original[2]=d.head_visual,_=>()}}
        original
    }
    pub fn view(&self,original:[i32;3])->Value{json!({"version":"loot-v1","state":self,"appearance":self.look(original)})}
    pub fn apply_stats(&self,s:&mut Stats,job:i16){
        let mut hp=0;let mut mp=0;let mut hp_percent=0;
        for i in self.items.iter().filter(|i|i.equipped&&!i.legacy){
            let (power,defense,h,m)=i.base();hp+=h;mp+=m;
            attributes::gear_bonus(s,0,defense);if let Some(b)=s.balance.as_mut(){if job==2{b.magic_attack+=power;}else{b.physical_attack+=power;}}
            for a in &i.affixes{match a.kind.as_str(){
                "power"=>{if let Some(b)=s.balance.as_mut(){if job==2{b.magic_attack+=a.value;}else{b.physical_attack+=a.value;}}},
                "hp"=>hp+=a.value,"mana"=>mp+=a.value,"hp_percent"=>hp_percent+=a.value,
                "defense"=>attributes::gear_bonus(s,0,a.value),
                _=>{if let Some(b)=s.balance.as_mut(){match a.kind.as_str(){"crit"=>{b.crit_bonus[0]+=a.value;b.crit_bonus[1]+=a.value;},"hit"=>{b.hit_bonus[0]+=a.value;b.hit_bonus[1]+=a.value;},"evasion"=>{b.evade_bonus[0]+=a.value;b.evade_bonus[1]+=a.value;},"crit_damage"=>b.crit_damage_bp+=a.value,"damage"=>b.increased_bp+=a.value,"dot"=>b.dot_bp+=a.value,"penetration"=>b.penetration_bp+=a.value,"reduction"=>b.reduction_bp+=a.value,_=>()}}}
            }}
        }
        s.hp=((s.hp+hp) as i64*(10000+hp_percent.min(4000)) as i64/10000).min(1000000) as i32;s.mp=(s.mp+mp).min(1000000);
        if let Some(b)=s.balance{s.attack=if job==2{b.magic_attack}else{b.physical_attack};}
    }
}
