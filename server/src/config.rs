use std::{
    collections::HashMap,
    env,
    net::SocketAddr,
    path::{Path, PathBuf},
};

// Deliberately no Debug: database_url may contain a password.
#[derive(Clone)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub server_name: String,
    pub database_url: Option<String>,
    pub log_filter: String,
    pub auth: AuthConfig,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let path = match env::var("SSJX_ENV_FILE") {
            Ok(path) if path.is_empty() => None,
            Ok(path) => Some(PathBuf::from(path)),
            Err(env::VarError::NotPresent) => {
                let local = env::current_dir()
                    .map_err(|_| "Cannot locate .env directory")?
                    .join(".env");
                let repository = Path::new(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .ok_or("Cannot locate repository")?
                    .join(".env");
                if local.is_file() {
                    Some(local)
                } else if repository.is_file() {
                    Some(repository)
                } else {
                    None
                }
            }
            Err(_) => return Err("Invalid SSJX_ENV_FILE".into()),
        };
        let mut values = if let Some(path) = path {
            read_env_file(&path)?
        } else {
            HashMap::new()
        };
        for (key, value) in env::vars_os() {
            let Some(key) = key.to_str() else { continue };
            if key.starts_with("SSJX_") || key == "RUST_LOG" {
                let value = value
                    .into_string()
                    .map_err(|_| format!("Invalid environment value for {key}"))?;
                values.insert(key.to_owned(), value);
            }
        }
        Self::from_values(&values)
    }

    pub fn from_values(values: &HashMap<String, String>) -> Result<Self, String> {
        let mut config = Self::parse(
            values
                .get("SSJX_BIND_ADDR")
                .map(String::as_str)
                .unwrap_or("127.0.0.1:8080"),
            values
                .get("SSJX_SERVER_NAME")
                .map(String::as_str)
                .unwrap_or("蜀山剑侠 · 开发服务器"),
        )?;
        config.database_url = values
            .get("SSJX_DATABASE_URL")
            .filter(|v| !v.trim().is_empty())
            .cloned();
        config.log_filter = values
            .get("RUST_LOG")
            .cloned()
            .unwrap_or_else(|| "info".into());
        if tracing_subscriber::EnvFilter::try_new(&config.log_filter).is_err() {
            return Err("Invalid RUST_LOG filter".into());
        }
        config.auth = AuthConfig::from_values(values)?;
        Ok(config)
    }

    pub fn parse(bind: &str, name: &str) -> Result<Self, String> {
        let bind_addr = bind
            .parse::<SocketAddr>()
            .map_err(|_| "SSJX_BIND_ADDR must be an IP:port or [IPv6]:port".to_string())?;
        let server_name = name.trim();
        if server_name.is_empty()
            || server_name.chars().count() > 64
            || server_name.chars().any(char::is_control)
        {
            return Err("SSJX_SERVER_NAME must contain 1..64 characters without controls".into());
        }
        Ok(Self {
            bind_addr,
            server_name: server_name.into(),
            database_url: None,
            log_filter: "info".into(),
            auth: AuthConfig::default(),
        })
    }
}

pub fn read_env_file(path: &Path) -> Result<HashMap<String, String>, String> {
    let entries = dotenvy::from_path_iter(path).map_err(|_| "Cannot read configured .env file")?;
    let mut values = HashMap::new();
    for entry in entries {
        // dotenv parser errors may contain the original secret-bearing line.
        let (key, value) = entry
            .map_err(|_| "Invalid .env syntax; check configuration without logging secrets")?;
        values.insert(key, value);
    }
    Ok(values)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AuthConfig {
    pub access_seconds: i32,
    pub refresh_seconds: i32,
    pub max_sessions: u32,
    pub hash_workers: u32,
    pub rate_window_seconds: u32,
    pub rate_global: u32,
    pub rate_ip: u32,
    pub rate_account: u32,
    pub rate_max_keys: u32,
    pub db_max_connections: u32,
    pub db_acquire_timeout_seconds: u32,
    pub db_statement_timeout_seconds: u32,
    pub db_idle_transaction_timeout_seconds: u32,
    pub db_ready_timeout_seconds: u32,
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            access_seconds: 900,
            refresh_seconds: 604800,
            max_sessions: 8,
            hash_workers: 2,
            rate_window_seconds: 60,
            rate_global: 600,
            rate_ip: 60,
            rate_account: 10,
            rate_max_keys: 8192,
            db_max_connections: 10,
            db_acquire_timeout_seconds: 3,
            db_statement_timeout_seconds: 3,
            db_idle_transaction_timeout_seconds: 5,
            db_ready_timeout_seconds: 1,
        }
    }
}

impl AuthConfig {
    fn from_values(values: &HashMap<String, String>) -> Result<Self, String> {
        let config = Self {
            access_seconds: number(values, "SSJX_AUTH_ACCESS_SECONDS", 900, 60, 86400)? as i32,
            refresh_seconds: number(values, "SSJX_AUTH_REFRESH_SECONDS", 604800, 300, 2592000)?
                as i32,
            max_sessions: number(values, "SSJX_AUTH_MAX_SESSIONS", 8, 1, 128)?,
            hash_workers: number(values, "SSJX_AUTH_HASH_WORKERS", 2, 1, 16)?,
            rate_window_seconds: number(values, "SSJX_AUTH_RATE_WINDOW_SECONDS", 60, 1, 3600)?,
            rate_global: number(values, "SSJX_AUTH_RATE_GLOBAL", 600, 1, 100000)?,
            rate_ip: number(values, "SSJX_AUTH_RATE_IP", 60, 1, 10000)?,
            rate_account: number(values, "SSJX_AUTH_RATE_ACCOUNT", 10, 1, 1000)?,
            rate_max_keys: number(values, "SSJX_AUTH_RATE_MAX_KEYS", 8192, 16, 1000000)?,
            db_max_connections: number(values, "SSJX_DB_MAX_CONNECTIONS", 10, 1, 100)?,
            db_acquire_timeout_seconds: number(
                values,
                "SSJX_DB_ACQUIRE_TIMEOUT_SECONDS",
                3,
                1,
                60,
            )?,
            db_statement_timeout_seconds: number(
                values,
                "SSJX_DB_STATEMENT_TIMEOUT_SECONDS",
                3,
                1,
                60,
            )?,
            db_idle_transaction_timeout_seconds: number(
                values,
                "SSJX_DB_IDLE_TRANSACTION_TIMEOUT_SECONDS",
                5,
                1,
                300,
            )?,
            db_ready_timeout_seconds: number(values, "SSJX_DB_READY_TIMEOUT_SECONDS", 1, 1, 30)?,
        };
        if config.refresh_seconds < config.access_seconds {
            return Err("Refresh lifetime must not be shorter than access lifetime".into());
        }
        Ok(config)
    }
}

fn number(
    values: &HashMap<String, String>,
    key: &str,
    default: u32,
    minimum: u32,
    maximum: u32,
) -> Result<u32, String> {
    let Some(raw) = values.get(key) else {
        return Ok(default);
    };
    let parsed = raw
        .parse::<u32>()
        .map_err(|_| format!("{key} must be an integer in {minimum}..={maximum}"))?;
    if !(minimum..=maximum).contains(&parsed) {
        return Err(format!("{key} must be in {minimum}..={maximum}"));
    }
    Ok(parsed)
}
