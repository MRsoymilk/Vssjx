use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};
use uuid::Uuid;
use vssjx_server::config::{AuthConfig, Config, read_env_file};

struct Fixture(PathBuf);
impl Fixture {
    fn new(contents: &str) -> Self {
        let directory = if Path::new("/tmp/opencode").is_dir() {
            PathBuf::from("/tmp/opencode")
        } else {
            std::env::temp_dir()
        };
        let path = directory.join(format!("vssjx-config-{}.env", Uuid::new_v4()));
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        file.write_all(contents.as_bytes()).unwrap();
        Self(path)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

#[test]
fn sample_is_complete_and_safe_without_a_database_password() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let values = read_env_file(&root.join(".env.sample.txt")).unwrap();
    assert!(
        values
            .get("SSJX_POSTGRES_PASSWORD")
            .is_some_and(String::is_empty),
        "Sample must not contain a database password"
    );
    let config = Config::from_values(&values).unwrap();
    assert!(config.database_url.is_none());
    assert_eq!(config.auth, AuthConfig::default());
}

#[test]
fn file_expands_variables_without_mutating_process_environment() {
    let key = format!("VSSJX_FIXTURE_{}", Uuid::new_v4().simple());
    let file = Fixture::new(&format!(
        "{key}=fixture-value-not-a-secret\nSSJX_DATABASE_URL=\"postgresql://user:${{{key}}}@localhost/example\"\n"
    ));
    let values = read_env_file(&file.0).unwrap();
    assert_eq!(
        values["SSJX_DATABASE_URL"],
        "postgresql://user:fixture-value-not-a-secret@localhost/example"
    );
    assert!(std::env::var(&key).is_err());
}

#[test]
fn overrides_and_blank_database_url_are_supported() {
    let mut values = HashMap::from([
        ("SSJX_BIND_ADDR".into(), "127.0.0.1:0".into()),
        ("SSJX_DATABASE_URL".into(), "postgresql://fixture".into()),
        ("SSJX_AUTH_ACCESS_SECONDS".into(), "120".into()),
        ("SSJX_AUTH_REFRESH_SECONDS".into(), "600".into()),
        ("SSJX_AUTH_HASH_WORKERS".into(), "4".into()),
        ("SSJX_DB_MAX_CONNECTIONS".into(), "12".into()),
    ]);
    let config = Config::from_values(&values).unwrap();
    assert_eq!(config.auth.access_seconds, 120);
    assert_eq!(config.auth.refresh_seconds, 600);
    assert_eq!(config.auth.hash_workers, 4);
    assert_eq!(config.auth.db_max_connections, 12);
    values.insert("SSJX_DATABASE_URL".into(), "".into());
    assert!(Config::from_values(&values).unwrap().database_url.is_none());
}

#[test]
fn invalid_limits_and_syntax_fail_without_exposing_values() {
    for (key, value) in [
        ("SSJX_AUTH_HASH_WORKERS", "0"),
        ("SSJX_DB_MAX_CONNECTIONS", "101"),
        ("SSJX_AUTH_ACCESS_SECONDS", "not-a-number"),
    ] {
        assert!(Config::from_values(&HashMap::from([(key.into(), value.into())])).is_err());
    }
    let invalid_order = HashMap::from([
        ("SSJX_AUTH_ACCESS_SECONDS".into(), "3600".into()),
        ("SSJX_AUTH_REFRESH_SECONDS".into(), "300".into()),
    ]);
    assert!(Config::from_values(&invalid_order).is_err());
    let file = Fixture::new("SSJX_POSTGRES_PASSWORD=\"redacted-fixture-marker\n");
    let error = read_env_file(&file.0).unwrap_err();
    assert!(!error.contains("redacted-fixture-marker"));
}
