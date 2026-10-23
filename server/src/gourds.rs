//! Refillable containers. Resource changes and remaining supply share a transaction.
use serde::{Deserialize,Serialize};
use std::collections::BTreeMap;

pub const HP:&str="supply/hp_gourd";
pub const MP:&str="supply/mp_gourd";
#[derive(Clone,Debug,Deserialize,Serialize,PartialEq,Eq)]
#[serde(deny_unknown_fields)]
pub struct Supply {pub remaining:i32,pub enabled:bool}
impl Supply {
    pub fn full(id:&str)->Self{Self{remaining:crate::shop::item(id).expect("gourd catalog").capacity,enabled:true}}
}
#[derive(Clone,Default,Debug,Deserialize,Serialize,PartialEq,Eq)]
#[serde(transparent)]
pub struct State(pub BTreeMap<String,Supply>);
impl State {
    pub fn valid(&self,gear:&BTreeMap<String,bool>,quantities:&BTreeMap<String,i32>)->bool{
        self.0.keys().all(|id|[HP,MP].contains(&id.as_str())) && [HP,MP].iter().all(|id|{
            match (self.0.get(*id),gear.get(*id)) {
                (None,None)=>true,
                (Some(s),Some(false))=>quantities.get(*id)==Some(&1)&&(0..=crate::shop::item(id).unwrap().capacity).contains(&s.remaining),
                _=>false,
            }
        })
    }
    pub fn supply(&mut self,hp:&mut i32,mp:&mut i32,maxima:crate::pve_rules::Stats,blocked:bool)->bool{
        if blocked||*hp<=0{return false;}
        let mut changed=false;
        for (id,current,maximum) in [(HP,hp,maxima.hp),(MP,mp,maxima.mp)] {
            if let Some(s)=self.0.get_mut(id).filter(|s|s.enabled) {
                let amount=(maximum-*current).max(0).min(s.remaining);
                *current+=amount;s.remaining-=amount;changed|=amount>0;
            }
        }
        changed
    }
}
