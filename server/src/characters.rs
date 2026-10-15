//! Account-scoped creation, before CharacterActor/world ownership exists.
use crate::{
    AppState,
    auth::{self, AuthError, Peer},
};
use axum::{
    Json,
    extract::{Path, State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{FromRow, Row, types::Json as DbJson};
use std::sync::Arc;
use uuid::Uuid;

pub const RULES_VERSION: &str = "creation-v1";
pub const NAME_RULES_VERSION: &str = "nickname-v1";

/// Deliberate fixed whitelist, not deployment-dependent Unicode case folding.
pub fn canonical_name(raw: &str) -> Result<(String, String), AuthError> {
    let display = raw.trim_matches(' ');
    if !(2..=12).contains(&display.chars().count())
        || !display.chars().all(|c| {
            c.is_ascii_alphanumeric() || c == '_' || ('\u{4e00}'..='\u{9fff}').contains(&c)
        })
    {
        return Err(AuthError(StatusCode::UNPROCESSABLE_ENTITY, "INVALID_NAME"));
    }
    Ok((display.to_owned(), display.to_ascii_lowercase()))
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CreateCharacter {
    #[serde(deserialize_with = "operation_id")]
    operation_id: Uuid,
    display_name: String,
    job: u8,
    gender: u8,
    school: u8,
    rules_version: String,
}

fn operation_id<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Uuid, D::Error> {
    let raw = String::deserialize(deserializer)?;
    let id =
        Uuid::parse_str(&raw).map_err(|_| serde::de::Error::custom("invalid operation UUID"))?;
    if raw.len() != 36
        || raw.to_ascii_lowercase() != id.hyphenated().to_string()
        || id.get_version_num() != 4
        || id.get_variant() != uuid::Variant::RFC4122
    {
        return Err(serde::de::Error::custom(
            "operation_id must be a hyphenated UUIDv4",
        ));
    }
    Ok(id)
}

#[derive(Clone, Serialize, FromRow)]
pub(crate) struct Character {
    pub(crate) id: Uuid,
    pub(crate) display_name: String,
    pub(crate) name_rules_version: String,
    pub(crate) rules_version: String,
    pub(crate) job: i16,
    pub(crate) gender: i16,
    pub(crate) school: i16,
    pub(crate) level: i32,
    pub(crate) xp: i32,
    pub(crate) gold: i32,
    pub(crate) hp: i32,
    pub(crate) mp: i32,
    pub(crate) quest_stage: i32,
    pub(crate) map_id: String,
    pub(crate) cell_x: i32,
    pub(crate) cell_y: i32,
    pub(crate) state_revision: String,
}
pub(crate) const CHARACTER_COLUMNS: &str = "id, display_name, name_rules_version, rules_version, job, gender, school, level, xp, gold, hp, mp, quest_stage, map_id, cell_x, cell_y, state_revision::text";

fn database_error(error: sqlx::Error) -> AuthError {
    crate::observability::database_error(&error, "characters");
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}

pub(crate) async fn list(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
) -> Result<Json<Value>, AuthError> {
    let auth = auth::service(&state)?;
    auth.admit(auth::peer_ip(peer), None)?;
    let account = auth.me(auth::bearer(&headers)?).await?;
    // Single query: no mixed-version attributes/inventory snapshot.
    let characters = sqlx::query_as::<_, Character>(&format!(
        "SELECT {CHARACTER_COLUMNS} FROM characters WHERE account_id=$1"
    ))
    .bind(account.id)
    .fetch_all(auth.pool())
    .await
    .map_err(database_error)?;
    Ok(Json(
        json!({"characters": characters, "rules_version": RULES_VERSION, "name_rules_version": NAME_RULES_VERSION}),
    ))
}

fn receipt_response(status: i16, mut result: Value, replayed: bool) -> Response {
    result["replayed"] = json!(replayed);
    (
        StatusCode::from_u16(status as u16).expect("constrained receipt status"),
        Json(result),
    )
        .into_response()
}

pub(crate) async fn receipt(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
    Path(operation_id): Path<Uuid>,
) -> Result<Response, AuthError> {
    let auth = auth::service(&state)?;
    auth.admit(auth::peer_ip(peer), None)?;
    let account = auth.me(auth::bearer(&headers)?).await?;
    let row = sqlx::query("SELECT http_status, result FROM account_operation_receipts WHERE account_id=$1 AND operation_id=$2")
        .bind(account.id).bind(operation_id).fetch_optional(auth.pool()).await.map_err(database_error)?
        .ok_or(AuthError(StatusCode::NOT_FOUND, "OPERATION_NOT_FOUND"))?;
    Ok(receipt_response(
        row.get("http_status"),
        row.get::<DbJson<Value>, _>("result").0,
        true,
    ))
}

pub(crate) async fn create(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
    payload: Result<Json<CreateCharacter>, JsonRejection>,
) -> Result<Response, AuthError> {
    let auth = auth::service(&state)?;
    let ip = auth::peer_ip(peer);
    auth.admit(ip, None)?;
    let bearer = auth::bearer(&headers)?;
    let account = auth.me(bearer).await?;
    auth.admit_creation(account.id)?;
    let Json(payload) =
        payload.map_err(|_| AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST"))?;
    if payload.display_name.chars().count() > 256 || payload.rules_version.chars().count() > 64 {
        return Err(AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST"));
    }
    // Keep display case in identity: changing it is a different business intent.
    // Only ordinary outer spaces are semantically irrelevant in nickname-v1.
    // A versioned tuple fixes serialization order even if serde_json map features change.
    let digest = Sha256::digest(
        serde_json::to_vec(&(
            "character.create:v1",
            payload.display_name.trim_matches(' '),
            payload.job,
            payload.gender,
            payload.school,
            &payload.rules_version,
        ))
        .expect("typed request serialization"),
    )
    .to_vec();
    let mut tx = auth.pool().begin().await.map_err(database_error)?;
    // Every creation on an account serializes here. Login uses the same lock order.
    sqlx::query("SELECT id FROM accounts WHERE id=$1 FOR UPDATE")
        .bind(account.id)
        .fetch_one(&mut *tx)
        .await
        .map_err(database_error)?;
    auth.authorize_in(&mut tx, bearer).await?;
    if let Some(row) = sqlx::query("SELECT request_digest, http_status, result FROM account_operation_receipts WHERE account_id=$1 AND operation_id=$2")
        .bind(account.id).bind(payload.operation_id).fetch_optional(&mut *tx).await.map_err(database_error)? {
        if row.get::<Vec<u8>, _>("request_digest") != digest { return Err(AuthError(StatusCode::CONFLICT, "IDEMPOTENCY_CONFLICT")); }
        return Ok(receipt_response(row.get("http_status"), row.get::<DbJson<Value>, _>("result").0, true));
    }
    let has_character: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM characters WHERE account_id=$1)")
            .bind(account.id)
            .fetch_one(&mut *tx)
            .await
            .map_err(database_error)?;
    let name = canonical_name(&payload.display_name);
    let refusal = if has_character {
        Some((409_i16, "CHARACTER_LIMIT_REACHED"))
    } else if payload.rules_version != RULES_VERSION {
        Some((422, "RULES_UNSUPPORTED"))
    } else if payload.job > 2 || payload.gender > 1 || payload.school > 2 {
        Some((422, "INVALID_APPEARANCE"))
    } else if name.is_err() {
        Some((422, "INVALID_NAME"))
    } else {
        None
    };
    let (status, mut result) = if let Some((status, code)) = refusal {
        (status, json!({"code": code}))
    } else {
        let (display, key) = name.expect("validated name");
        let id = Uuid::new_v4();
        let inserted = sqlx::query("INSERT INTO characters (id, account_id, display_name, name_key, name_rules_version, rules_version, job, gender, school, hp, mp) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT DO NOTHING")
            .bind(id).bind(account.id).bind(display).bind(key).bind(NAME_RULES_VERSION).bind(RULES_VERSION)
            .bind(i16::from(payload.job)).bind(i16::from(payload.gender)).bind(i16::from(payload.school))
            .bind([120_i32,95,85][payload.job as usize]).bind([35_i32,45,65][payload.job as usize])
            .execute(&mut *tx).await.map_err(database_error)?;
        if inserted.rows_affected() == 0 {
            (409, json!({"code": "NAME_TAKEN"}))
        } else {
            sqlx::query("INSERT INTO inventory_items (id, character_id, definition_id, quantity) VALUES ($1,$2,'potion',6),($3,$2,'sword',1)")
                .bind(Uuid::new_v4()).bind(id).bind(Uuid::new_v4()).execute(&mut *tx).await.map_err(database_error)?;
            let character = sqlx::query_as::<_, Character>(&format!(
                "SELECT {CHARACTER_COLUMNS} FROM characters WHERE id=$1"
            ))
            .bind(id)
            .fetch_one(&mut *tx)
            .await
            .map_err(database_error)?;
            (201, json!({"character": character}))
        }
    };
    result["operation_id"] = json!(payload.operation_id);
    sqlx::query("INSERT INTO account_operation_receipts (account_id, operation_id, operation_type, request_digest, http_status, result) VALUES ($1,$2,'character.create',$3,$4,$5)")
        .bind(account.id).bind(payload.operation_id).bind(digest).bind(status).bind(DbJson(&result)).execute(&mut *tx).await.map_err(database_error)?;
    tx.commit().await.map_err(database_error)?;
    Ok(receipt_response(status, result, false))
}
