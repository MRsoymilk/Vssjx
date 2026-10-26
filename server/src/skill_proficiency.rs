//! Character-owned cast counts; never accept them from a gameplay command.
use crate::skills;
use serde::{Deserialize,Serialize};
use std::collections::BTreeMap;
use std::sync::LazyLock;

#[derive(Deserialize)]
struct Rules {max_level:u16,casts_per_level:u16}
static RULES:LazyLock<Rules>=LazyLock::new(||serde_json::from_str(include_str!("../../shared/data/skill-proficiency-v1.json")).expect("skill proficiency rules"));
#[derive(Clone,Debug,Default,Serialize,Deserialize,PartialEq,Eq)]
#[serde(transparent)]
pub struct Progress(pub BTreeMap<String,u16>);
impl Progress {
    pub fn is_empty(&self)->bool{self.0.is_empty()}
    pub fn level(&self,id:&str)->u8{(1+self.0.get(id).copied().unwrap_or(0)/RULES.casts_per_level).min(RULES.max_level) as u8}
    pub fn record(&mut self,id:&str)->u8{
        if skills::item(id).is_some_and(|s|s.active){
            let count=self.0.entry(id.to_owned()).or_default();
            *count=count.saturating_add(1).min((RULES.max_level-1)*RULES.casts_per_level);
        }
        self.level(id)
    }
    pub fn valid(&self,job:i16,level:i32)->bool{
        self.0.len()<=skills::ITEMS.len()&&self.0.iter().all(|(id,n)|
            *n<=(RULES.max_level-1)*RULES.casts_per_level&&skills::item(id).is_some_and(|s|s.active&&skills::eligible(s,job,0,level)))
    }
}

/// Merge monotonic server-owned counters. A duplicate checkpoint never trains twice.
pub(crate) async fn save_duel(pool:&sqlx::PgPool,mut values:Vec<(uuid::Uuid,Progress)>)->Result<(),sqlx::Error>{
    use sqlx::{Row,types::Json};
    values.sort_by_key(|(id,_)|*id);
    let mut tx=pool.begin().await?;
    for (id,incoming) in values {
        let row=sqlx::query("SELECT account_id,job,level,skill_proficiency FROM characters WHERE id=$1 AND deleted_at IS NULL FOR UPDATE")
            .bind(id).fetch_one(&mut *tx).await?;
        if !incoming.valid(row.get("job"),row.get("level")){return Err(sqlx::Error::Protocol("Invalid duel skill proficiency".into()));}
        let mut stored:Progress=row.get::<Json<Progress>,_>("skill_proficiency").0;
        let before=stored.clone();
        for (skill,count) in incoming.0 {let old=stored.0.entry(skill).or_default();*old=(*old).max(count);}
        if stored!=before{
            sqlx::query("UPDATE characters SET skill_proficiency=$2,state_revision=state_revision+1 WHERE id=$1").bind(id).bind(Json(&stored)).execute(&mut *tx).await?;
            crate::security::append(&mut *tx,crate::security::Event{account:Some(row.get("account_id")),character:Some(id),session:None,operation:None,action:"skill.practice",outcome:"accepted",code:"OK",details:serde_json::json!({"source":"duel","before":before,"after":stored})}).await?;
        }
    }
    tx.commit().await
}
