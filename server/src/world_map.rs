use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::VecDeque;

pub const MAP_BYTES: &str = include_str!("../../shared/data/qingyun-v1.json");
pub const RUINS_BYTES: &str = include_str!("../../shared/data/ancient-ruins-v1.json");
pub fn config_hash() -> String {
    format!("{:x}", Sha256::digest(MAP_BYTES.as_bytes()))
}

#[derive(Clone, Deserialize)]
pub struct WorldMap {
    pub map_id: String,
    pub width: i32,
    pub height: i32,
    pub cell_size: i32,
    pub spawn: [i32; 2],
    pub blocked: Vec<bool>,
    pub tiles: Vec<i32>,
}
impl Default for WorldMap {
    fn default() -> Self {
        Self::load("qingyun_trail").expect("default map")
    }
}
impl WorldMap {
    pub fn load(id: &str) -> Option<Self> {
        let bytes = match id {
            "qingyun_trail" => MAP_BYTES,
            "ancient_ruins" => RUINS_BYTES,
            _ => return crate::ai_world::map(id).map(|v|serde_json::from_value(v.clone()).expect("AI map")),
        };
        let map: Self = serde_json::from_str(bytes).expect("bundled map JSON");
        assert_eq!((map.width, map.height, map.cell_size), (32, 32, 16));
        assert_eq!(map.blocked.len(), 1024);
        assert_eq!(map.tiles.len(), 1024);
        assert!(map.walkable(map.spawn));
        Some(map)
    }
    pub fn hash(&self) -> String {
        if crate::ai_world::map(&self.map_id).is_some() {return crate::ai_world::hash();}
        let bytes = if self.map_id == "ancient_ruins" { RUINS_BYTES } else { MAP_BYTES };
        format!("{:x}", Sha256::digest(bytes.as_bytes()))
    }
    pub fn portal(&self) -> (&'static str, [i32; 2], &'static str, [i32; 2]) {
        if self.map_id == "ancient_ruins" {
            ("trail_gate", [3, 16], "qingyun_trail", [10, 16])
        } else {
            ("ruins_gate", [28, 16], "ancient_ruins", [5, 16])
        }
    }
    pub fn walkable(&self, cell: [i32; 2]) -> bool {
        cell[0] >= 0
            && cell[1] >= 0
            && cell[0] < self.width
            && cell[1] < self.height
            && !self.blocked[(cell[1] * self.width + cell[0]) as usize]
    }
    pub fn route(&self, start: [i32; 2], goal: [i32; 2]) -> Option<VecDeque<[i32; 2]>> {
        if !self.walkable(start) || !self.walkable(goal) {
            return None;
        }
        let index = |c: [i32; 2]| (c[1] * self.width + c[0]) as usize;
        let mut previous = vec![None; 1024];
        let mut queue = VecDeque::from([start]);
        previous[index(start)] = Some(start);
        while let Some(cell) = queue.pop_front() {
            if cell == goal {
                let mut route = VecDeque::new();
                let mut current = goal;
                while current != start {
                    route.push_front(current);
                    current = previous[index(current)]?;
                }
                return Some(route);
            }
            for delta in [[0, -1], [1, 0], [0, 1], [-1, 0]] {
                let next = [cell[0] + delta[0], cell[1] + delta[1]];
                if self.walkable(next) && previous[index(next)].is_none() {
                    previous[index(next)] = Some(cell);
                    queue.push_back(next);
                }
            }
        }
        None
    }
}

#[derive(Clone)]
pub struct Motion {
    pub cell: [i32; 2],
    pub next: Option<[i32; 2]>,
    pub progress: f64,
    pub route: VecDeque<[i32; 2]>,
    pub revision: u64,
}
impl Motion {
    pub fn new(cell: [i32; 2]) -> Self {
        Self {
            cell,
            next: None,
            progress: 0.0,
            route: VecDeque::new(),
            revision: 0,
        }
    }
    pub fn move_to(&mut self, map: &WorldMap, goal: [i32; 2]) -> bool {
        let Some(route) = map.route(self.next.unwrap_or(self.cell), goal) else {
            return false;
        };
        self.route = route;
        true
    }
    pub fn stop(&mut self) {
        self.route.clear();
    }
    pub fn advance(&mut self, seconds: f64) -> bool {
        let mut budget = seconds.clamp(0.0, 0.1) * 72.0 / 16.0;
        let mut moved = false;
        while budget > 0.0 {
            if self.next.is_none() {
                self.next = self.route.pop_front();
            }
            let Some(next) = self.next else { break };
            let distance = budget.min(1.0 - self.progress);
            self.progress += distance;
            budget -= distance;
            moved = true;
            if self.progress >= 1.0 - 1e-9 {
                self.cell = next;
                self.next = None;
                self.progress = 0.0;
            }
        }
        if moved {
            self.revision += 1;
        }
        moved
    }
}
