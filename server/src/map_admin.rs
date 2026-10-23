//! Guarded local map editor. No scripts, SQL, terrain writes or player relocation.
use crate::{
    AppState,
    auth::{self, AuthError},
    map_rules::{self, Document},
};
use axum::{
    Json,
    extract::{Path, State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode},
};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{Row, types::Json as DbJson};
use std::sync::Arc;
use uuid::Uuid;
fn database(e: sqlx::Error) -> AuthError {
    crate::observability::database_error(&e, "map_admin");
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
fn error(code: &'static str) -> AuthError {
    AuthError(StatusCode::BAD_REQUEST, code)
}
fn known(id: &str) -> Result<(), AuthError> {
    if map_rules::DEFAULTS.contains_key(id) {
        Ok(())
    } else {
        Err(AuthError(StatusCode::NOT_FOUND, "MAP_NOT_FOUND"))
    }
}
pub(crate) async fn list(State(state): State<Arc<AppState>>) -> Result<Json<Value>, AuthError> {
    let auth = auth::service(&state)?;
    let active = map_rules::load(auth.pool()).await.map_err(database)?;
    Ok(Json(
        json!({"csrf_token":state.operator_token,"maps":map_rules::ids().iter().map(|id|{let d=active.document(id);json!({"id":id,"name":map_rules::title(id),"revision":active.revision(id),"entry_enabled":d.entry_enabled,"monsters":d.residents.iter().filter(|p|p.enabled&&crate::population::definitions_for(id).iter().any(|r|r.id==p.id&&r.kind!="npc")).count(),"npcs":d.residents.iter().filter(|p|p.enabled&&crate::population::definitions_for(id).iter().any(|r|r.id==p.id&&r.kind=="npc")).count()})}).collect::<Vec<_>>()}),
    ))
}
pub(crate) async fn detail(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<Value>, AuthError> {
    known(&id)?;
    let auth = auth::service(&state)?;
    let mut tx = auth.pool().begin().await.map_err(database)?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    let active = map_rules::load_tx(&mut tx).await.map_err(database)?;
    let draft =
        sqlx::query("SELECT revision,active_revision,document FROM map_drafts WHERE map_id=$1")
            .bind(&id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(database)?;
    let history=sqlx::query_scalar::<_,DbJson<Value>>("SELECT jsonb_build_object('revision',revision,'reason',reason,'created_at',created_at::text) FROM map_releases WHERE map_id=$1 ORDER BY revision DESC LIMIT 30").bind(&id).fetch_all(&mut *tx).await.map_err(database)?;
    let (revision, base, document) = draft
        .map(|r| {
            (
                r.get::<i64, _>("revision"),
                r.get::<i64, _>("active_revision"),
                r.get::<DbJson<Value>, _>("document").0,
            )
        })
        .unwrap_or((0, active.revision(&id), json!(active.document(&id))));
    tx.commit().await.map_err(database)?;
    let map = crate::world_map::WorldMap::load(&id).unwrap();
    Ok(Json(
        json!({"id":id,"name":map_rules::title(&id),"csrf_token":state.operator_token,"revision":revision,"base_revision":base,"active_revision":active.revision(&id),"document":document,"active":active.document(&id),"terrain":{"width":map.width,"height":map.height,"blocked":map.blocked},"residents":crate::population::definitions_for(&id),"history":history.into_iter().map(|v|v.0).collect::<Vec<_>>(),"activation":"发布后点位在下一次世界刷新生效，已有战斗数值不变；新击败使用新刷新时长，已有冷却不变；传送与地图禁入用于后续旅行，不移动现有玩家。"}),
    ))
}
#[derive(Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Action {
    operation_id: Uuid,
    action: String,
    revision: i64,
    reason: String,
    document: Option<Document>,
    release: Option<i64>,
}
pub(crate) async fn act(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
    headers: HeaderMap,
    payload: Result<Json<Action>, JsonRejection>,
) -> Result<Json<Value>, AuthError> {
    if !headers.contains_key("origin")
        || !headers
            .get("x-operator-token")
            .is_some_and(|v| v.as_bytes() == state.operator_token.to_string().as_bytes())
    {
        return Err(AuthError(StatusCode::FORBIDDEN, "INVALID_OPERATOR_TOKEN"));
    }
    known(&id)?;
    let Json(p) = payload.map_err(|_| error("INVALID_MAP_REQUEST"))?;
    if p.operation_id.get_version_num() != 4
        || p.revision < 0
        || !["save", "validate", "publish", "restore"].contains(&p.action.as_str())
        || !(2..=240).contains(&p.reason.trim().chars().count())
        || p.reason.chars().any(char::is_control)
        || p.document.is_some() != (p.action == "save")
        || p.release.is_some() != (p.action == "restore")
    {
        return Err(error("INVALID_MAP_REQUEST"));
    }
    let digest = Sha256::digest(serde_json::to_vec(&(&id, &p)).unwrap()).to_vec();
    let auth = auth::service(&state)?;
    let _publishing = auth.map_publish.lock().await;
    let mut tx = auth.pool().begin().await.map_err(database)?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1,36))")
        .bind(p.operation_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    if let Some(r) =
        sqlx::query("SELECT request_digest,result FROM map_operator_receipts WHERE operation_id=$1")
            .bind(p.operation_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(database)?
    {
        if r.get::<Vec<u8>, _>("request_digest") != digest {
            return Err(AuthError(StatusCode::CONFLICT, "IDEMPOTENCY_CONFLICT"));
        }
        let mut value = r.get::<DbJson<Value>, _>("result").0;
        value["replayed"] = json!(true);
        return Ok(Json(value));
    }
    sqlx::query("SELECT pg_advisory_xact_lock(360036)")
        .execute(&mut *tx)
        .await
        .map_err(database)?;
    let active = map_rules::load_tx(&mut tx).await.map_err(database)?;
    let row = sqlx::query(
        "SELECT revision,active_revision,document FROM map_drafts WHERE map_id=$1 FOR UPDATE",
    )
    .bind(&id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(database)?;
    let (revision, base, mut document) = if let Some(r) = row {
        (
            r.get::<i64, _>("revision"),
            r.get::<i64, _>("active_revision"),
            serde_json::from_value::<Document>(r.get::<DbJson<Value>, _>("document").0)
                .map_err(|_| error("INVALID_MAP_DOCUMENT"))?,
        )
    } else {
        (0, active.revision(&id), active.document(&id).clone())
    };
    if revision != p.revision {
        return Err(AuthError(StatusCode::CONFLICT, "STALE_MAP_DRAFT"));
    }
    let mut next = revision;
    let mut published = active.revision(&id);
    if p.action == "save" {
        document = p.document.unwrap();
    }
    if p.action == "restore" {
        document = if p.release == Some(0) {
            map_rules::DEFAULTS[&id].clone()
        } else {
            let v: DbJson<Value> = sqlx::query_scalar(
                "SELECT document FROM map_releases WHERE map_id=$1 AND revision=$2",
            )
            .bind(&id)
            .bind(p.release)
            .fetch_optional(&mut *tx)
            .await
            .map_err(database)?
            .ok_or(error("MAP_RELEASE_NOT_FOUND"))?;
            serde_json::from_value(v.0).map_err(|_| error("INVALID_MAP_DOCUMENT"))?
        };
    }
    let errors = map_rules::validate_with_active(&id, &document, &active);
    if p.action == "publish" {
        if !errors.is_empty() {
            return Err(error("MAP_VALIDATION_FAILED"));
        }
        if base != active.revision(&id) {
            return Err(AuthError(StatusCode::CONFLICT, "STALE_MAP_BASE"));
        }
        published=sqlx::query_scalar("INSERT INTO map_releases(map_id,document,operation_id,reason) VALUES($1,$2,$3,$4) RETURNING revision").bind(&id).bind(DbJson(&document)).bind(p.operation_id).bind(p.reason.trim()).fetch_one(&mut *tx).await.map_err(database)?;
        sqlx::query("INSERT INTO map_active(map_id,revision) VALUES($1,$2) ON CONFLICT(map_id) DO UPDATE SET revision=EXCLUDED.revision").bind(&id).bind(published).execute(&mut *tx).await.map_err(database)?;
        for n in &document.gathering {
            sqlx::query("UPDATE gathering_nodes SET cell_x=$2,cell_y=$3,material=$4,duration_ms=$5,respawn_ms=$6,min_quantity=$7,max_quantity=$8,enabled=$9 WHERE id=$1 AND map_id=$10").bind(&n.id).bind(n.cell[0]).bind(n.cell[1]).bind(&n.material).bind(n.duration_ms).bind(n.respawn_ms).bind(n.min_quantity).bind(n.max_quantity).bind(n.enabled).bind(&id).execute(&mut *tx).await.map_err(database)?;
        }
    }
    if p.action != "validate" {
        next += 1;
        sqlx::query("INSERT INTO map_drafts(map_id,revision,active_revision,document) VALUES($1,$2,$3,$4) ON CONFLICT(map_id) DO UPDATE SET revision=EXCLUDED.revision,active_revision=EXCLUDED.active_revision,document=EXCLUDED.document,updated_at=now()")
            .bind(&id).bind(next).bind(if p.action=="publish"||p.action=="restore"{published}else{base}).bind(DbJson(&document)).execute(&mut *tx).await.map_err(database)?;
    }
    let result = json!({"ok":true,"revision":next,"active_revision":published,"errors":errors,"replayed":false});
    crate::security::append(&mut *tx,crate::security::Event{account:None,character:None,session:None,operation:Some(p.operation_id),action:&format!("operator.map.{}",p.action),outcome:"accepted",code:"OK",details:json!({"map_id":id,"reason":p.reason.trim(),"revision":next,"active_revision":published,"previous_active_revision":active.revision(&id)})}).await.map_err(database)?;
    sqlx::query(
        "INSERT INTO map_operator_receipts(operation_id,request_digest,result) VALUES($1,$2,$3)",
    )
    .bind(p.operation_id)
    .bind(digest)
    .bind(DbJson(&result))
    .execute(&mut *tx)
    .await
    .map_err(database)?;
    let snapshot = map_rules::load_tx(&mut tx).await.map_err(database)?;
    tx.commit().await.map_err(database)?;
    *auth.map_rules.write().expect("map rules") = snapshot;
    Ok(Json(result))
}
