use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::Value;
use tower::ServiceExt;
use vssjx_server::{app, config::Config};

async fn get(path: &str) -> (StatusCode, Value) {
    let config = Config::parse("127.0.0.1:0", "测试服务器").unwrap();
    let response = app(config)
        .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
async fn health_and_readiness_only_claim_connection_stage() {
    for path in ["/healthz", "/readyz"] {
        let (status, value) = get(path).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(value["service"], "vssjx");
        assert_eq!(value["status"], "ok");
        assert_eq!(value["stage"], "connection_only");
    }
}

#[tokio::test]
async fn discovery_identifies_protocol_without_advertising_fake_login() {
    let (status, value) = get("/api/v1/server-info").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(value["protocol_version"], 1);
    assert_eq!(value["server_name"], "测试服务器");
    assert_eq!(value["stage"], "connection_only");
    assert_eq!(value["capabilities"], serde_json::json!([]));
}

#[tokio::test]
async fn unimplemented_login_is_not_a_success_response() {
    let (status, value) = get("/api/v1/login").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(value["code"], "NOT_FOUND");
}

#[tokio::test]
async fn authentication_is_explicitly_unavailable_without_database() {
    let config = Config::parse("127.0.0.1:0", "服务器").unwrap();
    let response = app(config)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"username":"player_one","password":"password-1234"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    assert_eq!(
        serde_json::from_slice::<Value>(&bytes).unwrap()["code"],
        "AUTH_UNAVAILABLE"
    );
}

#[test]
fn configuration_validates_bind_address_and_display_name() {
    assert!(Config::parse("127.0.0.1:8080", "服务器").is_ok());
    assert!(Config::parse("[::1]:8080", "服务器").is_ok());
    assert!(Config::parse("example.com:8080", "服务器").is_err());
    assert!(Config::parse("127.0.0.1:65536", "服务器").is_err());
    assert!(Config::parse("127.0.0.1:8080", "  ").is_err());
    assert!(Config::parse("127.0.0.1:8080", "服务器\n假日志").is_err());
    assert!(Config::parse("127.0.0.1:8080", &"甲".repeat(65)).is_err());
}
