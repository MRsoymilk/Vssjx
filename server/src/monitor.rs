//! A separate, strictly local operational listener with guarded announcements.
use crate::{AppState, observability::now_ms};
use axum::{
    Json, Router,
    extract::{ConnectInfo, DefaultBodyLimit, Request, State, rejection::JsonRejection},
    http::{StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
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
            get(|| async { crate::monitor_pages::render("overview") }),
        )
        .route("/users", get(|| async { crate::monitor_pages::render("users") }))
        .route("/users/{id}", get(|axum::extract::Path(_): axum::extract::Path<uuid::Uuid>| async { crate::monitor_pages::render("user") }))
        .route("/audit", get(|| async { crate::monitor_pages::render("audit") }))
        .route("/announcements", get(|| async { crate::monitor_pages::render("announcements") }))
        .route("/chat", get(|| async { crate::monitor_pages::render("chat") }))
        .route("/maps", get(|| async { crate::monitor_pages::render("maps") }))
        .route("/maps.js", get(|| async { ([(header::CONTENT_TYPE,"text/javascript; charset=utf-8")], include_str!("monitor_assets/maps.js")) }))
        .route("/maps.css", get(|| async { ([(header::CONTENT_TYPE,"text/css; charset=utf-8")], include_str!("monitor_assets/maps.css")) }))
        .route("/api/maps", get(crate::map_admin::list))
        .route("/api/maps/{id}", get(crate::map_admin::detail))
        .route("/api/maps/{id}/actions", axum::routing::post(crate::map_admin::act).layer(DefaultBodyLimit::max(65536)))
        .route("/chat.js", get(|| async { ([(header::CONTENT_TYPE,"text/javascript; charset=utf-8")], include_str!("monitor_assets/chat.js")) }))
        .route("/api/chat", get(crate::chat_admin::history))
        .route("/api/chat/actions", axum::routing::post(crate::chat_admin::act))
        .route("/admin.js", get(|| async { ([(header::CONTENT_TYPE,"text/javascript; charset=utf-8")], include_str!("monitor_assets/admin.js")) }))
        .route("/audit.js", get(|| async { ([(header::CONTENT_TYPE,"text/javascript; charset=utf-8")], include_str!("monitor_assets/audit.js")) }))
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
        .route("/api/online/daily", get(crate::online_stats::daily))
        .route("/users.js", get(|| async { ([(header::CONTENT_TYPE,"text/javascript; charset=utf-8")], include_str!("monitor_assets/users.js")) }))
        .route("/api/users", get(crate::user_admin::users))
        .route("/api/users/{id}", get(crate::user_admin::detail))
        .route("/api/users/{id}/actions", axum::routing::post(crate::user_admin::act))
        .route("/api/audit", get(crate::user_admin::audit))
        .route(
            "/announcements.js",
            get(|| async {
                (
                    [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
                    include_str!("monitor_assets/announcements.js"),
                )
            }),
        )
        .route(
            "/api/announcements",
            get(announcements)
                .post(publish_announcement)
                .delete(cancel_announcement),
        )
        .fallback(|| async { StatusCode::NOT_FOUND })
        .layer(middleware::from_fn(local_only))
        .layer(DefaultBodyLimit::max(4096))
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
    let origin_ok = request.headers().get(header::ORIGIN).is_none_or(|origin| {
        host.as_ref()
            .is_some_and(|host| origin.as_bytes() == format!("http://{host}").as_bytes())
    });
    let mut response =
        if !peer.is_some_and(|p| p.0.ip().is_loopback()) || !host_ok || !fetch_ok || !origin_ok {
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
async fn announcements(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(
        serde_json::json!({"csrf_token":state.announcements.csrf_token,
        "state":state.announcements.packet_since(None, Instant::now()).expect("current announcement").1}),
    )
}
fn announcement_error(code: &'static str, status: StatusCode) -> Response {
    (status, Json(serde_json::json!({"code":code}))).into_response()
}
fn announcement_token(state: &AppState, headers: &axum::http::HeaderMap) -> bool {
    headers.get("x-announcement-token").is_some_and(|value| {
        value.as_bytes() == state.announcements.csrf_token.to_string().as_bytes()
    })
}
async fn publish_announcement(
    State(state): State<Arc<AppState>>,
    headers: axum::http::HeaderMap,
    draft: Result<Json<crate::announcements::AnnouncementDraft>, JsonRejection>,
) -> Response {
    if !announcement_token(&state, &headers) {
        return announcement_error("INVALID_OPERATOR_TOKEN", StatusCode::FORBIDDEN);
    }
    let Ok(Json(draft)) = draft else {
        return announcement_error("INVALID_ANNOUNCEMENT", StatusCode::BAD_REQUEST);
    };
    match state.announcements.publish(draft, Instant::now()) {
        Ok(packet) => {
            tracing::info!("global announcement published");
            Json(packet).into_response()
        }
        Err(code) => announcement_error(code, StatusCode::BAD_REQUEST),
    }
}
#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct CancelAnnouncement {
    id: uuid::Uuid,
}
async fn cancel_announcement(
    State(state): State<Arc<AppState>>,
    headers: axum::http::HeaderMap,
    draft: Result<Json<CancelAnnouncement>, JsonRejection>,
) -> Response {
    if !announcement_token(&state, &headers) {
        return announcement_error("INVALID_OPERATOR_TOKEN", StatusCode::FORBIDDEN);
    }
    let Ok(Json(draft)) = draft else {
        return announcement_error("INVALID_ANNOUNCEMENT", StatusCode::BAD_REQUEST);
    };
    match state.announcements.cancel(draft.id, Instant::now()) {
        Ok(packet) => {
            tracing::info!("global announcement removed");
            Json(packet).into_response()
        }
        Err(code) => announcement_error(code, StatusCode::CONFLICT),
    }
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
