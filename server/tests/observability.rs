use axum::{
    Router,
    body::Body,
    extract::ConnectInfo,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::Value;
use std::{
    collections::HashMap,
    sync::{Arc, atomic::Ordering},
};
use tower::ServiceExt;
use uuid::Uuid;
use vssjx_server::{apps, config::Config, logging::LogHealth, observability::Observability};

fn routers() -> (Router, Router) {
    apps(
        Config::parse("127.0.0.1:0", "test").unwrap(),
        None,
        LogHealth::default(),
    )
}
fn local(path: &str) -> Request<Body> {
    let mut request = Request::builder()
        .uri(path)
        .header("host", "127.0.0.1:9090")
        .body(Body::empty())
        .unwrap();
    request.extensions_mut().insert(ConnectInfo(
        "127.0.0.1:20000".parse::<std::net::SocketAddr>().unwrap(),
    ));
    request
}
async fn json(router: Router, request: Request<Body>) -> Value {
    let response = router.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers()["cache-control"], "no-store");
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

#[tokio::test]
async fn monitoring_is_separate_read_only_and_requires_local_peer_and_host() {
    let (game, monitor) = routers();
    assert_eq!(
        game.oneshot(local("/api/status")).await.unwrap().status(),
        StatusCode::NOT_FOUND
    );
    for path in ["/", "/dashboard.js", "/dashboard.css", "/api/status"] {
        let response = monitor.clone().oneshot(local(path)).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert!(
            response.headers()["content-security-policy"]
                .to_str()
                .unwrap()
                .contains("frame-ancestors 'none'")
        );
        assert!(
            !response
                .headers()
                .contains_key("access-control-allow-origin")
        );
    }
    for case in 0..7 {
        let mut request = local("/api/status");
        match case {
            0 => {
                request
                    .extensions_mut()
                    .remove::<ConnectInfo<std::net::SocketAddr>>();
            }
            1 => {
                request.extensions_mut().insert(ConnectInfo(
                    "192.0.2.1:1234".parse::<std::net::SocketAddr>().unwrap(),
                ));
            }
            2 => {
                request
                    .headers_mut()
                    .insert("host", "evil.example:9090".parse().unwrap());
            }
            3 => {
                request
                    .headers_mut()
                    .insert("origin", "http://evil.example".parse().unwrap());
            }
            4 => {
                request
                    .headers_mut()
                    .insert("sec-fetch-site", "cross-site".parse().unwrap());
            }
            5 => {
                request.headers_mut().remove("host");
            }
            _ => {
                request
                    .headers_mut()
                    .insert("sec-fetch-site", "same-site".parse().unwrap());
            }
        }
        assert_eq!(
            monitor.clone().oneshot(request).await.unwrap().status(),
            StatusCode::FORBIDDEN
        );
    }
    let mut post = local("/api/status");
    *post.method_mut() = axum::http::Method::POST;
    assert_eq!(
        monitor.oneshot(post).await.unwrap().status(),
        StatusCode::METHOD_NOT_ALLOWED
    );
}

#[tokio::test]
async fn labels_are_bounded_and_caller_ids_paths_queries_and_bodies_are_not_retained() {
    let (game, monitor) = routers();
    for _ in 0..120 {
        let raw = format!("/secret-path-{}?access_token=secret-query", Uuid::new_v4());
        let request = Request::builder()
            .uri(raw)
            .header("x-request-id", "secret-request-id")
            .body(Body::empty())
            .unwrap();
        let response = game.clone().oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert!(Uuid::parse_str(response.headers()["x-request-id"].to_str().unwrap()).is_ok());
    }
    let response = game
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/login")
                .header("content-type", "application/json")
                .header("authorization", "Bearer secret-authorization")
                .body(Body::from(
                    r#"{"username":"secret-user","password":"secret-password"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let request_id = response.headers()["x-request-id"]
        .to_str()
        .unwrap()
        .to_owned();
    let data = json(monitor, local("/api/status")).await;
    assert!(!data.to_string().contains("secret-"));
    assert_eq!(data["recent_events"].as_array().unwrap().len(), 100);
    assert_eq!(
        data["recent_events"].as_array().unwrap().last().unwrap()["correlation_id"],
        request_id
    );
    assert_eq!(data["errors"]["AUTH_UNAVAILABLE"], 1);
    assert_eq!(data["http"]["routes"].as_object().unwrap().len(), 2);
    let metric = &data["http"]["routes"]["GET unmatched"];
    assert_eq!(metric["requests"], 120);
    assert_eq!(
        metric["latency_buckets"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_u64().unwrap())
            .sum::<u64>(),
        120
    );
    assert_eq!(data["http"]["in_flight"], 0);
    assert_eq!(data["database"]["status"], "not_configured");
    assert!(data["world"].is_null());
}

#[tokio::test]
async fn receipt_uuid_paths_use_the_fixed_route_template_and_ipv6_monitor_is_local() {
    let (game, monitor) = routers();
    for _ in 0..10 {
        let path = format!("/api/v1/character-operations/{}", Uuid::new_v4());
        assert_eq!(
            game.clone().oneshot(local(&path)).await.unwrap().status(),
            StatusCode::SERVICE_UNAVAILABLE
        );
    }
    let mut request = local("/api/status");
    request
        .headers_mut()
        .insert("host", "[::1]:9090".parse().unwrap());
    request.extensions_mut().insert(ConnectInfo(
        "[::1]:1234".parse::<std::net::SocketAddr>().unwrap(),
    ));
    let data = json(monitor, request).await;
    let routes = data["http"]["routes"].as_object().unwrap();
    assert_eq!(routes.len(), 1);
    assert_eq!(
        routes["GET /api/v1/character-operations/{operation_id}"]["requests"],
        10
    );
}

#[test]
fn counters_guards_and_tick_statistics_are_consistent() {
    let metrics = Arc::new(Observability::default());
    {
        let _socket = metrics.socket(Uuid::new_v4());
        assert_eq!(metrics.ws_active.load(Ordering::Relaxed), 1);
    }
    metrics.record_tick(100000, 2000, 70);
    metrics.record_tick(200000, 3000, 96);
    let data = metrics.snapshot();
    assert_eq!(data["websocket"]["active"], 0);
    assert_eq!(data["websocket"]["opened"], 1);
    assert_eq!(data["websocket"]["closed"], 1);
    assert_eq!(data["tick"]["late_intervals"], 1);
    assert_eq!(data["tick"]["max_work_ms"], 3.0);
    assert_eq!(data["tick"]["shared_publication_bytes"], 166);
}

#[test]
fn monitor_configuration_defaults_and_safety_boundaries() {
    let default = Config::from_values(&HashMap::new()).unwrap();
    assert!(default.monitoring.bind_addr.unwrap().ip().is_loopback());
    for value in [
        "0.0.0.0:9090",
        "[::]:9090",
        "192.168.1.2:9090",
        "evil-secret.example:9090",
    ] {
        let error = Config::from_values(&HashMap::from([(
            "SSJX_MONITOR_BIND_ADDR".into(),
            value.into(),
        )]))
        .err()
        .unwrap();
        assert!(!error.contains(value));
    }
    for (key, value) in [("SSJX_LOG_FILE_MIB", "0"), ("SSJX_LOG_FILES", "101")] {
        assert!(Config::from_values(&HashMap::from([(key.into(), value.into())])).is_err());
    }
    let config = Config::from_values(&HashMap::from([
        ("SSJX_MONITOR_BIND_ADDR".into(), "".into()),
        ("SSJX_LOG_DIR".into(), "".into()),
    ]))
    .unwrap();
    assert!(config.monitoring.bind_addr.is_none());
    assert!(config.monitoring.log_dir.is_none());
}
