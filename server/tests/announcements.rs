use axum::{
    Router,
    body::Body,
    extract::ConnectInfo,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::{Value, json};
use std::{
    net::SocketAddr,
    time::{Duration, Instant},
};
use tower::ServiceExt;
use uuid::Uuid;
use vssjx_server::{
    announcements::{AnnouncementDraft, Announcements},
    apps,
    config::Config,
    logging::LogHealth,
};

fn draft(text: &str) -> AnnouncementDraft {
    AnnouncementDraft {
        request_id: Uuid::new_v4(),
        text: text.into(),
        duration_seconds: 60,
    }
}
#[test]
fn broadcast_late_join_replacement_cancel_and_expiry_share_one_revision() {
    let hub = Announcements::default();
    let now = Instant::now();
    let (initial, empty) = hub.packet_since(None, now).unwrap();
    assert!(empty["notice"].is_null());
    let first = draft("维护通知\n今晚 22:00");
    let packet = hub.publish(first.clone(), now).unwrap();
    assert_eq!(packet["notice"]["text"], "维护通知 今晚 22:00");
    let a = hub.packet_since(Some(initial), now).unwrap();
    let b = hub.packet_since(Some(initial), now).unwrap();
    assert_eq!(a, b);
    assert_eq!(a.1, packet);
    assert!(hub.packet_since(Some(a.0), now).is_none());
    assert_eq!(hub.packet_since(None, now).unwrap().1, packet); // late join
    let replay = hub
        .publish(first.clone(), now + Duration::from_secs(5))
        .unwrap();
    assert_eq!(replay["revision"], packet["revision"]);
    assert_eq!(replay["notice"]["remaining_ms"], 55000); // retry does not extend expiry
    let second = draft("新通知[微笑] <b>原文</b>");
    let replacement = hub.publish(second.clone(), now).unwrap();
    assert_ne!(replacement["revision"], packet["revision"]);
    assert_eq!(
        hub.cancel(first.request_id, now).unwrap_err(),
        "ANNOUNCEMENT_REPLACED"
    );
    let cleared = hub.cancel(second.request_id, now).unwrap();
    assert!(cleared["notice"].is_null());
    assert_eq!(
        hub.publish(second, now).unwrap_err(),
        "ANNOUNCEMENT_SUPERSEDED"
    );
    assert_eq!(
        hub.publish(first, now).unwrap_err(),
        "ANNOUNCEMENT_SUPERSEDED"
    );
    let third = hub.publish(draft("限时通知"), now).unwrap();
    let revision = third["revision"].as_str().unwrap().parse().unwrap();
    let expired = hub
        .packet_since(Some(revision), now + Duration::from_secs(60))
        .unwrap();
    assert!(expired.1["notice"].is_null());
    assert!(
        hub.packet_since(None, now + Duration::from_secs(61))
            .unwrap()
            .1["notice"]
            .is_null()
    );
}
#[test]
fn input_is_bounded_and_same_request_cannot_change_content() {
    let hub = Announcements::default();
    let now = Instant::now();
    for text in [
        "".into(),
        " \n\t ".into(),
        "长".repeat(241),
        "隐藏\u{202e}".into(),
        "控制\0".into(),
    ] {
        assert!(hub.publish(draft(&text), now).is_err());
    }
    for seconds in [0, 9, 86401, u64::MAX] {
        let mut item = draft("消息");
        item.duration_seconds = seconds;
        assert!(hub.publish(item, now).is_err());
    }
    let mut item = draft(&"字".repeat(240));
    assert!(hub.publish(item.clone(), now).is_ok());
    item.text = "改内容".into();
    assert_eq!(
        hub.publish(item, now).unwrap_err(),
        "ANNOUNCEMENT_ID_CONFLICT"
    );
}
fn request(method: &str, path: &str, token: Option<&str>, body: Value) -> Request<Body> {
    let mut builder = Request::builder()
        .method(method)
        .uri(path)
        .header("host", "127.0.0.1:9090")
        .header("content-type", "application/json");
    if let Some(token) = token {
        builder = builder.header("x-announcement-token", token);
    }
    let mut request = builder
        .body(if method == "GET" {
            Body::empty()
        } else {
            Body::from(body.to_string())
        })
        .unwrap();
    request.extensions_mut().insert(ConnectInfo(
        "127.0.0.1:34567".parse::<SocketAddr>().unwrap(),
    ));
    request
}
async fn response(router: &Router, request: Request<Body>, expected: StatusCode) -> Value {
    let response = router.clone().oneshot(request).await.unwrap();
    assert_eq!(response.status(), expected);
    assert_eq!(response.headers()["cache-control"], "no-store");
    let raw = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&raw).unwrap_or(Value::Null)
}
#[tokio::test]
async fn operator_api_is_private_token_guarded_and_accepts_real_same_origin_posts() {
    let (game, monitor) = apps(
        Config::parse("127.0.0.1:0", "test").unwrap(),
        None,
        LogHealth::default(),
    );
    let data = response(
        &monitor,
        request("GET", "/api/announcements", None, Value::Null),
        StatusCode::OK,
    )
    .await;
    let token = data["csrf_token"].as_str().unwrap();
    let id = Uuid::new_v4();
    let body = json!({"request_id":id,"text":"维护 <script>原文</script>","duration_seconds":600});
    response(
        &game,
        request("POST", "/api/announcements", Some(token), body.clone()),
        StatusCode::NOT_FOUND,
    )
    .await;
    response(
        &monitor,
        request("POST", "/api/announcements", None, body.clone()),
        StatusCode::FORBIDDEN,
    )
    .await;
    response(
        &monitor,
        request("POST", "/api/announcements", Some("wrong"), body.clone()),
        StatusCode::FORBIDDEN,
    )
    .await;
    let mut attack = request("POST", "/api/announcements", Some(token), body.clone());
    attack
        .headers_mut()
        .insert("origin", "http://evil.example".parse().unwrap());
    response(&monitor, attack, StatusCode::FORBIDDEN).await;
    let mut legitimate = request("POST", "/api/announcements", Some(token), body);
    legitimate
        .headers_mut()
        .insert("origin", "http://127.0.0.1:9090".parse().unwrap());
    legitimate
        .headers_mut()
        .insert("sec-fetch-site", "same-origin".parse().unwrap());
    let published = response(&monitor, legitimate, StatusCode::OK).await;
    assert_eq!(published["notice"]["id"], id.to_string());
    assert_eq!(published["notice"]["text"], "维护 <script>原文</script>");
    let mut spoof = request(
        "POST",
        "/api/announcements",
        Some(token),
        json!({"request_id":Uuid::new_v4(),"text":"消息","duration_seconds":600,"admin":true}),
    );
    spoof
        .headers_mut()
        .insert("origin", "http://127.0.0.1:9090".parse().unwrap());
    response(&monitor, spoof, StatusCode::BAD_REQUEST).await;
    let mut remote = request(
        "DELETE",
        "/api/announcements",
        Some(token),
        json!({"id":id}),
    );
    remote
        .extensions_mut()
        .insert(ConnectInfo("192.0.2.1:1234".parse::<SocketAddr>().unwrap()));
    response(&monitor, remote, StatusCode::FORBIDDEN).await;
    let cleared = response(
        &monitor,
        request(
            "DELETE",
            "/api/announcements",
            Some(token),
            json!({"id":id}),
        ),
        StatusCode::OK,
    )
    .await;
    assert!(cleared["notice"].is_null());
}
