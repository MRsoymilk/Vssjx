//! Bounded, privacy-safe process metrics. Never accepts raw request paths,
//! account names, tokens, frame bodies, SQL messages or chat text as labels.
use axum::{
    extract::{MatchedPath, Request, State},
    http::HeaderValue,
    middleware::Next,
    response::Response,
};
use serde::Serialize;
use std::{
    collections::{BTreeMap, VecDeque},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{Instant, SystemTime, UNIX_EPOCH},
};
use tracing::Instrument;
use uuid::Uuid;

pub const LATENCY_BOUNDS_MS: [u64; 10] = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000];
#[derive(Clone)]
pub(crate) struct ErrorCode(pub &'static str);
#[derive(Default, Serialize)]
pub struct HttpMetric {
    requests: u64,
    responses_2xx: u64,
    responses_3xx: u64,
    responses_4xx: u64,
    responses_5xx: u64,
    upgrades: u64,
    latency_sum_ms: f64,
    latency_max_ms: f64,
    latency_buckets: [u64; 11],
}
#[derive(Serialize)]
struct Event {
    time_ms: u64,
    kind: &'static str,
    code: &'static str,
    correlation_id: Uuid,
}
#[derive(Default, Serialize)]
struct Events {
    http: BTreeMap<String, HttpMetric>,
    errors: BTreeMap<&'static str, u64>,
    recent: VecDeque<Event>,
}
pub struct Observability {
    pub boot_id: Uuid,
    started: Instant,
    events: Mutex<Events>,
    pub http_active: AtomicU64,
    pub ws_active: AtomicU64,
    pub ws_opened: AtomicU64,
    pub ws_closed: AtomicU64,
    pub ws_sent_bytes: AtomicU64,
    pub ws_send_failures: AtomicU64,
    pub ticks: AtomicU64,
    pub late_ticks: AtomicU64,
    pub tick_interval_us: AtomicU64,
    pub tick_work_us: AtomicU64,
    pub tick_max_work_us: AtomicU64,
    pub last_tick_ms: AtomicU64,
    pub publication_bytes: AtomicU64,
    pub database: Mutex<serde_json::Value>,
    pub log_health: crate::logging::LogHealth,
}
impl Default for Observability {
    fn default() -> Self {
        Self::new(crate::logging::LogHealth::default())
    }
}
impl Observability {
    pub fn new(log_health: crate::logging::LogHealth) -> Self {
        Self {
            boot_id: Uuid::new_v4(),
            started: Instant::now(),
            events: Mutex::new(Events::default()),
            http_active: AtomicU64::new(0),
            ws_active: AtomicU64::new(0),
            ws_opened: AtomicU64::new(0),
            ws_closed: AtomicU64::new(0),
            ws_sent_bytes: AtomicU64::new(0),
            ws_send_failures: AtomicU64::new(0),
            ticks: AtomicU64::new(0),
            late_ticks: AtomicU64::new(0),
            tick_interval_us: AtomicU64::new(0),
            tick_work_us: AtomicU64::new(0),
            tick_max_work_us: AtomicU64::new(0),
            publication_bytes: AtomicU64::new(0),
            last_tick_ms: AtomicU64::new(0),
            database: Mutex::new(serde_json::json!({"status":"pending"})),
            log_health,
        }
    }
    pub fn record_tick(&self, interval_us: u64, work_us: u64, publication_bytes: usize) {
        self.ticks.fetch_add(1, Ordering::Relaxed);
        self.last_tick_ms.store(now_ms(), Ordering::Relaxed);
        if interval_us > 150_000 {
            self.late_ticks.fetch_add(1, Ordering::Relaxed);
        }
        self.tick_interval_us.store(interval_us, Ordering::Relaxed);
        self.tick_work_us.store(work_us, Ordering::Relaxed);
        self.tick_max_work_us.fetch_max(work_us, Ordering::Relaxed);
        self.publication_bytes
            .fetch_add(publication_bytes as u64, Ordering::Relaxed);
    }
    pub fn event(&self, kind: &'static str, code: &'static str, id: Uuid) {
        let mut events = self.events.lock().expect("observability");
        // Codes originate exclusively in the server's fixed protocol constants.
        *events.errors.entry(code).or_default() += 1;
        if events.recent.len() == 100 {
            events.recent.pop_front();
        }
        events.recent.push_back(Event {
            time_ms: now_ms(),
            kind,
            code,
            correlation_id: id,
        });
    }
    pub fn snapshot(&self) -> serde_json::Value {
        let events = self.events.lock().expect("observability");
        let load = |v: &AtomicU64| v.load(Ordering::Relaxed);
        serde_json::json!({
            "boot_id": self.boot_id, "uptime_seconds": self.started.elapsed().as_secs_f64(), "sample_time_ms": now_ms(),
            "http": {"in_flight":load(&self.http_active), "routes":events.http, "latency_bucket_upper_bounds_ms":LATENCY_BOUNDS_MS, "last_bucket":"+Inf"},
            "websocket": {"active":load(&self.ws_active),"opened":load(&self.ws_opened),"closed":load(&self.ws_closed),"sent_application_bytes":load(&self.ws_sent_bytes),"send_failures":load(&self.ws_send_failures)},
            "tick": {"count":load(&self.ticks),"late_intervals":load(&self.late_ticks),"last_interval_ms":load(&self.tick_interval_us) as f64/1000.0,"last_work_ms":load(&self.tick_work_us) as f64/1000.0,"max_work_ms":load(&self.tick_max_work_us) as f64/1000.0,"shared_publication_bytes":load(&self.publication_bytes)},
            "errors":events.errors, "recent_events":events.recent,
            "logging":{"dropped_records":self.log_health.dropped(),"file_io_errors":self.log_health.io_errors()},
        })
    }
    pub fn socket(self: &Arc<Self>, id: Uuid) -> SocketGuard {
        self.ws_active.fetch_add(1, Ordering::Relaxed);
        self.ws_opened.fetch_add(1, Ordering::Relaxed);
        tracing::info!(%id, "world connection opened");
        SocketGuard {
            metrics: self.clone(),
            id,
            started: Instant::now(),
        }
    }
}
pub struct SocketGuard {
    metrics: Arc<Observability>,
    id: Uuid,
    started: Instant,
}
impl Drop for SocketGuard {
    fn drop(&mut self) {
        self.metrics.ws_active.fetch_sub(1, Ordering::Relaxed);
        self.metrics.ws_closed.fetch_add(1, Ordering::Relaxed);
        tracing::info!(connection_id=%self.id, duration_ms=self.started.elapsed().as_millis() as u64, "world connection closed");
    }
}
struct HttpGuard(Arc<Observability>);
impl Drop for HttpGuard {
    fn drop(&mut self) {
        self.0.http_active.fetch_sub(1, Ordering::Relaxed);
    }
}
pub(crate) async fn request(
    State(metrics): State<Arc<Observability>>,
    mut request: Request,
    next: Next,
) -> Response {
    let id = Uuid::new_v4(); // Never trust a caller-provided request ID.
    request.extensions_mut().insert(RequestId(id));
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str())
        .unwrap_or("unmatched")
        .to_owned();
    let method = match request.method().as_str() {
        "GET" => "GET",
        "POST" => "POST",
        "HEAD" => "HEAD",
        "OPTIONS" => "OPTIONS",
        _ => "OTHER",
    };
    let label = format!("{method} {route}");
    metrics.http_active.fetch_add(1, Ordering::Relaxed);
    let _guard = HttpGuard(metrics.clone());
    let started = Instant::now();
    // Correlation spans stay enabled when the event filter is raised to error;
    // entering a span does not itself emit a log record.
    let span = tracing::error_span!("http", request_id=%id, method, route);
    async {
        let mut response = next.run(request).await;
        let status = response.status().as_u16();
        let ms = started.elapsed().as_secs_f64() * 1000.0;
        {
            let mut data = metrics.events.lock().expect("observability");
            let metric = data.http.entry(label).or_default();
            metric.requests += 1;
            match status {
                101 => metric.upgrades += 1,
                200..=299 => metric.responses_2xx += 1,
                300..=399 => metric.responses_3xx += 1,
                400..=499 => metric.responses_4xx += 1,
                500..=599 => metric.responses_5xx += 1,
                _ => {}
            }
            metric.latency_sum_ms += ms;
            metric.latency_max_ms = metric.latency_max_ms.max(ms);
            let bucket = LATENCY_BOUNDS_MS
                .iter()
                .position(|limit| ms <= *limit as f64)
                .unwrap_or(10);
            metric.latency_buckets[bucket] += 1;
        }
        if status >= 400 {
            let code = response
                .extensions()
                .get::<ErrorCode>()
                .map(|e| e.0)
                .unwrap_or(if status >= 500 {
                    "HTTP_SERVER_ERROR"
                } else {
                    "HTTP_CLIENT_ERROR"
                });
            metrics.event("http", code, id);
            if status >= 500 {
                tracing::error!(request_id=%id, status, code, duration_ms=ms, "http request failed");
            } else {
                tracing::warn!(request_id=%id, status, code, duration_ms=ms, "http request rejected");
            }
        } else if matches!(
            route.as_str(),
            "/healthz" | "/readyz" | "/api/v1/server-info"
        ) {
            tracing::debug!(status, duration_ms = ms, "http request completed");
        } else {
            tracing::info!(status, duration_ms = ms, "http request completed");
        }
        response.headers_mut().insert(
            "x-request-id",
            HeaderValue::from_str(&id.to_string()).expect("UUID header"),
        );
        response
    }
    .instrument(span)
    .await
}
#[derive(Clone, Copy)]
pub(crate) struct RequestId(pub Uuid);
pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

/// Only a fixed category and (if present) five-character SQLSTATE are logged.
pub(crate) fn database_error(error: &sqlx::Error, operation: &'static str) {
    let kind = match error {
        sqlx::Error::PoolTimedOut => "pool_timeout",
        sqlx::Error::PoolClosed => "pool_closed",
        sqlx::Error::Database(_) => "database",
        sqlx::Error::Io(_) => "io",
        _ => "other",
    };
    let state = error
        .as_database_error()
        .and_then(|e| e.code())
        .filter(|c| {
            c.len() == 5
                && c.bytes()
                    .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit())
        });
    tracing::error!(
        operation,
        kind,
        sqlstate = state.as_deref().unwrap_or("none"),
        "database operation failed"
    );
}
