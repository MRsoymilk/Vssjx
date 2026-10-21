//! Local operator controls; chat bodies remain ephemeral and are never audited.
use crate::{AppState, auth::{self, AuthError}, security::{self, Event}};
use axum::{Json, extract::{State, Query, rejection::JsonRejection}, http::{HeaderMap, StatusCode}};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::sync::Arc;
use uuid::Uuid;

fn error(status: StatusCode, code: &'static str) -> AuthError { AuthError(status, code) }
fn database(e: sqlx::Error) -> AuthError {
    crate::observability::database_error(&e, "chat_admin");
    error(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Search { #[serde(default)] q: String, account_id: Option<Uuid> }

pub(crate) async fn history(State(state): State<Arc<AppState>>, Query(query): Query<Search>) -> Result<Json<Value>, AuthError> {
    if query.q.chars().count()>64 { return Err(error(StatusCode::BAD_REQUEST,"INVALID_REQUEST")); }
    let auth = auth::service(&state)?;
    let world = state.world.as_ref().ok_or(error(StatusCode::SERVICE_UNAVAILABLE,"WORLD_UNAVAILABLE"))?;
    let (epoch, messages) = world.chat_snapshot();
    let ids: Vec<Uuid> = messages.iter().filter(|m| !m.system).map(|m|m.sender_character_id).collect();
    let rows = sqlx::query("SELECT c.id,c.account_id,a.username,COALESCE(a.chat_muted_until>clock_timestamp(),FALSE) AS muted,(extract(epoch FROM a.chat_muted_until)*1000)::bigint::text AS muted_until_ms FROM characters c JOIN accounts a ON a.id=c.account_id WHERE c.id=ANY($1)")
        .bind(&ids).fetch_all(auth.pool()).await.map_err(database)?;
    let q=query.q.trim().to_lowercase();
    let values:Vec<Value> = messages.into_iter().rev().filter_map(|message| {
        let row=rows.iter().find(|r|r.get::<Uuid,_>("id")==message.sender_character_id);
        if query.account_id.is_some_and(|id| row.is_none_or(|r|r.get::<Uuid,_>("account_id")!=id)) { return None; }
        let mut value=serde_json::to_value(&message).expect("chat message");
        if let Some(row)=row {
            value["account_id"]=json!(row.get::<Uuid,_>("account_id"));
            value["username"]=json!(row.get::<String,_>("username"));
            value["muted"]=json!(row.get::<bool,_>("muted"));
            value["muted_until_ms"]=json!(row.get::<Option<String>,_>("muted_until_ms"));
        }
        if !q.is_empty() && ![message.text.to_lowercase(),message.display_name.to_lowercase(),value["username"].as_str().unwrap_or("").to_lowercase()].iter().any(|s|s.contains(&q)) { return None; }
        Some(value)
    }).collect();
    let accounts=sqlx::query("SELECT a.id,a.username,COALESCE(a.chat_muted_until>clock_timestamp(),FALSE) AS muted,(extract(epoch FROM a.chat_muted_until)*1000)::bigint::text AS muted_until_ms,COALESCE((SELECT c.display_name FROM characters c WHERE c.deleted_at IS NULL AND c.account_id=a.id ORDER BY c.slot LIMIT 1),'某玩家') AS display_name FROM accounts a WHERE ($1::uuid IS NOT NULL AND a.id=$1) OR ($1::uuid IS NULL AND (($2<>'' AND (strpos(a.username,lower($2))>0 OR EXISTS(SELECT 1 FROM characters c WHERE c.deleted_at IS NULL AND c.account_id=a.id AND strpos(c.name_key,lower($2))>0))) OR ($2='' AND a.chat_muted_until>clock_timestamp()))) ORDER BY a.username LIMIT 20")
        .bind(query.account_id).bind(query.q.trim()).fetch_all(auth.pool()).await.map_err(database)?;
    let accounts:Vec<Value>=accounts.iter().map(|r|json!({"account_id":r.get::<Uuid,_>("id"),"username":r.get::<String,_>("username"),"display_name":r.get::<String,_>("display_name"),"muted":r.get::<bool,_>("muted"),"muted_until_ms":r.get::<Option<String>,_>("muted_until_ms"),"deleted":true})).collect();
    Ok(Json(json!({"channel_epoch":epoch,"messages":values,"accounts":accounts,"csrf_token":state.operator_token,"history_limit":100})))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Action {
    operation_id: Uuid, channel_epoch: Uuid, account_id: Uuid,
    message_id: Option<Uuid>, action: String, reason: String,
    #[serde(default)] duration_seconds: u64,
}

pub(crate) async fn act(State(state): State<Arc<AppState>>, headers: HeaderMap, payload: Result<Json<Action>,JsonRejection>) -> Result<Json<Value>,AuthError> {
    if !headers.contains_key("origin") || !headers.get("x-operator-token").is_some_and(|v|v.as_bytes()==state.operator_token.to_string().as_bytes()) {
        return Err(error(StatusCode::FORBIDDEN,"INVALID_OPERATOR_TOKEN"));
    }
    let Json(p)=payload.map_err(|_|error(StatusCode::BAD_REQUEST,"INVALID_REQUEST"))?;
    let reason=p.reason.trim();
    let deleting=matches!(p.action.as_str(),"delete"|"delete_and_mute");
    let muting=matches!(p.action.as_str(),"mute"|"delete_and_mute");
    if p.operation_id.get_version_num()!=4 || !["delete","mute","delete_and_mute","unmute"].contains(&p.action.as_str()) || !(2..=48).contains(&reason.chars().count()) || reason.chars().any(|c|c.is_control() || matches!(c,'\u{200b}'..='\u{200f}'|'\u{2028}'..='\u{202e}'|'\u{2060}'..='\u{206f}'|'\u{feff}')) || (deleting && p.message_id.is_none()) || (muting && !(60..=86400).contains(&p.duration_seconds)) || (!muting && p.duration_seconds!=0) {
        return Err(error(StatusCode::BAD_REQUEST,"INVALID_REQUEST"));
    }
    let auth=auth::service(&state)?;
    let world=state.world.as_ref().ok_or(error(StatusCode::SERVICE_UNAVAILABLE,"WORLD_UNAVAILABLE"))?;
    let _serial=world.moderation.lock().await;
    let digest=Sha256::digest(serde_json::to_vec(&("chat-moderation-v1",p.channel_epoch,p.account_id,p.message_id,&p.action,reason,p.duration_seconds)).expect("intent")).to_vec();
    let mut tx=auth.pool().begin().await.map_err(database)?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,17))").bind(p.operation_id.to_string()).execute(&mut *tx).await.map_err(database)?;
    if let Some(row)=sqlx::query("SELECT request_digest,result FROM operator_receipts WHERE operation_id=$1").bind(p.operation_id).fetch_optional(&mut *tx).await.map_err(database)? {
        if row.get::<Vec<u8>,_>("request_digest")!=digest { return Err(error(StatusCode::CONFLICT,"IDEMPOTENCY_CONFLICT")); }
        let mut result=row.get::<sqlx::types::Json<Value>,_>("result").0;
        result["replayed"]=json!(true);
        return Ok(Json(result));
    }
    let account=sqlx::query_scalar::<_,Uuid>("SELECT id FROM accounts WHERE id=$1 FOR UPDATE").bind(p.account_id).fetch_optional(&mut *tx).await.map_err(database)?;
    if account.is_none() { return Err(error(StatusCode::NOT_FOUND,"ACCOUNT_NOT_FOUND")); }
    let characters=sqlx::query("SELECT id,display_name FROM characters WHERE account_id=$1 AND deleted_at IS NULL ORDER BY slot").bind(p.account_id).fetch_all(&mut *tx).await.map_err(database)?;
    let ids:Vec<Uuid>=characters.iter().map(|r|r.get("id")).collect();
    let (epoch,messages)=world.chat_snapshot();
    if epoch!=p.channel_epoch { return Err(error(StatusCode::CONFLICT,"CHAT_EPOCH_CHANGED")); }
    let target=if let Some(id)=p.message_id {
        Some(messages.iter().find(|m|m.message_id==id && !m.system && !m.deleted && ids.contains(&m.sender_character_id)).ok_or(error(StatusCode::NOT_FOUND,"CHAT_MESSAGE_NOT_FOUND"))?)
    } else { None };
    let name=target.map(|m|m.display_name.clone()).or_else(||characters.first().map(|r|r.get::<String,_>("display_name"))).unwrap_or("某玩家".into());
    let mute=if muting { Some(p.duration_seconds) } else if p.action=="unmute" { Some(0) } else { None };
    if let Some(seconds)=mute {
        sqlx::query("UPDATE accounts SET chat_muted_until=CASE WHEN $2::bigint=0 THEN NULL ELSE clock_timestamp()+$2::bigint*interval '1 second' END WHERE id=$1")
            .bind(p.account_id).bind(seconds as i64).execute(&mut *tx).await.map_err(database)?;
    }
    let action_text=match p.action.as_str() {
        "delete"=>"的一条发言已被管理员删除".to_owned(),
        "mute"=>format!("所属账号已被管理员禁言{}分钟",p.duration_seconds.div_ceil(60)),
        "delete_and_mute"=>format!("的一条发言已删除，所属账号禁言{}分钟",p.duration_seconds.div_ceil(60)),
        _=>"所属账号已被管理员解除禁言".to_owned(),
    };
    let notice=format!("{name}{action_text}。原因：{reason}");
    let result=json!({"operation_id":p.operation_id,"action":p.action,"account_id":p.account_id,"message_id":p.message_id,"notice":notice,"replayed":false});
    security::append(&mut *tx,Event{account:Some(p.account_id),character:target.map(|m|m.sender_character_id),session:None,operation:Some(p.operation_id),action:"operator.chat",outcome:"accepted",code:"OK",details:json!({"action":p.action,"message_id":p.message_id,"duration_seconds":p.duration_seconds,"reason":reason})}).await.map_err(database)?;
    sqlx::query("INSERT INTO operator_receipts(operation_id,request_digest,result) VALUES($1,$2,$3)").bind(p.operation_id).bind(digest).bind(sqlx::types::Json(&result)).execute(&mut *tx).await.map_err(database)?;
    tx.commit().await.map_err(database)?;
    world.moderate_chat(if deleting {p.message_id} else {None},&ids,mute,notice);
    Ok(Json(result))
}
