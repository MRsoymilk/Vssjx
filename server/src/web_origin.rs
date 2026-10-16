//! Strict serialized HTTP(S) origins, not general URLs and never identity proof.
use axum::http::{HeaderMap, header::ORIGIN};
use std::{
    collections::HashSet,
    net::{IpAddr, Ipv4Addr, Ipv6Addr},
};

const MAX_LIST_BYTES: usize = 8192;
const MAX_ENTRIES: usize = 32;
const MAX_ORIGIN_BYTES: usize = 2048;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct Origin {
    scheme: &'static str,
    host: String,
    port: u16,
}

impl Origin {
    fn parse(raw: &str) -> Option<Self> {
        if raw.len() > MAX_ORIGIN_BYTES || raw.bytes().any(|b| b <= 32 || b >= 127) {
            return None;
        }
        let (scheme, authority) = raw.split_once("://")?;
        let scheme = match scheme.to_ascii_lowercase().as_str() {
            "http" => "http",
            "https" => "https",
            _ => return None,
        };
        if authority.is_empty() || authority.contains(['/', '?', '#', '@', '\\', '%', ',', '*']) {
            return None;
        }
        let (host, port) = if let Some(ipv6) = authority.strip_prefix('[') {
            let (host, suffix) = ipv6.split_once(']')?;
            let host = host.parse::<Ipv6Addr>().ok()?.to_string();
            let port = if suffix.is_empty() {
                None
            } else {
                Some(suffix.strip_prefix(':')?)
            };
            (host, port)
        } else {
            let mut parts = authority.split(':');
            let host = parts.next()?;
            let port = parts.next();
            if parts.next().is_some() {
                return None;
            }
            let host = if let Ok(ip) = host.parse::<Ipv4Addr>() {
                ip.to_string()
            } else {
                let host = host.to_ascii_lowercase();
                let labels = host.strip_suffix('.').unwrap_or(&host);
                if host.len() > 253
                    || labels.split('.').any(|label| {
                        label.is_empty()
                            || label.len() > 63
                            || label.starts_with('-')
                            || label.ends_with('-')
                            || !label
                                .bytes()
                                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
                    })
                {
                    return None;
                }
                // Browsers serialize IPv4 as dotted decimal, not shorthand,
                // octal or hexadecimal numeric-host URL aliases.
                let last = labels.rsplit('.').next()?;
                if last.bytes().all(|b| b.is_ascii_digit())
                    || last
                        .strip_prefix("0x")
                        .is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_hexdigit()))
                {
                    return None;
                }
                host
            };
            (host, port)
        };
        let port = match port {
            None => {
                if scheme == "https" {
                    443
                } else {
                    80
                }
            }
            Some(raw)
                if !raw.is_empty() && raw.len() <= 5 && raw.bytes().all(|b| b.is_ascii_digit()) =>
            {
                let value = raw.parse::<u16>().ok()?;
                if value == 0 {
                    return None;
                }
                value
            }
            Some(_) => return None,
        };
        Some(Self { scheme, host, port })
    }

    fn loopback(&self) -> bool {
        self.host == "localhost" || self.host.parse::<IpAddr>().is_ok_and(|ip| ip.is_loopback())
    }
}

#[derive(Clone, Debug, Default)]
pub struct OriginPolicy {
    production: HashSet<Origin>,
    development: HashSet<Origin>,
}

impl OriginPolicy {
    /// Empty lists preserve native-only behavior. Invalid config fails closed;
    /// errors name the setting but never echo potentially credential-bearing URLs.
    pub fn from_lists(production: &str, development: &str) -> Result<Self, String> {
        Ok(Self {
            production: Self::parse_list(production, "SSJX_WEB_ALLOWED_ORIGINS", false)?,
            development: Self::parse_list(development, "SSJX_WEB_DEV_ORIGINS", true)?,
        })
    }

    fn parse_list(raw: &str, key: &str, development: bool) -> Result<HashSet<Origin>, String> {
        let invalid = || {
            format!(
                "Invalid {key}: use at most 32 comma-separated origins without paths or credentials; production requires HTTPS, development requires loopback"
            )
        };
        if raw.len() > MAX_LIST_BYTES {
            return Err(invalid());
        }
        if raw.trim().is_empty() {
            return Ok(HashSet::new());
        }
        let mut result = HashSet::new();
        for (index, value) in raw.split(',').enumerate() {
            if index >= MAX_ENTRIES {
                return Err(invalid());
            }
            let origin = Origin::parse(value.trim()).ok_or_else(invalid)?;
            if (development && !origin.loopback()) || (!development && origin.scheme != "https") {
                return Err(invalid());
            }
            result.insert(origin);
        }
        Ok(result)
    }

    /// Missing Origin is the existing native path, still requiring auth.exchange.
    /// Every present header must be a single, exact, explicitly allowed origin.
    pub fn allows(&self, headers: &HeaderMap) -> bool {
        let mut values = headers.get_all(ORIGIN).iter();
        let Some(value) = values.next() else {
            return true;
        };
        if values.next().is_some() {
            return false;
        }
        let Some(origin) = value.to_str().ok().and_then(Origin::parse) else {
            return false;
        };
        self.production.contains(&origin) || self.development.contains(&origin)
    }
}
