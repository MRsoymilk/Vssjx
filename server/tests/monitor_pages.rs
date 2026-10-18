use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use tower::ServiceExt;
use uuid::Uuid;
use vssjx_server::{apps, config::Config, logging::LogHealth};

fn request(path: &str) -> Request<Body> {
    let mut r = Request::builder()
        .uri(path)
        .header("host", "127.0.0.1:9090")
        .body(Body::empty())
        .unwrap();
    r.extensions_mut().insert(ConnectInfo(
        "127.0.0.1:1234".parse::<std::net::SocketAddr>().unwrap(),
    ));
    r
}
#[tokio::test]
async fn pages_are_distinct_deep_linkable_and_keep_the_private_boundary() {
    let (game, monitor) = apps(
        Config::parse("127.0.0.1:0", "test").unwrap(),
        None,
        LogHealth::default(),
    );
    let user = format!("/users/{}", Uuid::new_v4());
    for (path, page, marker) in [
        ("/", "overview", "id=\"cards\""),
        ("/users", "users", "id=\"users-list\""),
        (user.as_str(), "user", "id=\"user-detail\""),
        ("/audit", "audit", "id=\"audit-filter\""),
        ("/chat", "chat", "id=\"chat-admin-list\""),
        (
            "/announcements",
            "announcements",
            "id=\"announcement-form\"",
        ),
    ] {
        assert_eq!(
            game.clone().oneshot(request(path)).await.unwrap().status(),
            StatusCode::NOT_FOUND
        );
        let response = monitor.clone().oneshot(request(path)).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()["cache-control"], "no-store");
        assert!(
            response.headers()["content-security-policy"]
                .to_str()
                .unwrap()
                .contains("frame-ancestors 'none'")
        );
        let body = String::from_utf8(
            response
                .into_body()
                .collect()
                .await
                .unwrap()
                .to_bytes()
                .to_vec(),
        )
        .unwrap();
        assert!(body.contains(&format!("data-page=\"{page}\"")));
        assert!(body.contains(marker));
        assert!(body.contains("aria-label=\"面包屑\""));
        assert!(!body.contains("{{"));
        for (other, fragment) in [
            ("overview", "id=\"cards\""),
            ("users", "id=\"users-list\""),
            ("user", "id=\"user-detail\""),
            ("audit", "id=\"audit-filter\""),
            ("chat", "id=\"chat-admin-list\""),
            ("announcements", "id=\"announcement-form\""),
        ] {
            if other != page {
                assert!(!body.contains(fragment));
            }
        }
        let mut hostile = request(path);
        hostile
            .headers_mut()
            .insert("origin", "https://evil.example".parse().unwrap());
        assert_eq!(
            monitor.clone().oneshot(hostile).await.unwrap().status(),
            StatusCode::FORBIDDEN
        );
    }
    assert_eq!(
        monitor
            .clone()
            .oneshot(request("/users/not-a-uuid"))
            .await
            .unwrap()
            .status(),
        StatusCode::BAD_REQUEST
    );
    for asset in ["/admin.js", "/users.js", "/audit.js", "/announcements.js", "/chat.js"] {
        assert_eq!(
            game.clone().oneshot(request(asset)).await.unwrap().status(),
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            monitor
                .clone()
                .oneshot(request(asset))
                .await
                .unwrap()
                .status(),
            StatusCode::OK
        );
    }
}
