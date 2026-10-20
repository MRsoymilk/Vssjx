//! A corpse is private to its character. Its position comes only from server motion.
use crate::world_map::WorldMap;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Corpse {
    pub id: Uuid,
    pub map_id: String,
    pub cell: [i32; 2],
}
impl Corpse {
    pub fn new(map_id: &str, cell: [i32; 2]) -> Result<Self, &'static str> {
        let corpse = Self { id: Uuid::new_v4(), map_id: map_id.into(), cell };
        if !corpse.valid() { return Err("INVALID_CORPSE_POSITION"); }
        Ok(corpse)
    }
    pub fn valid(&self) -> bool {
        self.id.get_version_num() == 4 && self.map_id.len() <= 32
            && WorldMap::load(&self.map_id).is_some_and(|map|map.walkable(self.cell))
    }
    pub fn can_recover(&self, map_id: &str, cell: [i32; 2]) -> bool {
        self.map_id == map_id && (self.cell[0]-cell[0]).abs()+(self.cell[1]-cell[1]).abs() <= 2
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn corpses_are_unique_map_bound_and_recovered_only_nearby() {
        let a=Corpse::new("qingyun_trail",[10,16]).unwrap();
        let b=Corpse::new("qingyun_trail",[10,16]).unwrap();
        assert_ne!(a.id,b.id);
        assert!(a.can_recover("qingyun_trail",[12,16]));
        assert!(!a.can_recover("qingyun_trail",[13,16]));
        assert!(!a.can_recover("ancient_ruins",[10,16]));
        assert!(Corpse::new("missing",[10,16]).is_err());
        assert!(Corpse::new("qingyun_trail",[-1,16]).is_err());
    }
}
