//! Only mounted behind the separate loopback/Host/Origin guarded monitor router.
use crate::{
    AppState,
    auth::{self, AuthError},
    security::{self, Event},
};
use axum::{
    Json,
    extract::{Path, Query, State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode},
};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{PgPool, Row, types::Json as DbJson};
use std::sync::Arc;
use uuid::Uuid;

fn database(error: sqlx::Error) -> AuthError {
    crate::observability::database_error(&error, "user_admin");
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
fn invalid() -> AuthError {
    AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST")
}
fn pool(state: &AppState) -> Result<&PgPool, AuthError> {
    Ok(auth::service(state)?.pool())
}

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Search {
    #[serde(default)]
    q: String,
    #[serde(default)]
    offset: i64,
}
pub(crate) async fn users(
    State(state): State<Arc<AppState>>,
    Query(search): Query<Search>,
) -> Result<Json<Value>, AuthError> {
    if search.q.chars().count() > 64 || !(0..=100_000).contains(&search.offset) {
        return Err(invalid());
    }
    // strpos treats '%' and '_' as ordinary text, not wildcard/SQL syntax.
    let rows = sqlx::query("SELECT a.id,a.username,a.disabled,a.created_at::text AS created_at, (SELECT count(*) FROM characters c WHERE c.account_id=a.id) AS characters, COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'display_name',c.display_name,'level',c.level) ORDER BY c.slot) FROM characters c WHERE c.account_id=a.id),'[]'::jsonb) AS character_summaries, (SELECT count(*) FROM sessions s WHERE s.account_id=a.id AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp() AND NOT a.disabled) AS sessions FROM accounts a WHERE $1='' OR strpos(a.username,lower($1))>0 OR a.id::text=$1 OR EXISTS(SELECT 1 FROM characters c WHERE c.account_id=a.id AND (strpos(c.name_key,lower($1))>0 OR c.id::text=$1)) ORDER BY a.created_at DESC,a.id LIMIT 51 OFFSET $2")
        .bind(search.q.trim()).bind(search.offset).fetch_all(pool(&state)?).await.map_err(database)?;
    let more = rows.len() > 50;
    let users: Vec<_> = rows.iter().take(50).map(|r| json!({"id":r.get::<Uuid,_>("id"),"username":r.get::<String,_>("username"),"disabled":r.get::<bool,_>("disabled"),"created_at":r.get::<String,_>("created_at"),"characters":r.get::<i64,_>("characters"),"character_summaries":r.get::<DbJson<Value>,_>("character_summaries").0,"sessions":r.get::<i64,_>("sessions")})).collect();
    Ok(Json(
        json!({"users":users,"more":more,"csrf_token":state.operator_token}),
    ))
}
pub(crate) async fn detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, AuthError> {
    let pool = pool(&state)?;
    let row = sqlx::query(
        "SELECT id,username,disabled,created_at::text AS created_at FROM accounts WHERE id=$1",
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(database)?
    .ok_or(AuthError(StatusCode::NOT_FOUND, "ACCOUNT_NOT_FOUND"))?;
    let characters = sqlx::query_scalar::<_, DbJson<Value>>("SELECT jsonb_build_object('id',c.id,'display_name',c.display_name,'slot',c.slot,'job',c.job,'gender',c.gender,'school',c.school,'level',c.level,'xp',c.xp,'gold',c.gold,'hp',c.hp,'mp',c.mp,'quest_stage',c.quest_stage,'map_id',c.map_id,'cell',jsonb_build_array(c.cell_x,c.cell_y),'state_revision',c.state_revision::text,'allocated_attributes',c.allocated_attributes,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('definition_id',i.definition_id,'quantity',i.quantity,'equipped',i.equipped) ORDER BY i.definition_id) FROM inventory_items i WHERE i.character_id=c.id),'[]'::jsonb)) FROM characters c WHERE c.account_id=$1 ORDER BY c.slot")
        .bind(id).fetch_all(pool).await.map_err(database)?;
    // Only counts/expiry metadata: no password, digest, bearer or refresh token.
    let sessions = sqlx::query_scalar::<_, DbJson<Value>>("SELECT jsonb_build_object('created_at',created_at::text,'access_expires_at',access_expires_at::text,'revoked',revoked_at IS NOT NULL,'active',revoked_at IS NULL AND access_expires_at>clock_timestamp() AND refresh_expires_at>clock_timestamp()) FROM sessions WHERE account_id=$1 ORDER BY created_at DESC LIMIT 20")
        .bind(id).fetch_all(pool).await.map_err(database)?;
    Ok(Json(
        json!({"account":{"id":id,"username":row.get::<String,_>("username"),"disabled":row.get::<bool,_>("disabled"),"created_at":row.get::<String,_>("created_at")},"characters":characters.into_iter().map(|v|v.0).collect::<Vec<_>>(),"sessions":sessions.into_iter().map(|v|v.0).collect::<Vec<_>>()}),
    ))
}

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct AuditQuery {
    account_id: Option<Uuid>,
    character_id: Option<Uuid>,
    before: Option<i64>,
    outcome: Option<String>,
}
pub(crate) async fn audit(
    State(state): State<Arc<AppState>>,
    Query(q): Query<AuditQuery>,
) -> Result<Json<Value>, AuthError> {
    if q.before.is_some_and(|v| v <= 0)
        || q.outcome
            .as_deref()
            .is_some_and(|v| !["accepted", "rejected", "replayed", "observed"].contains(&v))
    {
        return Err(invalid());
    }
    let rows = sqlx::query_scalar::<_, DbJson<Value>>("SELECT jsonb_build_object('id',id::text,'created_at',created_at::text,'account_id',account_id,'character_id',character_id,'session_id',session_id,'operation_id',operation_id,'action',action,'outcome',outcome,'code',code,'details',details) FROM security_audit WHERE ($1::uuid IS NULL OR account_id=$1) AND ($2::uuid IS NULL OR character_id=$2) AND ($3::bigint IS NULL OR id<$3) AND ($4::text IS NULL OR outcome=$4) ORDER BY id DESC LIMIT 101")
        .bind(q.account_id).bind(q.character_id).bind(q.before).bind(q.outcome).fetch_all(pool(&state)?).await.map_err(database)?;
    let more = rows.len() > 100;
    let events: Vec<_> = rows.into_iter().take(100).map(|v| v.0).collect();
    let next = if more {
        events.last().map(|v| v["id"].clone())
    } else {
        None
    };
    Ok(Json(json!({"events":events,"next_before":next})))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct OperatorAction {
    operation_id: Uuid,
    action: String,
    reason: String,
    character_id: Option<Uuid>,
}
pub(crate) async fn act(
    State(state): State<Arc<AppState>>,
    Path(id): Path<Uuid>,
    headers: HeaderMap,
    payload: Result<Json<OperatorAction>, JsonRejection>,
) -> Result<Json<Value>, AuthError> {
    // The random process token is only available through the guarded local reader.
    // Exact Origin is mandatory on writes (the outer guard validates its value).
    if !headers.contains_key("origin")
        || !headers
            .get("x-operator-token")
            .is_some_and(|v| v.as_bytes() == state.operator_token.to_string().as_bytes())
    {
        return Err(AuthError(StatusCode::FORBIDDEN, "INVALID_OPERATOR_TOKEN"));
    }
    let Json(p) = payload.map_err(|_| invalid())?;
    let reason = p.reason.trim();
    if p.operation_id.get_version_num() != 4
        || !["disable", "enable", "revoke_sessions"].contains(&p.action.as_str())
        || !(2..=240).contains(&reason.chars().count())
        || reason.chars().any(char::is_control)
    {
        return Err(invalid());
    }
    // Preserve the existing receipt digest for account-only requests.
    let intent = if let Some(character) = p.character_id {
        serde_json::to_vec(&("operator.character-context-v1",id,character,&p.action,reason))
    } else { serde_json::to_vec(&(id,&p.action,reason)) };
    let digest = Sha256::digest(intent.expect("operator intent")).to_vec();
    let mut tx = pool(&state)?.begin().await.map_err(database)?;
    // Serialize the operation UUID globally, then account. No untrusted value is SQL.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,17))")
        .bind(p.operation_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    if let Some(r) =
        sqlx::query("SELECT request_digest,result FROM operator_receipts WHERE operation_id=$1")
            .bind(p.operation_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(database)?
    {
        if r.get::<Vec<u8>, _>("request_digest") != digest {
            return Err(AuthError(StatusCode::CONFLICT, "IDEMPOTENCY_CONFLICT"));
        }
        let mut result = r.get::<DbJson<Value>, _>("result").0;
        result["replayed"] = json!(true);
        return Ok(Json(result));
    }
    let before: bool = sqlx::query_scalar("SELECT disabled FROM accounts WHERE id=$1 FOR UPDATE")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(database)?
        .ok_or(AuthError(StatusCode::NOT_FOUND, "ACCOUNT_NOT_FOUND"))?;
    let disabled = match p.action.as_str() {
        "disable" => true,
        "enable" => false,
        _ => before,
    };
    let selected_character = if let Some(character) = p.character_id {
        let name: String = sqlx::query_scalar("SELECT display_name FROM characters WHERE id=$1 AND account_id=$2")
            .bind(character).bind(id).fetch_optional(&mut *tx).await.map_err(database)?
            .ok_or(AuthError(StatusCode::FORBIDDEN,"CHARACTER_NOT_OWNED"))?;
        json!({"id":character,"display_name":name})
    } else { Value::Null };
    sqlx::query("UPDATE accounts SET disabled=$2 WHERE id=$1")
        .bind(id)
        .bind(disabled)
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    let revoked = if p.action != "enable" {
        sqlx::query("UPDATE sessions SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE account_id=$1 AND revoked_at IS NULL")
            .bind(id).execute(&mut *tx).await.map_err(database)?.rows_affected()
    } else {
        0
    };
    let result = json!({"operation_id":p.operation_id,"account_id":id,"action":p.action,"disabled":disabled,"revoked_sessions":revoked,"replayed":false});
    security::append(&mut *tx, Event{account:Some(id),character:p.character_id,session:None,operation:Some(p.operation_id),action:&format!("operator.{}",p.action),outcome:"accepted",code:"OK",details:json!({"reason":reason,"disabled_before":before,"disabled_after":disabled,"revoked_sessions":revoked,"actor":"local_operator","scope":"account","selected_character":selected_character})}).await.map_err(database)?;
    sqlx::query(
        "INSERT INTO operator_receipts(operation_id,request_digest,result) VALUES($1,$2,$3)",
    )
    .bind(p.operation_id)
    .bind(digest)
    .bind(DbJson(&result))
    .execute(&mut *tx)
    .await
    .map_err(database)?;
    tx.commit().await.map_err(database)?;
    Ok(Json(result))
}
