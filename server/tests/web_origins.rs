use axum::http::{HeaderMap, HeaderValue, header::ORIGIN};
use std::collections::HashMap;
use vssjx_server::{config::Config, web_origin::OriginPolicy};

fn headers(value: &str) -> HeaderMap {
    HeaderMap::from_iter([(ORIGIN, HeaderValue::from_str(value).unwrap())])
}

#[test]
fn defaults_retain_native_path_but_deny_all_browser_origins() {
    let policy = OriginPolicy::default();
    assert!(policy.allows(&HeaderMap::new()));
    for value in [
        "https://game.example.com",
        "http://localhost:8060",
        "null",
        "",
    ] {
        assert!(!policy.allows(&headers(value)));
    }
}

#[test]
fn scheme_dns_case_ipv6_and_default_ports_normalize_exactly() {
    let policy = OriginPolicy::from_lists(
        "HTTPS://Game.Example.com:443,https://[2001:db8::1]:9443,https://xn--fiqs8s.example",
        "http://localhost,http://127.0.0.1:8060,https://[::1]",
    )
    .unwrap();
    for value in [
        "https://game.example.com",
        "HTTPS://GAME.EXAMPLE.COM:443",
        "https://game.example.com:00443",
        "https://[2001:0DB8:0:0:0:0:0:1]:9443",
        "https://xn--fiqs8s.example",
        "http://LOCALHOST:80",
        "http://127.0.0.1:8060",
        "https://[0:0:0:0:0:0:0:1]:443",
    ] {
        assert!(policy.allows(&headers(value)), "{value}");
    }
    for value in [
        "http://game.example.com",
        "https://game.example.com:444",
        "https://sub.game.example.com",
        "https://game.example.com.evil",
        "https://game.example.com.",
        "http://localhost:81",
        "http://127.0.0.2:8060",
        "http://[::1]",
    ] {
        assert!(!policy.allows(&headers(value)), "{value}");
    }
}

#[test]
fn non_serialized_origins_credentials_lists_and_aliases_are_rejected() {
    let policy = OriginPolicy::from_lists("https://game.example.com", "http://127.0.0.1").unwrap();
    for value in [
        "null",
        "https://game.example.com/",
        "https://game.example.com/game",
        "https://game.example.com?x=1",
        "https://game.example.com#x",
        "https://user:pass@game.example.com",
        " https://game.example.com",
        "https://game.example.com ",
        "https://game.example.com https://game.example.com",
        "https://game.example.com,https://game.example.com",
        "https:\\game.example.com",
        "http://127.1",
        "http://2130706433",
        "http://0x7f000001",
        "http://127.000.0.1",
        "http://127.0.0.1:",
        "http://127.0.0.1:0",
        "https://*.example.com",
        "https://game%2eexample.com",
        "https://[::1%25lo]:443",
        "https://游戏.example",
    ] {
        assert!(!policy.allows(&headers(value)), "{value}");
    }
    let mut invalid = HeaderMap::new();
    invalid.insert(
        ORIGIN,
        HeaderValue::from_bytes(b"https://\xff.example").unwrap(),
    );
    assert!(!policy.allows(&invalid));
}

#[test]
fn duplicate_headers_and_forwarded_header_spoofs_cannot_open_an_origin() {
    let policy = OriginPolicy::from_lists("https://game.example.com", "").unwrap();
    let mut values = headers("https://game.example.com");
    values.append(ORIGIN, HeaderValue::from_static("https://game.example.com"));
    assert!(!policy.allows(&values));
    let mut values = headers("https://evil.example");
    for key in [
        "host",
        "x-forwarded-host",
        "x-forwarded-origin",
        "x-original-origin",
    ] {
        values.insert(key, HeaderValue::from_static("https://game.example.com"));
    }
    assert!(!policy.allows(&values));
}

#[test]
fn production_and_explicit_loopback_development_lists_are_separate() {
    for value in [
        "http://game.example.com",
        "http://localhost",
        "*",
        "null",
        "https://user:secret@host",
        "https://host/",
        "https://host,",
        "https://host,,https://other",
        "https://host:65536",
        "https://-host",
    ] {
        assert!(OriginPolicy::from_lists(value, "").is_err(), "{value}");
    }
    for value in [
        "http://0.0.0.0:8060",
        "http://192.168.1.2:8060",
        "http://localhost.evil:8060",
        "http://dev.localhost:8060",
        "http://localhost.:8060",
        "http://[::]:8060",
        "https://game.example.com",
    ] {
        assert!(OriginPolicy::from_lists("", value).is_err(), "{value}");
    }
    let policy = OriginPolicy::from_lists("", "http://127.0.0.2:8060,http://[::1]:8060").unwrap();
    assert!(policy.allows(&headers("http://127.0.0.2:8060")));
    assert!(policy.allows(&headers("http://[::1]:8060")));
}

#[test]
fn bounded_configuration_errors_never_echo_url_values() {
    for key in ["SSJX_WEB_ALLOWED_ORIGINS", "SSJX_WEB_DEV_ORIGINS"] {
        let config = Config::from_values(&HashMap::from([(
            key.into(),
            "https://user:private-origin-marker@host".into(),
        )]));
        let error = config.err().unwrap();
        assert!(error.contains(key) && !error.contains("private-origin-marker"));
    }
    let entries = vec!["https://host.example"; 33].join(",");
    assert!(OriginPolicy::from_lists(&entries, "").is_err());
    assert!(OriginPolicy::from_lists(&"x".repeat(8193), "").is_err());
    let policy =
        OriginPolicy::from_lists(" https://HOST.example:443 ,https://host.example ", " ").unwrap();
    assert!(policy.allows(&headers("https://host.example")));
    assert!(!policy.allows(&headers(&format!("https://{}", "x".repeat(2048)))));
}
