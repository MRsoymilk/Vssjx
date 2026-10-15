//! Server-owned Qingyun residents. Player counts and player replication stay separate.
use crate::world_map::{Motion, WorldMap};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::Arc;
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ResidentDefinition {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub art: String,
    pub cell: [i32; 2],
    pub level: i32,
    pub hp: i32,
    pub attack: i32,
    pub defense: i32,
    pub gold: i32,
    pub xp: i32,
}
pub fn definitions() -> Vec<ResidentDefinition> {
    serde_json::from_str(include_str!("../../shared/data/qingyun-population-v1.json"))
        .expect("resident definitions")
}
pub struct Resident {
    pub definition: ResidentDefinition,
    pub motion: Motion,
    waypoint: usize,
    wait: f64,
}
pub struct Population {
    pub residents: Vec<Resident>,
    epoch: Uuid,
    revision: u64,
    packet: Arc<str>,
}
impl Population {
    pub fn new(map: &WorldMap) -> Self {
        let residents = definitions()
            .into_iter()
            .enumerate()
            .map(|(index, definition)| {
                assert!(map.walkable(definition.cell));
                Resident {
                    motion: Motion::new(definition.cell),
                    definition,
                    waypoint: 0,
                    wait: 0.7 + index as f64 * 0.25,
                }
            })
            .collect();
        let mut value = Self {
            residents,
            epoch: Uuid::new_v4(),
            revision: 0,
            packet: Arc::from(""),
        };
        value.encode();
        value
    }
    pub fn get(&self, id: &str) -> Option<&Resident> {
        self.residents.iter().find(|r| r.definition.id == id)
    }
    pub fn advance(&mut self, map: &WorldMap, seconds: f64) {
        const OFFSETS: [[i32; 2]; 6] = [[2, 0], [2, 1], [0, 1], [-2, 1], [-2, 0], [0, 0]];
        let mut changed = false;
        for resident in &mut self.residents {
            if resident.definition.kind != "wolf" {
                continue;
            }
            if resident.wait > 0.0 {
                resident.wait -= seconds.min(0.1);
                continue;
            }
            if resident.motion.next.is_none() && resident.motion.route.is_empty() {
                for _ in 0..OFFSETS.len() {
                    let offset = OFFSETS[resident.waypoint];
                    resident.waypoint = (resident.waypoint + 1) % OFFSETS.len();
                    let home = resident.definition.cell;
                    let target = [home[0] + offset[0], home[1] + offset[1]];
                    if let Some(route) = map.route(resident.motion.cell, target)
                        && !route.is_empty()
                        && route.iter().all(|cell| {
                            (cell[0] - home[0]).abs().max((cell[1] - home[1]).abs()) <= 2
                        })
                    {
                        resident.motion.route = route;
                        break;
                    }
                }
            }
            changed |= resident
                .motion
                .advance(seconds.clamp(0.0, 0.1) * 28.0 / 72.0);
            if resident.motion.next.is_none() && resident.motion.route.is_empty() {
                resident.wait = 0.6;
            }
        }
        if changed {
            self.revision += 1;
            self.encode();
        }
    }
    fn encode(&mut self) {
        let entities: Vec<_> = self
            .residents
            .iter()
            .map(|resident| {
                let mut value = serde_json::to_value(&resident.definition).expect("resident");
                value["cell"] = json!(resident.motion.cell);
                value["next_cell"] = json!(resident.motion.next);
                value["segment_progress"] =
                    json!((resident.motion.progress * 1000.0).round() as u16);
                value["world_epoch"] = json!("1");
                value["entity_revision"] = json!(resident.motion.revision.to_string());
                value
            })
            .collect();
        self.packet = Arc::from(json!({"type":"population.state","epoch":self.epoch,"revision":self.revision.to_string(),"entities":entities}).to_string());
    }
    pub fn packet_since(&self, revision: Option<u64>) -> Option<(u64, Arc<str>)> {
        (revision != Some(self.revision)).then(|| (self.revision, self.packet.clone()))
    }
}
