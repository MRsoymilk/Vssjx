//! One immutable, encoded publication per 100ms world tick, shared by sockets.
//! Initial JSON snapshots establish a baseline; bounded ordered binary deltas
//! include lifecycle events, so a lagging reader must resynchronize, never skip.
use crate::world::Entity;
use axum::body::Bytes;
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};
use tokio::sync::broadcast;
use uuid::Uuid;

pub const SYNC_VERSION: u32 = 2;
pub const HEADER: usize = 36;
pub const MOTION_BYTES: usize = 26;
pub const MAX_PACKET: usize = 1048576;
const RETAINED_TICKS: usize = 32;

pub struct Publication {
    pub epoch: Uuid,
    pub seq: u64,
    pub source_revision: u64,
    pub entities: Vec<Entity>,
    pub delta: Bytes,
    chunks: OnceLock<Vec<String>>,
}
impl Publication {
    pub fn snapshot_chunks(&self) -> &[String] {
        self.chunks.get_or_init(|| {
            self.entities
                .chunks(32)
                .map(|records| serde_json::to_string(records).expect("public entities"))
                .collect()
        })
    }
}
struct Published {
    current: Arc<Publication>,
    sender: broadcast::Sender<Arc<Publication>>,
}
pub struct Publisher {
    inner: Mutex<Published>,
}
impl Default for Publisher {
    fn default() -> Self {
        let epoch = Uuid::new_v4();
        let (sender, _) = broadcast::channel(RETAINED_TICKS);
        Self {
            inner: Mutex::new(Published {
                current: Arc::new(Publication {
                    epoch,
                    seq: 0,
                    source_revision: 0,
                    entities: Vec::new(),
                    delta: Bytes::new(),
                    chunks: OnceLock::new(),
                }),
                sender,
            }),
        }
    }
}
impl Publisher {
    /// Called by the sole world tick task, NOT by connection handlers.
    pub fn publish(&self, source_revision: u64, entities: Vec<Entity>) -> usize {
        let previous = self.inner.lock().expect("publication").current.clone();
        let seq = previous
            .seq
            .checked_add(1)
            .filter(|v| *v <= i64::MAX as u64)
            .expect("world stream exhausted");
        let delta = encode_delta(previous.epoch, seq, &previous.entities, &entities);
        let encoded_bytes = delta.len();
        let current = Arc::new(Publication {
            epoch: previous.epoch,
            seq,
            source_revision,
            entities,
            delta,
            chunks: OnceLock::new(),
        });
        let mut published = self.inner.lock().expect("publication");
        published.current = current.clone();
        let _ = published.sender.send(current);
        encoded_bytes
    }
    pub(crate) fn sequence(&self) -> u64 {
        self.inner.lock().expect("publication").current.seq
    }
    /// Subscription and baseline capture have the same linearization point.
    pub fn subscribe(&self) -> (Arc<Publication>, broadcast::Receiver<Arc<Publication>>) {
        let published = self.inner.lock().expect("publication");
        (published.current.clone(), published.sender.subscribe())
    }
}
pub fn encode_delta(epoch: Uuid, seq: u64, previous: &[Entity], current: &[Entity]) -> Bytes {
    let old: HashMap<u32, &Entity> = previous.iter().map(|e| (e.net_id, e)).collect();
    let new: HashMap<u32, &Entity> = current.iter().map(|e| (e.net_id, e)).collect();
    let entered: Vec<&Entity> = current
        .iter()
        .filter(|e| !old.contains_key(&e.net_id))
        .collect();
    let left: Vec<u32> = previous
        .iter()
        .filter(|e| !new.contains_key(&e.net_id))
        .map(|e| e.net_id)
        .collect();
    let moved: Vec<&Entity> = current
        .iter()
        .filter(|e| old.get(&e.net_id).is_some_and(|before| *before != *e))
        .collect();
    let lifecycle = serde_json::to_vec(&entered).expect("public enters");
    let mut bytes = Vec::with_capacity(
        HEADER + lifecycle.len() + left.len() * 4 + moved.len() * MOTION_BYTES + 32,
    );
    bytes.extend_from_slice(b"VWD2");
    bytes.extend_from_slice(epoch.as_bytes());
    bytes.extend_from_slice(&seq.to_be_bytes());
    bytes.extend_from_slice(&(lifecycle.len() as u32).to_be_bytes());
    bytes.extend_from_slice(&(left.len() as u16).to_be_bytes());
    bytes.extend_from_slice(&(moved.len() as u16).to_be_bytes());
    bytes.extend_from_slice(&lifecycle);
    for id in left {
        bytes.extend_from_slice(&id.to_be_bytes());
    }
    for entity in moved {
        bytes.extend_from_slice(&entity.net_id.to_be_bytes());
        bytes.extend_from_slice(&cell(entity.cell).to_be_bytes());
        bytes.extend_from_slice(&entity.next_cell.map(cell).unwrap_or(u16::MAX).to_be_bytes());
        bytes.extend_from_slice(&entity.segment_progress.to_be_bytes());
        bytes.extend_from_slice(
            &entity
                .entity_revision
                .parse::<u64>()
                .expect("revision")
                .to_be_bytes(),
        );
        bytes.extend_from_slice(
            &entity
                .last_input_seq
                .parse::<u64>()
                .expect("input sequence")
                .to_be_bytes(),
        );
    }
    let digest = Sha256::digest(&bytes);
    bytes.extend_from_slice(&digest);
    assert!(bytes.len() <= MAX_PACKET, "bounded world publication");
    bytes.into()
}
fn cell(value: [i32; 2]) -> u16 {
    (value[1] * 32 + value[0]) as u16
}
