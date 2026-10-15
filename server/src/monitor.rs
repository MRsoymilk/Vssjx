//! A separate, strictly local, read-only operational listener.
use crate::{AppState, observability::now_ms};
use axum::{
    Json, Router,
    extract::{ConnectInfo, Request, State},
    http::{StatusCode, header},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response},
    routing::get,
};
use std::{
    net::{IpAddr, SocketAddr},
    sync::Arc,
    time::{Duration, Instant},
};

pub(crate) fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route(
            "/",
            get(|| async { Html(include_str!("monitor_assets/index.html")) }),
        )
        .route(
            "/dashboard.js",
            get(|| async {
                (
                    [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
                    include_str!("monitor_assets/dashboard.js"),
                )
            }),
        )
        .route(
            "/dashboard.css",
            get(|| async {
                (
                    [(header::CONTENT_TYPE, "text/css; charset=utf-8")],
                    include_str!("monitor_assets/dashboard.css"),
                )
            }),
        )
        .route("/api/status", get(status))
        .fallback(|| async { StatusCode::NOT_FOUND })
        .layer(middleware::from_fn(local_only))
        .with_state(state)
}
async fn local_only(request: Request, next: Next) -> Response {
    let peer = request.extensions().get::<ConnectInfo<SocketAddr>>();
    let host = request
        .headers()
        .get(header::HOST)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<axum::http::uri::Authority>().ok());
    let host_ok = host.as_ref().is_some_and(|host| {
        host.host() == "localhost"
            || host
                .host()
                .trim_matches(['[', ']'])
                .parse::<IpAddr>()
                .is_ok_and(|ip| ip.is_loopback())
    });
    let fetch_ok = request
        .headers()
        .get("sec-fetch-site")
        .is_none_or(|v| v == "same-origin" || v == "none");
    let mut response = if !peer.is_some_and(|p| p.0.ip().is_loopback())
        || !host_ok
        || !fetch_ok
        || request.headers().contains_key(header::ORIGIN)
    {
        StatusCode::FORBIDDEN.into_response()
    } else {
        next.run(request).await
    };
    for (key, value) in [
        ("cache-control", "no-store"),
        ("x-content-type-options", "nosniff"),
        ("referrer-policy", "no-referrer"),
        (
            "content-security-policy",
            "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
        ),
    ] {
        response.headers_mut().insert(
            axum::http::HeaderName::from_static(key),
            axum::http::HeaderValue::from_static(value),
        );
    }
    response
}
async fn status(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let mut value = state.metrics.snapshot();
    value["service"] = "vssjx".into();
    value["version"] = env!("CARGO_PKG_VERSION").into();
    value["database"] = state
        .metrics
        .database
        .lock()
        .expect("database health")
        .clone();
    value["world"] = state
        .world
        .as_ref()
        .map(|w| w.monitor_snapshot())
        .unwrap_or(serde_json::Value::Null);
    value["process"] = serde_json::json!({"pid":std::process::id(),"rss_bytes":rss_bytes()});
    Json(value)
}
fn rss_bytes() -> Option<u64> {
    let text = std::fs::read_to_string("/proc/self/status").ok()?;
    let line = text.lines().find(|l| l.starts_with("VmRSS:"))?;
    line.split_whitespace()
        .nth(1)?
        .parse::<u64>()
        .ok()?
        .checked_mul(1024)
}
pub(crate) fn sample_database(state: &Arc<AppState>) {
    if state.auth.is_none() {
        *state.metrics.database.lock().expect("database health") =
            serde_json::json!({"status":"not_configured"});
        return;
    }
    let weak = Arc::downgrade(state);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        let mut previous = None;
        loop {
            interval.tick().await;
            let Some(state) = weak.upgrade() else { break };
            let auth = state.auth.as_ref().expect("configured auth");
            let started = Instant::now();
            let healthy = auth.healthy().await;
            let status = if healthy { "ok" } else { "unavailable" };
            *state.metrics.database.lock().expect("database health") = serde_json::json!({
                "status":status,"checked_at_ms":now_ms(),"probe_ms":started.elapsed().as_secs_f64()*1000.0,
                "pool_size":auth.pool().size(),"pool_idle":auth.pool().num_idle(), "pool_limit":state.config.auth.db_max_connections,
            });
            if previous != Some(healthy) {
                if healthy {
                    tracing::info!("database health recovered");
                } else {
                    tracing::error!("database health unavailable");
                    state
                        .metrics
                        .event("database", "DATABASE_UNAVAILABLE", state.metrics.boot_id);
                }
            }
            previous = Some(healthy);
        }
    });
}
