//! Ephemeral public channel: bounded history/receipts and one queued message per
//! character. FIFO among characters prevents one sender monopolizing the drain.
use serde::Serialize;
use std::{
    collections::{HashMap, VecDeque},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use uuid::Uuid;

pub const MAX_CHARS: usize = 120;
pub const MAX_BYTES: usize = 480;
#[derive(Clone, Copy)]
pub struct ChatConfig {
    pub history: usize,
    pub dedup_seconds: u64,
    pub max_receipts: usize,
    pub max_pending: usize,
    pub personal_burst: u32,
    pub personal_seconds: u64,
    pub global_per_second: u32,
}
impl Default for ChatConfig {
    fn default() -> Self {
        Self {
            history: 50,
            dedup_seconds: 300,
            max_receipts: 4096,
            max_pending: 256,
            personal_burst: 3,
            personal_seconds: 5,
            global_per_second: 20,
        }
    }
}
pub fn text(raw: &str) -> Result<String, &'static str> {
    if raw.len()>MAX_BYTES || raw.chars().count()>MAX_CHARS || raw.chars().any(|c| c.is_control() || matches!(c, '\u{200b}'..='\u{200f}'|'\u{2028}'..='\u{202e}'|'\u{2060}'..='\u{206f}'|'\u{feff}')) {
        return Err("CHAT_INVALID_TEXT");
    }
    let value = raw.trim_matches(' ');
    if value.is_empty() || value.chars().all(char::is_whitespace) {
        return Err("CHAT_INVALID_TEXT");
    }
    Ok(value.to_owned())
}
#[derive(Clone, Serialize)]
pub struct ChatMessage {
    pub seq: String,
    pub message_id: Uuid,
    pub sender_character_id: Uuid,
    pub display_name: String,
    pub server_time_ms: String,
    pub channel: &'static str,
    pub text: String,
}
#[derive(Clone, Serialize)]
pub struct ChatResult {
    pub client_message_id: Uuid,
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<&'static str>,
}
impl ChatResult {
    pub fn rejected(id: Uuid, code: &'static str) -> Self {
        Self {
            client_message_id: id,
            status: "REJECTED",
            message_id: None,
            code: Some(code),
        }
    }
}
struct Receipt {
    text: String,
    result: ChatResult,
    at: Instant,
}
struct Pending {
    character: Uuid,
    client: Uuid,
    name: String,
    text: String,
}
struct Rate {
    tokens: f64,
    at: Instant,
}
pub struct ChatHub {
    pub epoch: Uuid,
    config: ChatConfig,
    seq: u64,
    history: VecDeque<ChatMessage>,
    receipts: HashMap<(Uuid, Uuid), Receipt>,
    rates: HashMap<Uuid, Rate>,
    pending: VecDeque<Pending>,
    budget: f64,
    last_drain: Instant,
}
impl ChatHub {
    pub(crate) fn monitor_snapshot(&self) -> serde_json::Value {
        serde_json::json!({"pending":self.pending.len(),"history":self.history.len(),"receipts":self.receipts.len()})
    }
    pub fn new(config: ChatConfig) -> Self {
        Self {
            epoch: Uuid::new_v4(),
            config,
            seq: 0,
            history: VecDeque::new(),
            receipts: HashMap::new(),
            rates: HashMap::new(),
            pending: VecDeque::new(),
            budget: 0.0,
            last_drain: Instant::now(),
        }
    }
    pub fn ready(&self) -> serde_json::Value {
        self.ready_since(self.oldest() - 1).0
    }
    pub fn latest(&self) -> u64 {
        self.seq
    }
    /// The readable window begins at this character's admission, bounded by
    /// retained history. Capture admission separately so messages published
    /// during world synchronization are still delivered.
    pub fn ready_since(&self, admitted_after: u64) -> (serde_json::Value, u64) {
        let cursor = admitted_after.max(self.oldest() - 1).min(self.seq);
        let ready = serde_json::json!({"type":"chat.ready","channel_epoch":self.epoch,"latest_seq":self.seq.to_string(),"oldest_seq":(cursor+1).to_string(),"history_limit":self.config.history,"dedup_seconds":self.config.dedup_seconds,"max_chars":MAX_CHARS,"max_bytes":MAX_BYTES});
        (ready, cursor)
    }
    fn prune(&mut self, now: Instant) {
        let ttl = Duration::from_secs(self.config.dedup_seconds);
        self.receipts
            .retain(|_, r| r.result.status == "QUEUED" || now.duration_since(r.at) < ttl);
        self.rates.retain(|_, r| now.duration_since(r.at) < ttl);
    }
    pub fn submit(
        &mut self,
        sender: (Uuid, &str),
        client: Uuid,
        channel: &str,
        raw: &str,
        muted: bool,
        now: Instant,
    ) -> ChatResult {
        let (character, name) = sender;
        self.prune(now);
        if client.get_version_num() != 4 {
            return ChatResult::rejected(client, "CHAT_INVALID_ID");
        }
        if channel != "public" {
            return ChatResult::rejected(client, "CHAT_INVALID_CHANNEL");
        }
        let text = match text(raw) {
            Ok(v) => v,
            Err(code) => return ChatResult::rejected(client, code),
        };
        if let Some(receipt) = self.receipts.get(&(character, client)) {
            return if receipt.text == text {
                receipt.result.clone()
            } else {
                ChatResult::rejected(client, "CHAT_ID_CONFLICT")
            };
        }
        if muted {
            return ChatResult::rejected(client, "CHAT_MUTED");
        }
        if self.pending.iter().any(|p| p.character == character) {
            return ChatResult::rejected(client, "CHAT_PENDING");
        }
        if self.pending.len() >= self.config.max_pending
            || self.receipts.len() >= self.config.max_receipts
            || (!self.rates.contains_key(&character)
                && self.rates.len() >= self.config.max_receipts)
        {
            return ChatResult::rejected(client, "CHAT_BUSY");
        }
        let rate = self.rates.entry(character).or_insert(Rate {
            tokens: self.config.personal_burst as f64,
            at: now,
        });
        rate.tokens = (rate.tokens
            + now.duration_since(rate.at).as_secs_f64() * self.config.personal_burst as f64
                / self.config.personal_seconds as f64)
            .min(self.config.personal_burst as f64);
        rate.at = now;
        if rate.tokens < 1.0 {
            return ChatResult::rejected(client, "CHAT_RATE_LIMITED");
        }
        rate.tokens -= 1.0;
        let result = ChatResult {
            client_message_id: client,
            status: "QUEUED",
            message_id: None,
            code: None,
        };
        self.receipts.insert(
            (character, client),
            Receipt {
                text: text.clone(),
                result: result.clone(),
                at: now,
            },
        );
        self.pending.push_back(Pending {
            character,
            client,
            name: name.to_owned(),
            text,
        });
        result
    }
    pub fn drain(&mut self, now: Instant) {
        // No accumulated idle-time burst: at most one second of total budget.
        self.budget = (self.budget
            + now.duration_since(self.last_drain).as_secs_f64()
                * self.config.global_per_second as f64)
            .min(self.config.global_per_second as f64);
        self.last_drain = now;
        while self.budget >= 1.0 && !self.pending.is_empty() {
            self.budget -= 1.0;
            let pending = self.pending.pop_front().expect("pending message");
            self.seq += 1;
            let id = Uuid::new_v4();
            self.history.push_back(ChatMessage {
                seq: self.seq.to_string(),
                message_id: id,
                sender_character_id: pending.character,
                display_name: pending.name,
                server_time_ms: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis()
                    .to_string(),
                channel: "public",
                text: pending.text,
            });
            while self.history.len() > self.config.history {
                self.history.pop_front();
            }
            let receipt = self
                .receipts
                .get_mut(&(pending.character, pending.client))
                .expect("queued receipt");
            receipt.at = now;
            receipt.result.status = "SENT";
            receipt.result.message_id = Some(id);
        }
        self.prune(now);
    }
    pub fn result(&self, character: Uuid, client: Uuid) -> Option<ChatResult> {
        self.receipts
            .get(&(character, client))
            .map(|r| r.result.clone())
    }
    pub fn oldest(&self) -> u64 {
        self.seq + 1 - self.history.len() as u64
    }
    pub fn batch(&self, after: u64) -> Vec<ChatMessage> {
        self.history
            .iter()
            .filter(|m| m.seq.parse::<u64>().expect("chat sequence") > after)
            .take(16)
            .cloned()
            .collect()
    }
}
