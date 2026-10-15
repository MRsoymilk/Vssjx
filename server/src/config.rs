use std::{env, net::SocketAddr};

#[derive(Clone, Debug)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub server_name: String,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let bind = env::var("SSJX_BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".into());
        let name = env::var("SSJX_SERVER_NAME").unwrap_or_else(|_| "蜀山剑侠 · 开发服务器".into());
        Self::parse(&bind, &name)
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
        })
    }
}
