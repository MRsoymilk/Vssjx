pub mod shop;
pub mod combat_balance;
pub mod skill_balance;
pub mod monster_combat;
pub mod loot;
pub mod builds;
pub mod progression;
pub mod team_loot;
pub mod endless;
pub mod soul;
pub mod social;
pub mod team_rules;
pub mod teams;
pub mod skills;
pub mod auth;
pub mod attributes;
pub mod announcements;
pub mod characters;
pub mod chat;
mod chat_admin;
pub mod config;
pub mod logging;
mod monitor;
mod monitor_pages;
mod security;
mod user_admin;
pub mod observability;
pub mod population;
pub mod ai_world;
pub mod pve_rules;
pub mod pve;
pub mod duel;
pub mod world;
pub mod world_map;
pub mod world_replication;
pub mod web_origin;

use axum::response::IntoResponse;
use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    middleware,
    response::Response,
    routing::{get, post},
};
use serde::Serialize;
use std::sync::Arc;

pub const SERVICE: &str = "vssjx";
pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Serialize)]
struct Health {
    service: &'static str,
    status: &'static str,
    stage: &'static str,
}

#[derive(Serialize)]
struct ServerInfo {
    service: &'static str,
    protocol_version: u32,
    server_name: String,
    version: &'static str,
    stage: &'static str,
    capabilities: Vec<&'static str>,
}

#[derive(Serialize)]
struct ApiError {
    code: &'static str,
}

pub(crate) struct AppState {
    config: config::Config,
    auth: Option<auth::AuthService>,
    world: Option<Arc<world::WorldHub>>,
    metrics: Arc<observability::Observability>,
    announcements: Arc<announcements::Announcements>,
    operator_token: uuid::Uuid,
}

pub fn app(config: config::Config) -> Router {
    build_app(config, None)
}

pub fn app_with_auth(config: config::Config, auth: auth::AuthService) -> Router {
    build_app(config, Some(auth))
}

fn build_app(config: config::Config, auth: Option<auth::AuthService>) -> Router {
    apps(config, auth, logging::LogHealth::default()).0
}

/// Public game router and private monitoring router share the same process state.
/// The caller must serve the second router on a dedicated loopback listener.
pub fn apps(
    config: config::Config,
    auth: Option<auth::AuthService>,
    log_health: logging::LogHealth,
) -> (Router, Router) {
    let metrics = Arc::new(observability::Observability::new(log_health));
    tracing::info!(boot_id=%metrics.boot_id, "process diagnostics initialized");
    let world = auth
        .as_ref()
        .map(|_| world::WorldHub::with_metrics(config.world, metrics.clone()));
    let state = Arc::new(AppState {
        config,
        auth,
        world,
        metrics: metrics.clone(),
        announcements: Arc::new(announcements::Announcements::default()),
        operator_token: uuid::Uuid::new_v4(),
    });
    monitor::sample_database(&state);
    let router = Router::new()
        .route("/healthz", get(health))
        .route("/readyz", get(ready))
        .route("/api/v1/server-info", get(server_info))
        .route("/api/v1/auth/register", post(auth::register))
        .route("/api/v1/auth/login", post(auth::login))
        .route("/api/v1/auth/refresh", post(auth::refresh))
        .route("/api/v1/auth/me", get(auth::me))
        .route("/api/v1/auth/logout", post(auth::logout))
        .route("/api/v1/world/ticket", post(world::ticket))
        .route("/api/v1/world/ws", get(world::upgrade))
        .route("/api/v1/social", post(social::command))
        .route("/api/v1/teams", post(teams::command))
        .route(
            "/api/v1/characters",
            get(characters::list).post(characters::create),
        )
        .route(
            "/api/v1/character-operations/{operation_id}",
            get(characters::receipt),
        )
        .fallback(|| async { (StatusCode::NOT_FOUND, Json(ApiError { code: "NOT_FOUND" })) })
        .layer(DefaultBodyLimit::max(4096))
        .layer(middleware::map_response(no_store))
        .layer(middleware::from_fn_with_state(state.clone(), security::http_rejections))
        .layer(middleware::from_fn_with_state(
            metrics,
            observability::request,
        ))
        .with_state(state.clone());
    (router, monitor::router(state))
}

async fn no_store(mut response: Response) -> Response {
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        axum::http::HeaderValue::from_static("no-store"),
    );
    response
}

async fn health(State(state): State<Arc<AppState>>) -> Json<Health> {
    Json(Health {
        service: SERVICE,
        status: "ok",
        stage: if state.auth.is_some() {
            "account_auth"
        } else {
            "connection_only"
        },
    })
}

async fn ready(State(state): State<Arc<AppState>>) -> Response {
    if let Some(auth) = &state.auth
        && !auth.healthy().await
    {
        return auth::AuthError(StatusCode::SERVICE_UNAVAILABLE, "DATABASE_UNAVAILABLE")
            .into_response();
    }
    health(State(state)).await.into_response()
}

async fn server_info(State(state): State<Arc<AppState>>) -> impl axum::response::IntoResponse {
    (
        [(axum::http::header::CACHE_CONTROL, "no-store")],
        Json(ServerInfo {
            service: SERVICE,
            protocol_version: PROTOCOL_VERSION,
            server_name: state.config.server_name.clone(),
            version: env!("CARGO_PKG_VERSION"),
            stage: if state.auth.is_some() {
                "account_auth"
            } else {
                "connection_only"
            },
            capabilities: if state.auth.is_some() {
                vec![
                    "account_auth",
                    "character_creation",
                    "shared_world",
                    "public_chat",
                    "social_v1",
                ]
            } else {
                vec![]
            },
        }),
    )
}
