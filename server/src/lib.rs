pub mod auth;
pub mod characters;
pub mod config;
pub mod world_map;

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
}

pub fn app(config: config::Config) -> Router {
    build_app(config, None)
}

pub fn app_with_auth(config: config::Config, auth: auth::AuthService) -> Router {
    build_app(config, Some(auth))
}

fn build_app(config: config::Config, auth: Option<auth::AuthService>) -> Router {
    Router::new()
        .route("/healthz", get(health))
        .route("/readyz", get(ready))
        .route("/api/v1/server-info", get(server_info))
        .route("/api/v1/auth/register", post(auth::register))
        .route("/api/v1/auth/login", post(auth::login))
        .route("/api/v1/auth/refresh", post(auth::refresh))
        .route("/api/v1/auth/me", get(auth::me))
        .route("/api/v1/auth/logout", post(auth::logout))
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
        .with_state(Arc::new(AppState { config, auth }))
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
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ApiError {
                code: "DATABASE_UNAVAILABLE",
            }),
        )
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
                vec!["account_auth", "character_creation"]
            } else {
                vec![]
            },
        }),
    )
}
