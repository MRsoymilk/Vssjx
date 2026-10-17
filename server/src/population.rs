//! Server-owned Qingyun residents. Player counts and player replication stay separate.
use crate::world_map::{Motion, WorldMap};
use rand::{Rng, SeedableRng, rngs::StdRng, seq::SliceRandom};
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
    definitions_for("qingyun_trail")
}
pub fn definitions_for(map_id: &str) -> Vec<ResidentDefinition> {
    let bytes = match map_id {
        "qingyun_trail" => include_str!("../../shared/data/qingyun-population-v1.json"),
        "ancient_ruins" => include_str!("../../shared/data/ruins-population-v1.json"),
        _ => return Vec::new(),
    };
    serde_json::from_str(bytes).expect("resident definitions")
}
pub struct Resident {
    pub definition: ResidentDefinition,
    pub motion: Motion,
    rng: StdRng,
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
        Self::seeded(map, rand::random())
    }
    fn seeded(map: &WorldMap, seed: u64) -> Self {
        let mut seeds = StdRng::seed_from_u64(seed);
        let residents = definitions_for(&map.map_id)
            .into_iter()
            .map(|definition| {
                assert!(map.walkable(definition.cell));
                let mut rng = StdRng::seed_from_u64(seeds.r#gen());
                let wait = rng.gen_range(0.2..=2.5);
                Resident {
                    motion: Motion::new(definition.cell),
                    definition,
                    rng,
                    wait,
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
        let seconds = seconds.clamp(0.0, 0.1);
        let mut changed = false;
        for resident in &mut self.residents {
            if resident.definition.kind != "wolf" {
                continue;
            }
            if resident.wait > 0.0 {
                resident.wait -= seconds;
                continue;
            }
            if resident.motion.next.is_none() && resident.motion.route.is_empty() {
                let home = resident.definition.cell;
                let mut targets: Vec<_> = (-2..=2)
                    .flat_map(|y| (-2..=2).map(move |x| [home[0] + x, home[1] + y]))
                    .collect();
                targets.shuffle(&mut resident.rng);
                for target in targets {
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
                resident.wait = resident.rng.gen_range(0.5..=2.0);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn pose(resident: &Resident) -> [i32; 5] {
        let home = resident.definition.cell;
        let next = resident.motion.next.unwrap_or(resident.motion.cell);
        [
            resident.motion.cell[0] - home[0],
            resident.motion.cell[1] - home[1],
            next[0] - home[0],
            next[1] - home[1],
            (resident.motion.progress * 1000.0).round() as i32,
        ]
    }

    #[test]
    fn patrols_have_different_routes_and_independent_pause_times() {
        let map = WorldMap::default();
        let mut population = Population::seeded(&map, 403084);
        let mut traces = [Vec::new(), Vec::new(), Vec::new()];
        let mut mixed_motion = 0;
        for _ in 0..1200 {
            population.advance(&map, 0.1);
            let mut moving = 0;
            for (i, id) in ["wolf_a", "wolf_b", "wolf_c"].iter().enumerate() {
                let resident = population.get(id).unwrap();
                traces[i].push(pose(resident));
                moving += usize::from(resident.motion.next.is_some());
            }
            if moving > 0 && moving < 3 {
                mixed_motion += 1;
            }
        }
        assert!(mixed_motion > 100);
        assert_ne!(traces[0], traces[1]);
        assert_ne!(traces[1], traces[2]);
        assert_ne!(traces[0], traces[2]);
    }

    #[test]
    fn one_monsters_random_choices_cannot_change_others() {
        let map = WorldMap::default();
        let mut a = Population::seeded(&map, 403084);
        let mut b = Population::seeded(&map, 403084);
        for _ in 0..100 {
            b.residents[1].rng.r#gen::<u64>();
        }
        let mut first_differs = false;
        for _ in 0..1200 {
            a.advance(&map, 0.1);
            b.advance(&map, 0.1);
            first_differs |= pose(a.get("wolf_a").unwrap()) != pose(b.get("wolf_a").unwrap());
            for id in ["wolf_b", "wolf_c"] {
                assert_eq!(pose(a.get(id).unwrap()), pose(b.get(id).unwrap()));
            }
        }
        assert!(first_differs);
    }
}
