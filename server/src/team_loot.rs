//! Shared party loot: one immutable decision per participant and item.
use crate::{loot::Item,team_rules::Fighter};
use serde::{Serialize,Deserialize};use std::collections::BTreeMap;use uuid::Uuid;
use rand::seq::SliceRandom;
pub const ROLL_MS:i64=60_000;
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct Drop{
    pub item:Item,pub eligible:Vec<Uuid>,pub choices:BTreeMap<Uuid,Option<u8>>,
    pub tie_scores:BTreeMap<Uuid,u8>,pub winner:Option<Uuid>,pub resolved:bool,pub delivered:bool,
}
#[derive(Clone,Debug,Serialize,Deserialize)]
pub struct Pool{pub deadline_ms:i64,pub revision:u64,pub members:Vec<Uuid>,pub drops:Vec<Drop>,#[serde(default)] pub unrestricted:bool}
impl Pool{
    pub fn new(items:Vec<Item>,fighters:&[Fighter],now:i64)->Self{
        let members:Vec<_>=fighters.iter().map(|f|f.id).collect();
        let drops=items.into_iter().map(|item|{
            let eligible:Vec<_>=fighters.iter().map(|f|f.id).collect();
            let choices=members.iter().filter(|id|!eligible.contains(id)).map(|id|(*id,None)).collect();
            Drop{item,eligible,choices,tie_scores:BTreeMap::new(),winner:None,resolved:false,delivered:false}
        }).collect();
        let mut pool=Self{deadline_ms:now+ROLL_MS,revision:0,members,drops,unrestricted:true};pool.resolve(now);pool
    }
    pub fn pending(&self)->bool{self.drops.iter().any(|d|!d.delivered)}
    pub fn choose(&mut self,who:Uuid,id:Uuid,roll:Option<u8>,now:i64)->Result<(),&'static str>{
        if now>=self.deadline_ms{return Err("TEAM_LOOT_EXPIRED");}
        if !self.members.contains(&who){return Err("TEAM_NOT_PARTICIPATING");}
        if roll.is_some_and(|n|!(1..=100).contains(&n)){return Err("INVALID_LOOT_ROLL");}
        let drop=self.drops.iter_mut().find(|d|d.item.id==id).ok_or("TEAM_LOOT_NOT_FOUND")?;
        if !drop.eligible.contains(&who){return Err("TEAM_LOOT_INELIGIBLE");}
        if drop.resolved||drop.choices.contains_key(&who){return Err("TEAM_LOOT_DECIDED");}
        drop.choices.insert(who,roll);self.revision+=1;self.resolve(now);Ok(())
    }
    pub fn resolve(&mut self,now:i64){
        for drop in self.drops.iter_mut().filter(|d|!d.resolved){
            if now>=self.deadline_ms{for id in &self.members{drop.choices.entry(*id).or_insert(None);}}
            if drop.choices.len()!=self.members.len(){continue;}
            let high=drop.choices.values().filter_map(|v|*v).max();
            if let Some(high)=high{
                let tied:Vec<_>=drop.choices.iter().filter(|(_,n)|**n==Some(high)).map(|(id,_)|*id).collect();
                drop.winner=if tied.len()==1{Some(tied[0])}else{
                    // A fair shuffled die bag makes the tie-break finite without
                    // privileging UUID order or letting clients request a reroll.
                    let mut scores:Vec<u8>=(1..=100).collect();scores.shuffle(&mut rand::thread_rng());
                    for (id,score) in tied.into_iter().zip(scores){drop.tie_scores.insert(id,score);}
                    drop.tie_scores.iter().max_by_key(|(_,score)|**score).map(|(id,_)|*id)
                };
            }
            drop.resolved=true;if drop.winner.is_none(){drop.delivered=true;}self.revision+=1;
        }
    }
}
