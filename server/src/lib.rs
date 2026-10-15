pub mod config;

use axum::{Json, Router, extract::State, http::StatusCode, routing::get};
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

pub fn app(config: config::Config) -> Router {
    Router::new()
        .route("/healthz", get(health))
        .route("/readyz", get(health))
        .route("/api/v1/server-info", get(server_info))
        .fallback(|| async { (StatusCode::NOT_FOUND, Json(ApiError { code: "NOT_FOUND" })) })
        .with_state(Arc::new(config))
}

async fn health() -> Json<Health> {
    Json(Health {
        service: SERVICE,
        status: "ok",
        stage: "connection_only",
    })
}

async fn server_info(
    State(config): State<Arc<config::Config>>,
) -> impl axum::response::IntoResponse {
    (
        [(axum::http::header::CACHE_CONTROL, "no-store")],
        Json(ServerInfo {
            service: SERVICE,
            protocol_version: PROTOCOL_VERSION,
            server_name: config.server_name.clone(),
            version: env!("CARGO_PKG_VERSION"),
            stage: "connection_only",
            // Discovery is available; account login and shared gameplay are not.
            capabilities: vec![],
        }),
    )
}
