use crate::AppState;
use crate::config::AuthConfig;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier, password_hash::SaltString};
use axum::{
    Json,
    extract::{ConnectInfo, Extension, State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use rand::{RngCore, rngs::OsRng};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{
    ConnectOptions, PgPool, Row,
    postgres::{PgConnectOptions, PgPoolOptions},
};
use std::{
    collections::HashMap,
    net::IpAddr,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::Semaphore;
use uuid::Uuid;

#[derive(Clone)]
pub struct AuthService {
    pool: PgPool,
    hash_slots: Arc<Semaphore>,
    dummy_hash: String,
    limiter: Arc<Mutex<Limiter>>,
    settings: AuthConfig,
}

struct Limiter {
    entries: HashMap<String, (Instant, u32)>,
    last_cleanup: Instant,
    settings: AuthConfig,
}

impl Limiter {
    fn admit(&mut self, ip: IpAddr, username: Option<&str>) -> bool {
        let mut keys = vec![
            ("global".to_string(), self.settings.rate_global),
            (format!("ip:{ip}"), self.settings.rate_ip),
        ];
        if let Some(name) = username {
            keys.push((format!("account:{name}"), self.settings.rate_account));
        }
        self.admit_keys(keys)
    }

    fn admit_keys(&mut self, keys: Vec<(String, u32)>) -> bool {
        let now = Instant::now();
        let window = Duration::from_secs(u64::from(self.settings.rate_window_seconds));
        if now.duration_since(self.last_cleanup) > window {
            self.entries
                .retain(|_, (since, _)| now.duration_since(*since) < window);
            self.last_cleanup = now;
        }
        for (key, limit) in &keys {
            if !self.entries.contains_key(key)
                && self.entries.len() >= self.settings.rate_max_keys as usize
            {
                return false;
            }
            let entry = self.entries.entry(key.clone()).or_insert((now, 0));
            if now.duration_since(entry.0) >= window {
                *entry = (now, 0);
            }
            if entry.1 >= *limit {
                return false;
            }
        }
        for (key, _) in keys {
            self.entries.get_mut(&key).expect("admitted key").1 += 1;
        }
        true
    }
}

#[derive(Debug)]
pub struct AuthError(pub StatusCode, pub &'static str);
impl IntoResponse for AuthError {
    fn into_response(self) -> Response {
        let mut response = (
            self.0,
            [("cache-control", "no-store")],
            Json(serde_json_error(self.1)),
        )
            .into_response();
        response
            .extensions_mut()
            .insert(crate::observability::ErrorCode(self.1));
        response
    }
}
#[derive(Serialize)]
struct ErrorBody {
    code: &'static str,
}
fn serde_json_error(code: &'static str) -> ErrorBody {
    ErrorBody { code }
}
fn unavailable() -> AuthError {
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
}
fn database_unavailable(error: sqlx::Error) -> AuthError {
    crate::observability::database_error(&error, "auth");
    unavailable()
}
fn unauthorized() -> AuthError {
    AuthError(StatusCode::UNAUTHORIZED, "UNAUTHORIZED")
}
fn busy() -> AuthError {
    AuthError(StatusCode::SERVICE_UNAVAILABLE, "SERVER_BUSY")
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Credentials {
    username: String,
    password: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RefreshRequest {
    refresh_token: String,
}
#[derive(Serialize)]
pub struct Account {
    pub id: Uuid,
    pub username: String,
}
#[derive(Serialize)]
pub struct AccountResponse {
    account: Account,
}
#[derive(Serialize)]
pub struct SessionResponse {
    account: Account,
    session_id: Uuid,
    access_token: String,
    refresh_token: String,
    expires_in: i32,
    refresh_expires_in: i32,
}

pub fn canonical_username(raw: &str) -> Result<String, AuthError> {
    let name = raw.trim().to_ascii_lowercase();
    if !(3..=32).contains(&name.len())
        || !name.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
    {
        return Err(AuthError(
            StatusCode::UNPROCESSABLE_ENTITY,
            "INVALID_USERNAME",
        ));
    }
    Ok(name)
}
pub fn validate_password(password: &str) -> Result<(), AuthError> {
    if !(12..=128).contains(&password.chars().count())
        || password.len() > 512
        || password.chars().all(char::is_whitespace)
    {
        return Err(AuthError(StatusCode::UNPROCESSABLE_ENTITY, "WEAK_PASSWORD"));
    }
    Ok(())
}

pub(crate) fn token() -> String {
    let mut bytes = [0_u8; 32];
    OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
pub(crate) fn token_digest(raw: &str) -> Result<Vec<u8>, AuthError> {
    if raw.len() != 64 || !raw.bytes().all(|c| c.is_ascii_hexdigit()) {
        return Err(unauthorized());
    }
    Ok(Sha256::digest(raw.as_bytes()).to_vec())
}

impl AuthService {
    pub async fn connect(url: &str, settings: AuthConfig) -> Result<Self, &'static str> {
        let options = url
            .parse::<PgConnectOptions>()
            .map_err(|_| "invalid database configuration")?
            .disable_statement_logging();
        let pool = PgPoolOptions::new()
            .max_connections(settings.db_max_connections)
            .acquire_timeout(Duration::from_secs(u64::from(settings.db_acquire_timeout_seconds)))
            .after_connect(move |connection, _| {
                Box::pin(async move {
                    sqlx::query("SELECT set_config('statement_timeout', $1, false), set_config('idle_in_transaction_session_timeout', $2, false)")
                        .bind(format!("{}ms", settings.db_statement_timeout_seconds * 1000))
                        .bind(format!("{}ms", settings.db_idle_transaction_timeout_seconds * 1000))
                        .execute(&mut *connection)
                        .await?;
                    Ok(())
                })
            })
            .connect_with(options)
            .await
            .map_err(|error| {
                crate::observability::database_error(&error, "connect");
                "database connection failed"
            })?;
        sqlx::migrate!("./migrations")
            .run(&pool)
            .await
            .map_err(|_| {
                tracing::error!(operation = "migrate", "database migration failed");
                "database migration failed"
            })?;
        let dummy_hash = tokio::task::spawn_blocking(|| {
            Argon2::default()
                .hash_password(
                    b"dummy-password-not-an-account",
                    &SaltString::generate(&mut OsRng),
                )
                .map(|h| h.to_string())
        })
        .await
        .map_err(|_| "password initialization failed")?
        .map_err(|_| "password initialization failed")?;
        Ok(Self {
            pool,
            hash_slots: Arc::new(Semaphore::new(settings.hash_workers as usize)),
            dummy_hash,
            limiter: Arc::new(Mutex::new(Limiter {
                entries: HashMap::new(),
                last_cleanup: Instant::now(),
                settings,
            })),
            settings,
        })
    }

    pub async fn healthy(&self) -> bool {
        match tokio::time::timeout(
            Duration::from_secs(u64::from(self.settings.db_ready_timeout_seconds)),
            sqlx::query("SELECT 1").execute(&self.pool),
        )
        .await
        {
            Ok(Ok(_)) => true,
            Ok(Err(error)) => {
                crate::observability::database_error(&error, "health_probe");
                false
            }
            Err(_) => {
                tracing::error!(
                    operation = "health_probe",
                    kind = "timeout",
                    "database health probe timed out"
                );
                false
            }
        }
    }
    pub(crate) fn admit(&self, ip: IpAddr, username: Option<&str>) -> Result<(), AuthError> {
        if self.limiter.lock().map_err(|_| busy())?.admit(ip, username) {
            Ok(())
        } else {
            Err(AuthError(StatusCode::TOO_MANY_REQUESTS, "RATE_LIMITED"))
        }
    }

    pub(crate) fn admit_creation(&self, account_id: Uuid) -> Result<(), AuthError> {
        let mut limiter = self.limiter.lock().map_err(|_| busy())?;
        let limit = limiter.settings.rate_account;
        if limiter.admit_keys(vec![(format!("character:{account_id}"), limit)]) {
            Ok(())
        } else {
            Err(AuthError(StatusCode::TOO_MANY_REQUESTS, "RATE_LIMITED"))
        }
    }

    async fn hash(&self, password: String) -> Result<String, AuthError> {
        let permit = self
            .hash_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| busy())?;
        tokio::task::spawn_blocking(move || {
            let _permit = permit;
            Argon2::default()
                .hash_password(password.as_bytes(), &SaltString::generate(&mut OsRng))
                .map(|h| h.to_string())
                .map_err(|_| busy())
        })
        .await
        .map_err(|_| busy())?
    }
    async fn verify(&self, password: String, hash: String) -> Result<bool, AuthError> {
        let permit = self
            .hash_slots
            .clone()
            .try_acquire_owned()
            .map_err(|_| busy())?;
        tokio::task::spawn_blocking(move || {
            let _permit = permit;
            let parsed = PasswordHash::new(&hash).map_err(|_| unavailable())?;
            Ok(Argon2::default()
                .verify_password(password.as_bytes(), &parsed)
                .is_ok())
        })
        .await
        .map_err(|_| busy())?
    }

    async fn register(&self, credentials: Credentials) -> Result<Account, AuthError> {
        let username = canonical_username(&credentials.username)?;
        validate_password(&credentials.password)?;
        let hash = self.hash(credentials.password).await?;
        let id = Uuid::new_v4();
        let inserted = sqlx::query("INSERT INTO accounts (id, username, password_hash) VALUES ($1, $2, $3) ON CONFLICT (username) DO NOTHING")
            .bind(id).bind(&username).bind(hash).execute(&self.pool).await.map_err(database_unavailable)?;
        if inserted.rows_affected() == 0 {
            return Err(AuthError(StatusCode::CONFLICT, "ACCOUNT_EXISTS"));
        }
        Ok(Account { id, username })
    }

    async fn login(&self, credentials: Credentials) -> Result<SessionResponse, AuthError> {
        let username = canonical_username(&credentials.username)?;
        if validate_password(&credentials.password).is_err() {
            return Err(unauthorized());
        }
        let account =
            sqlx::query("SELECT id, password_hash, disabled FROM accounts WHERE username = $1")
                .bind(&username)
                .fetch_optional(&self.pool)
                .await
                .map_err(database_unavailable)?;
        let hash = account
            .as_ref()
            .map(|r| r.get::<String, _>("password_hash"))
            .unwrap_or_else(|| self.dummy_hash.clone());
        if !self.verify(credentials.password, hash).await? || account.is_none() {
            return Err(unauthorized());
        }
        let row = account.ok_or_else(unauthorized)?;
        if row.get::<bool, _>("disabled") {
            return Err(unauthorized());
        }
        let account_id: Uuid = row.get("id");
        let mut transaction = self.pool.begin().await.map_err(database_unavailable)?;
        let enabled = sqlx::query("SELECT disabled FROM accounts WHERE id = $1 FOR UPDATE")
            .bind(account_id)
            .fetch_one(&mut *transaction)
            .await
            .map_err(database_unavailable)?;
        if enabled.get::<bool, _>("disabled") {
            return Err(unauthorized());
        }
        sqlx::query("DELETE FROM sessions WHERE account_id = $1 AND (revoked_at IS NOT NULL OR refresh_expires_at <= NOW())")
            .bind(account_id).execute(&mut *transaction).await.map_err(database_unavailable)?;
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM sessions WHERE account_id = $1")
            .bind(account_id)
            .fetch_one(&mut *transaction)
            .await
            .map_err(database_unavailable)?;
        if count >= i64::from(self.settings.max_sessions) {
            return Err(AuthError(
                StatusCode::TOO_MANY_REQUESTS,
                "SESSION_LIMIT_REACHED",
            ));
        }
        let response = SessionResponse {
            account: Account {
                id: account_id,
                username,
            },
            session_id: Uuid::new_v4(),
            access_token: token(),
            refresh_token: token(),
            expires_in: self.settings.access_seconds,
            refresh_expires_in: self.settings.refresh_seconds,
        };
        sqlx::query("INSERT INTO sessions (id, account_id, access_digest, refresh_digest, access_expires_at, refresh_expires_at) VALUES ($1, $2, $3, $4, NOW() + $5 * INTERVAL '1 second', NOW() + $6 * INTERVAL '1 second')")
            .bind(response.session_id).bind(account_id).bind(token_digest(&response.access_token)?).bind(token_digest(&response.refresh_token)?)
            .bind(response.expires_in).bind(response.refresh_expires_in).execute(&mut *transaction).await.map_err(database_unavailable)?;
        sqlx::query("INSERT INTO session_access_history (access_digest, session_id, expires_at) VALUES ($1, $2, NOW() + $3 * INTERVAL '1 second')")
            .bind(token_digest(&response.access_token)?).bind(response.session_id).bind(response.expires_in)
            .execute(&mut *transaction).await.map_err(database_unavailable)?;
        transaction.commit().await.map_err(database_unavailable)?;
        Ok(response)
    }

    async fn refresh(&self, refresh_token: &str) -> Result<SessionResponse, AuthError> {
        let digest = token_digest(refresh_token)?;
        let mut transaction = self.pool.begin().await.map_err(database_unavailable)?;
        let row = sqlx::query("SELECT s.id, s.account_id, a.username, FLOOR(EXTRACT(EPOCH FROM (s.refresh_expires_at - NOW())))::int AS remaining FROM sessions s JOIN accounts a ON a.id = s.account_id WHERE s.refresh_digest = $1 AND s.revoked_at IS NULL AND s.refresh_expires_at > NOW() AND NOT a.disabled FOR UPDATE OF s")
            .bind(digest).fetch_optional(&mut *transaction).await.map_err(database_unavailable)?.ok_or_else(unauthorized)?;
        let remaining: i32 = row.get("remaining");
        if remaining <= 0 {
            return Err(unauthorized());
        }
        let response = SessionResponse {
            account: Account {
                id: row.get("account_id"),
                username: row.get("username"),
            },
            session_id: row.get("id"),
            access_token: token(),
            refresh_token: token(),
            expires_in: self.settings.access_seconds.min(remaining),
            refresh_expires_in: remaining,
        };
        sqlx::query("UPDATE sessions SET access_digest=$1, refresh_digest=$2, access_expires_at=NOW() + $3 * INTERVAL '1 second' WHERE id=$4")
            .bind(token_digest(&response.access_token)?).bind(token_digest(&response.refresh_token)?).bind(response.expires_in).bind(response.session_id)
            .execute(&mut *transaction).await.map_err(database_unavailable)?;
        sqlx::query("DELETE FROM session_access_history WHERE session_id=$1 AND expires_at<=NOW()")
            .bind(response.session_id)
            .execute(&mut *transaction)
            .await
            .map_err(database_unavailable)?;
        sqlx::query("INSERT INTO session_access_history (access_digest, session_id, expires_at) VALUES ($1, $2, NOW() + $3 * INTERVAL '1 second')")
            .bind(token_digest(&response.access_token)?).bind(response.session_id).bind(response.expires_in)
            .execute(&mut *transaction).await.map_err(database_unavailable)?;
        transaction.commit().await.map_err(database_unavailable)?;
        Ok(response)
    }

    pub(crate) fn pool(&self) -> &PgPool {
        &self.pool
    }

    pub(crate) async fn live_session(&self, id: Uuid) -> Result<bool, AuthError> {
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.id=$1 AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp() AND NOT a.disabled)")
            .bind(id).fetch_one(&self.pool).await.map_err(database_unavailable)
    }

    pub(crate) async fn chat_muted(&self, id: Uuid) -> Result<bool, AuthError> {
        sqlx::query_scalar("SELECT COALESCE(a.chat_muted_until>clock_timestamp(),FALSE) FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.id=$1 AND s.revoked_at IS NULL AND s.access_expires_at>clock_timestamp() AND s.refresh_expires_at>clock_timestamp() AND NOT a.disabled")
            .bind(id).fetch_optional(&self.pool).await.map_err(database_unavailable)?.ok_or(AuthError(StatusCode::UNAUTHORIZED,"SESSION_REVOKED"))
    }

    pub(crate) async fn authorize_in(
        &self,
        connection: &mut sqlx::PgConnection,
        bearer: &str,
    ) -> Result<Account, AuthError> {
        let row = sqlx::query("SELECT a.id, a.username FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.access_digest=$1 AND s.revoked_at IS NULL AND s.access_expires_at > clock_timestamp() AND s.refresh_expires_at > clock_timestamp() AND NOT a.disabled FOR SHARE OF s")
            .bind(token_digest(bearer)?).fetch_optional(connection).await.map_err(database_unavailable)?.ok_or_else(unauthorized)?;
        Ok(Account {
            id: row.get("id"),
            username: row.get("username"),
        })
    }

    pub(crate) async fn me(&self, bearer: &str) -> Result<Account, AuthError> {
        let row = sqlx::query("SELECT a.id, a.username FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.access_digest=$1 AND s.revoked_at IS NULL AND s.access_expires_at > NOW() AND s.refresh_expires_at > NOW() AND NOT a.disabled")
            .bind(token_digest(bearer)?).fetch_optional(&self.pool).await.map_err(database_unavailable)?.ok_or_else(unauthorized)?;
        Ok(Account {
            id: row.get("id"),
            username: row.get("username"),
        })
    }
    async fn logout(&self, bearer: &str) -> Result<(), AuthError> {
        sqlx::query(
            "UPDATE sessions SET revoked_at=NOW() WHERE revoked_at IS NULL AND (access_digest=$1 OR id IN (SELECT session_id FROM session_access_history WHERE access_digest=$1 AND expires_at>NOW()))",
        )
        .bind(token_digest(bearer)?)
        .execute(&self.pool)
        .await
        .map_err(database_unavailable)?;
        Ok(())
    }
}

pub(crate) fn service(state: &AppState) -> Result<&AuthService, AuthError> {
    state.auth.as_ref().ok_or(AuthError(
        StatusCode::SERVICE_UNAVAILABLE,
        "AUTH_UNAVAILABLE",
    ))
}
pub(crate) type Peer = Option<Extension<ConnectInfo<std::net::SocketAddr>>>;
pub(crate) fn peer_ip(peer: Peer) -> IpAddr {
    peer.map(|Extension(ConnectInfo(address))| address.ip())
        .unwrap_or(IpAddr::from([127, 0, 0, 1]))
}
fn credentials(
    payload: Result<Json<Credentials>, JsonRejection>,
) -> Result<Credentials, AuthError> {
    payload
        .map(|Json(value)| value)
        .map_err(|_| AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST"))
}
pub(crate) fn bearer(headers: &HeaderMap) -> Result<&str, AuthError> {
    if headers.get_all("authorization").iter().count() != 1 {
        return Err(unauthorized());
    }
    let value = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .ok_or_else(unauthorized)?;
    let (scheme, value) = value.split_once(' ').ok_or_else(unauthorized)?;
    if !scheme.eq_ignore_ascii_case("bearer") {
        return Err(unauthorized());
    }
    token_digest(value)?;
    Ok(value)
}

pub(crate) async fn register(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    payload: Result<Json<Credentials>, JsonRejection>,
) -> Result<impl IntoResponse, AuthError> {
    let auth = service(&state)?;
    let payload = credentials(payload)?;
    let name = canonical_username(&payload.username)?;
    auth.admit(peer_ip(peer), Some(&name))?;
    Ok((
        StatusCode::CREATED,
        Json(AccountResponse {
            account: auth.register(payload).await?,
        }),
    ))
}
pub(crate) async fn login(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    payload: Result<Json<Credentials>, JsonRejection>,
) -> Result<Json<SessionResponse>, AuthError> {
    let auth = service(&state)?;
    let payload = credentials(payload)?;
    let name = canonical_username(&payload.username)?;
    auth.admit(peer_ip(peer), Some(&name))?;
    Ok(Json(auth.login(payload).await?))
}
pub(crate) async fn refresh(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    payload: Result<Json<RefreshRequest>, JsonRejection>,
) -> Result<Json<SessionResponse>, AuthError> {
    let auth = service(&state)?;
    auth.admit(peer_ip(peer), None)?;
    let Json(payload) =
        payload.map_err(|_| AuthError(StatusCode::BAD_REQUEST, "INVALID_REQUEST"))?;
    Ok(Json(auth.refresh(&payload.refresh_token).await?))
}
pub(crate) async fn me(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
) -> Result<Json<AccountResponse>, AuthError> {
    let auth = service(&state)?;
    auth.admit(peer_ip(peer), None)?;
    Ok(Json(AccountResponse {
        account: auth.me(bearer(&headers)?).await?,
    }))
}
pub(crate) async fn logout(
    State(state): State<Arc<AppState>>,
    peer: Peer,
    headers: HeaderMap,
) -> Result<StatusCode, AuthError> {
    let auth = service(&state)?;
    auth.admit(peer_ip(peer), None)?;
    auth.logout(bearer(&headers)?).await?;
    Ok(StatusCode::NO_CONTENT)
}
