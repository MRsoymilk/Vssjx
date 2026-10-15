//! Strict replication-v2 reconstruction: every bot retains every peer identity.
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};
use uuid::Uuid;

#[derive(Deserialize)]
struct Enter<'a> {
    net_id: u32,
    id: Uuid,
    #[serde(borrow)]
    last_input_seq: &'a str,
}
pub struct Model {
    epoch: Uuid,
    seq: u64,
    expected: Arc<HashMap<Uuid, usize>>,
    population: usize,
    own: usize,
    pub own_input: u64,
    nets: HashMap<u32, usize>,
    present: Vec<bool>,
    revisions: Vec<u64>,
    seen: Vec<bool>,
}
impl Model {
    pub fn new(
        epoch: Uuid,
        expected: Arc<HashMap<Uuid, usize>>,
        population: usize,
        own: usize,
    ) -> Self {
        Self {
            epoch,
            seq: 0,
            expected,
            population,
            own,
            own_input: 0,
            nets: HashMap::new(),
            present: vec![false; population],
            revisions: vec![0; population],
            seen: vec![false; population],
        }
    }
    pub fn count(&self) -> usize {
        self.nets.len()
    }
    pub fn install(&mut self, seq: u64, records: Vec<(u32, Uuid, u64, u64)>) -> Result<(), String> {
        let mut nets = HashMap::new();
        let mut present = vec![false; self.population];
        let mut revisions = vec![0; self.population];
        let mut own = None;
        for (net, id, input, revision) in records {
            let index = *self.expected.get(&id).ok_or("UNKNOWN_ENTITY")?;
            if net == 0
                || index >= self.population
                || present[index]
                || nets.insert(net, index).is_some()
            {
                return Err("DUPLICATE_ENTITY".into());
            }
            present[index] = true;
            revisions[index] = revision;
            if index == self.own {
                own = Some(input);
            }
        }
        self.own_input = own.ok_or("OWN_ENTITY_MISSING")?;
        self.seq = seq;
        self.nets = nets;
        self.present = present;
        self.revisions = revisions;
        Ok(())
    }
    pub fn apply(&mut self, raw: &[u8]) -> Result<usize, String> {
        if raw.len() < 70
            || raw.len() > 1048576
            || &raw[..4] != b"VWD2"
            || &raw[4..20] != self.epoch.as_bytes()
        {
            return Err("DELTA_HEADER".into());
        }
        let seq = u64_at(raw, 20);
        if seq != self.seq + 1 {
            return Err("DELTA_SEQUENCE".into());
        }
        let json_len = u32_at(raw, 28) as usize;
        let leaves = u16_at(raw, 32) as usize;
        let motions = u16_at(raw, 34) as usize;
        if json_len > 1048576
            || leaves > 1000
            || motions > 1000
            || 36 + json_len + leaves * 4 + motions * 26 + 32 != raw.len()
        {
            return Err("DELTA_SIZE".into());
        }
        if Sha256::digest(&raw[..raw.len() - 32]).as_slice() != &raw[raw.len() - 32..] {
            return Err("DELTA_DIGEST".into());
        }
        let entered: Vec<Enter> =
            serde_json::from_slice(&raw[36..36 + json_len]).map_err(|_| "DELTA_ENTERS")?;
        if entered.len() > 1000 {
            return Err("DELTA_LIMIT".into());
        }
        let mut removed = HashSet::new();
        let mut removed_members = HashSet::new();
        let mut offset = 36 + json_len;
        for _ in 0..leaves {
            let net = u32_at(raw, offset);
            offset += 4;
            let member = *self.nets.get(&net).ok_or("DELTA_UNKNOWN_LEAVE")?;
            if !removed.insert(net) || member == self.own {
                return Err("DELTA_DUPLICATE_LEAVE".into());
            }
            removed_members.insert(member);
        }
        let mut new_nets = HashSet::new();
        let mut new_members = HashSet::new();
        for entity in &entered {
            let index = *self.expected.get(&entity.id).ok_or("UNKNOWN_ENTITY")?;
            if entity.net_id == 0
                || index >= self.population
                || self.nets.contains_key(&entity.net_id)
                || !new_nets.insert(entity.net_id)
                || !new_members.insert(index)
                || (self.present[index] && !removed_members.contains(&index))
            {
                return Err("DELTA_DUPLICATE_ENTER".into());
            }
            entity
                .last_input_seq
                .parse::<u64>()
                .map_err(|_| "INPUT_SEQUENCE")?;
        }
        let movement_start = offset;
        self.seen.fill(false);
        for _ in 0..motions {
            let net = u32_at(raw, offset);
            let cell = u16_at(raw, offset + 4);
            let next = u16_at(raw, offset + 6);
            let progress = u16_at(raw, offset + 8);
            let revision = u64_at(raw, offset + 10);
            let input = u64_at(raw, offset + 18);
            offset += 26;
            let index = *self.nets.get(&net).ok_or("DELTA_UNKNOWN_MOTION")?;
            if removed.contains(&net)
                || self.seen[index]
                || cell > 1023
                || (next != 65535 && next > 1023)
                || progress > 1000
                || revision > i64::MAX as u64
                || input > i64::MAX as u64
                || revision < self.revisions[index]
            {
                return Err("DELTA_MOTION".into());
            }
            if next != 65535
                && (i32::from(cell % 32) - i32::from(next % 32)).abs()
                    + (i32::from(cell / 32) - i32::from(next / 32)).abs()
                    != 1
            {
                return Err("DELTA_ADJACENCY".into());
            }
            self.seen[index] = true;
        }
        if self.count() + entered.len() < leaves
            || self.count() + entered.len() - leaves > self.population
        {
            return Err("DELTA_POPULATION".into());
        }
        for net in removed {
            let index = self.nets.remove(&net).unwrap();
            self.present[index] = false;
        }
        let records = entered.len() + motions;
        for entity in entered {
            let index = self.expected[&entity.id];
            self.nets.insert(entity.net_id, index);
            self.present[index] = true;
            self.revisions[index] = 0;
        }
        offset = movement_start;
        for _ in 0..motions {
            let index = self.nets[&u32_at(raw, offset)];
            self.revisions[index] = u64_at(raw, offset + 10);
            if index == self.own {
                self.own_input = u64_at(raw, offset + 18);
            }
            offset += 26;
        }
        self.seq = seq;
        Ok(records)
    }
}
fn u16_at(bytes: &[u8], offset: usize) -> u16 {
    u16::from_be_bytes(bytes[offset..offset + 2].try_into().unwrap())
}
fn u32_at(bytes: &[u8], offset: usize) -> u32 {
    u32::from_be_bytes(bytes[offset..offset + 4].try_into().unwrap())
}
fn u64_at(bytes: &[u8], offset: usize) -> u64 {
    u64::from_be_bytes(bytes[offset..offset + 8].try_into().unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn decode(hex: &str) -> Vec<u8> {
        hex.as_bytes()
            .chunks_exact(2)
            .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
            .collect()
    }
    #[test]
    fn golden_frontiers_update_every_identity_and_own_input() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../../../shared/protocol/world-sync-v2.json"))
                .unwrap();
        let epoch = Uuid::parse_str(fixture["golden_epoch"].as_str().unwrap()).unwrap();
        let own = Uuid::new_v4();
        let peers = Arc::new(HashMap::from([(own, 0)]));
        let mut model = Model::new(epoch, peers, 1, 0);
        model.install(6, vec![(1, own, 0, 0)]).unwrap();
        assert_eq!(
            model
                .apply(&decode(fixture["golden_quiet_seq7_hex"].as_str().unwrap()))
                .unwrap(),
            0
        );
        assert_eq!(model.count(), 1);
        let moving = decode(fixture["golden_motion_seq8_hex"].as_str().unwrap());
        let mut corrupt = moving.clone();
        corrupt[40] ^= 1;
        assert!(model.apply(&corrupt).is_err());
        assert_eq!(model.own_input, 0);
        assert_eq!(model.apply(&moving).unwrap(), 1);
        assert_eq!(model.own_input, 7);
        assert!(model.apply(&moving).is_err()); // No duplicate sequence or movement replay.
    }
}
