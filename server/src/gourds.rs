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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enlarged_capacity_accepts_legacy_and_full_reserves_but_rejects_overflow(){
        let gear=BTreeMap::from([(HP.into(),false),(MP.into(),false)]);
        let quantities=BTreeMap::from([(HP.into(),1),(MP.into(),1)]);
        let mut state=State(BTreeMap::from([
            (HP.into(),Supply{remaining:10000,enabled:false}),
            (MP.into(),Supply{remaining:5000,enabled:true}),
        ]));
        assert!(state.valid(&gear,&quantities));
        let restored:State=serde_json::from_str(&serde_json::to_string(&state).unwrap()).unwrap();
        assert_eq!(restored,state);
        for id in [HP,MP] {
            let full=Supply::full(id);
            assert_eq!(full.remaining,999999);assert!(full.enabled);
            state.0.insert(id.into(),full);
            assert!(state.valid(&gear,&quantities));
            for invalid in [-1,1000000] {
                state.0.get_mut(id).unwrap().remaining=invalid;
                assert!(!state.valid(&gear,&quantities));
            }
            state.0.get_mut(id).unwrap().remaining=999999;
        }
    }
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
