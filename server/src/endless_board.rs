//! Authoritative best clears and transactional milestone announcements.
use crate::{AppState,auth::{self,AuthError,Peer}};
use axum::{Json,extract::{State,rejection::JsonRejection},http::{HeaderMap,StatusCode}};
use serde::Deserialize;
use serde_json::{Value,json};
use sqlx::{Postgres,Transaction,Row,types::Json as DbJson};
use std::sync::Arc;
use uuid::Uuid;

fn db(e:sqlx::Error)->AuthError{crate::observability::database_error(&e,"endless leaderboard");AuthError(StatusCode::SERVICE_UNAVAILABLE,"DATABASE_UNAVAILABLE")}
pub fn milestone(previous:i32,best:i32)->bool{best>previous&&best>=100&&best%10==0}
pub(crate) async fn record(tx:&mut Transaction<'_,Postgres>,id:Uuid,name:&str,previous:i32,best:i32)->Result<(),AuthError>{
    if best<=previous{return Ok(());}
    sqlx::query("INSERT INTO endless_records(character_id,best) VALUES($1,$2) ON CONFLICT(character_id) DO UPDATE SET best=EXCLUDED.best,achieved_at=clock_timestamp() WHERE endless_records.best<EXCLUDED.best")
        .bind(id).bind(best).execute(&mut **tx).await.map_err(db)?;
    if milestone(previous,best){
        sqlx::query("INSERT INTO endless_milestones(character_id,stage,display_name) VALUES($1,$2,$3) ON CONFLICT(character_id,stage) DO NOTHING")
            .bind(id).bind(best).bind(name).execute(&mut **tx).await.map_err(db)?;
    }
    Ok(())
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Request{character_id:Uuid}
pub(crate) async fn leaderboard(State(state):State<Arc<AppState>>,peer:Peer,headers:HeaderMap,body:Result<Json<Request>,JsonRejection>)->Result<Json<Value>,AuthError>{
    let auth=auth::service(&state)?;auth.admit_social_peer(auth::peer_ip(peer))?;
    let token=auth::bearer(&headers)?;let account=auth.me(token).await?;auth.admit_social(account.id)?;
    let Json(request)=body.map_err(|_|AuthError(StatusCode::BAD_REQUEST,"INVALID_REQUEST"))?;
    let mut tx=auth.pool().begin().await.map_err(db)?;auth.authorize_in(&mut tx,token).await?;
    let owned:bool=sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM characters WHERE id=$1 AND account_id=$2 AND deleted_at IS NULL)")
        .bind(request.character_id).bind(account.id).fetch_one(&mut *tx).await.map_err(db)?;
    if !owned{return Err(AuthError(StatusCode::FORBIDDEN,"FORBIDDEN"));}
    // One snapshot for top entries, total and personal rank, including ranks beyond 100.
    let value:DbJson<Value>=sqlx::query_scalar("WITH ranked AS (SELECT r.character_id,c.display_name,c.job,c.level,r.best,row_number() OVER (ORDER BY r.best DESC,r.achieved_at,r.character_id) AS rank FROM endless_records r JOIN characters c ON c.id=r.character_id JOIN accounts a ON a.id=c.account_id WHERE c.deleted_at IS NULL AND NOT a.disabled) SELECT jsonb_build_object('version','endless-board-v1','character_id',($1::uuid)::text,'total',(SELECT count(*) FROM ranked),'entries',COALESCE((SELECT jsonb_agg(to_jsonb(ranked) ORDER BY rank) FROM ranked WHERE rank<=100),'[]'::jsonb),'self',COALESCE((SELECT jsonb_build_object('rank',rank,'best',best) FROM ranked WHERE character_id=$1),'{\"rank\":null,\"best\":0}'::jsonb))")
        .bind(request.character_id).fetch_one(&mut *tx).await.map_err(db)?;
    tx.commit().await.map_err(db)?;
    Ok(Json(json!({"ok":true,"leaderboard":value.0})))
}
pub(crate) fn start(state:&Arc<AppState>){
    let(Some(auth),Some(world))=(state.auth.clone(),state.world.clone())else{return;};
    tokio::spawn(async move{
        let mut tick=tokio::time::interval(std::time::Duration::from_secs(1));
        loop{tick.tick().await;
            let delivered:Result<Vec<String>,AuthError>=async{
                let mut tx=auth.pool().begin().await.map_err(db)?;
                let rows=sqlx::query("SELECT m.id,m.stage,m.display_name,c.deleted_at IS NULL AND NOT a.disabled AS visible FROM endless_milestones m JOIN characters c ON c.id=m.character_id JOIN accounts a ON a.id=c.account_id WHERE m.announced_at IS NULL ORDER BY m.id LIMIT 10 FOR UPDATE OF m SKIP LOCKED")
                    .fetch_all(&mut *tx).await.map_err(db)?;
                let ids:Vec<i64>=rows.iter().map(|r|r.get("id")).collect();
                if !ids.is_empty(){sqlx::query("UPDATE endless_milestones SET announced_at=clock_timestamp() WHERE id=ANY($1)").bind(ids).execute(&mut *tx).await.map_err(db)?;}
                tx.commit().await.map_err(db)?;
                Ok(rows.iter().filter(|r|r.get::<bool,_>("visible")).map(|r|format!("恭喜{}闯过无尽之路第{}层，再攀高峰！",r.get::<String,_>("display_name"),r.get::<i32,_>("stage"))).collect())
            }.await;
            match delivered{Ok(notices)=>for notice in notices{world.public_notice(notice);},Err(_)=>tracing::warn!("endless milestone delivery deferred")}
        }
    });
}
#[cfg(test)]
mod tests{
    #[test]fn only_new_hundred_and_ten_floor_milestones_announce(){
        for stage in [1,90,99,101,109]{assert!(!super::milestone(stage-1,stage));}
        for stage in [100,110,120,1000]{assert!(super::milestone(stage-1,stage));assert!(!super::milestone(stage,stage));assert!(!super::milestone(stage+10,stage));}
    }
}
