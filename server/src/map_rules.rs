//! Versioned operational settings, deliberately separate from bundled asset hashes.
use crate::{population, world_map::WorldMap};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::{PgPool, Row, types::Json};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, LazyLock, RwLock},
};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Point {
    pub id: String,
    pub cell: [i32; 2],
    pub enabled: bool,
    pub respawn_seconds: i64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Portal {
    pub id: String,
    pub cell: [i32; 2],
    pub cells: Vec<[i32; 2]>,
    pub target_map: String,
    pub name: String,
    pub enabled: bool,
    pub legacy: bool,
    pub arrival: Option<[i32; 2]>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Gather {
    pub id: String,
    pub map_id: String,
    pub cell: [i32; 2],
    pub material: String,
    pub duration_ms: i64,
    pub respawn_ms: i64,
    pub min_quantity: i32,
    pub max_quantity: i32,
    #[serde(default = "yes")]
    pub enabled: bool,
}
fn yes() -> bool {
    true
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Document {
    pub entry_enabled: bool,
    pub spawn: [i32; 2],
    pub station: [i32; 2],
    pub station_enabled: bool,
    pub residents: Vec<Point>,
    pub portals: Vec<Portal>,
    pub gathering: Vec<Gather>,
}
#[derive(Clone, Default)]
pub struct Snapshot {
    pub active: BTreeMap<String, (i64, Document)>,
}
pub type Cache = Arc<RwLock<Arc<Snapshot>>>;
pub static DEFAULTS: LazyLock<BTreeMap<String, Document>> = LazyLock::new(|| {
    let nodes: Value = serde_json::from_str(include_str!("../../shared/data/gathering-v1.json"))
        .expect("gathering catalog");
    ids()
        .into_iter()
        .map(|id| {
            let map = WorldMap::load(&id).unwrap();
            let portals = if let Some(m) = crate::ai_world::map(&id) {
                m["exits"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|e| Portal {
                        id: e["id"].as_str().unwrap().into(),
                        cell: crate::ai_world::cell(&e["cell"]),
                        cells: e
                            .get("cells")
                            .and_then(Value::as_array)
                            .map(|cs| cs.iter().map(crate::ai_world::cell).collect())
                            .unwrap_or_else(|| vec![crate::ai_world::cell(&e["cell"])]),
                        target_map: e["target_map"].as_str().unwrap().into(),
                        name: e["name"].as_str().unwrap().into(),
                        enabled: true,
                        legacy: false,
                        arrival: None,
                    })
                    .collect()
            } else {
                let (gate, cell, target, arrival) = map.portal();
                let station = crate::ai_world::station(&id);
                vec![
                    Portal {
                        id: gate.into(),
                        cell,
                        cells: vec![cell],
                        target_map: target.into(),
                        name: if id == "qingyun_trail" {
                            "古剑遗迹 · 灵门"
                        } else {
                            "返回山道"
                        }
                        .into(),
                        enabled: true,
                        legacy: true,
                        arrival: Some(arrival),
                    },
                    Portal {
                        id: "ai_waystone".into(),
                        cell: station,
                        cells: vec![station],
                        target_map: "ai_001".into(),
                        name: "灵空台 · AI生成".into(),
                        enabled: true,
                        legacy: false,
                        arrival: None,
                    },
                ]
            };
            let gathering = nodes["nodes"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|n| n["map_id"] == id)
                .map(|n| serde_json::from_value(n.clone()).unwrap())
                .collect();
            let residents = population::definitions_for(&id)
                .into_iter()
                .map(|r| Point {
                    id: r.id,
                    cell: r.cell,
                    enabled: true,
                    respawn_seconds: 30,
                })
                .collect();
            (
                id.clone(),
                Document {
                    entry_enabled: true,
                    spawn: map.spawn,
                    station: crate::ai_world::station(&id),
                    station_enabled: true,
                    residents,
                    portals,
                    gathering,
                },
            )
        })
        .collect()
});
pub fn ids() -> Vec<String> {
    ["qingyun_trail".into(), "ancient_ruins".into()]
        .into_iter()
        .chain(
            crate::ai_world::maps()
                .iter()
                .map(|m| m["map_id"].as_str().unwrap().into()),
        )
        .collect()
}
pub fn title(id: &str) -> String {
    crate::ai_world::map(id)
        .and_then(|m| m["name"].as_str())
        .unwrap_or(if id == "qingyun_trail" {
            "青云山道"
        } else {
            "古剑遗迹"
        })
        .into()
}
impl Snapshot {
    pub fn document(&self, id: &str) -> &Document {
        self.active.get(id).map(|v| &v.1).unwrap_or(&DEFAULTS[id])
    }
    pub fn revision(&self, id: &str) -> i64 {
        self.active.get(id).map_or(0, |v| v.0)
    }
    pub fn packet(&self, id: &str) -> Value {
        json!({"type":"map.rules","version":1,"map_id":id,"revision":self.revision(id).to_string(),"rules":self.document(id)})
    }
    pub fn arrival(&self, id: &str) -> Result<[i32; 2], &'static str> {
        let d = self.document(id);
        if !d.entry_enabled {
            Err("MAP_CLOSED")
        } else {
            Ok(d.spawn)
        }
    }
    pub fn enabled(&self, map: &str, id: &str) -> bool {
        self.document(map)
            .residents
            .iter()
            .any(|p| p.id == id && p.enabled)
    }
    pub fn respawn_ms(&self, map: &str, id: &str) -> i64 {
        self.document(map)
            .residents
            .iter()
            .find(|p| p.id == id)
            .map_or(30000, |p| p.respawn_seconds * 1000)
    }
    pub fn exit(&self, map: &str, cell: [i32; 2]) -> Option<&Portal> {
        self.document(map)
            .portals
            .iter()
            .find(|p| p.enabled && p.cells.contains(&cell))
    }
}
pub async fn load(pool: &PgPool) -> Result<Arc<Snapshot>, sqlx::Error> {
    let rows=sqlx::query("SELECT a.map_id,a.revision,r.document FROM map_active a JOIN map_releases r ON r.revision=a.revision AND r.map_id=a.map_id").fetch_all(pool).await?;
    let snapshot = decode(rows)?;
    for (id, (_, d)) in &snapshot.active {
        if !validate(id, d).is_empty() {
            return Err(sqlx::Error::Protocol(
                "invalid published map configuration".into(),
            ));
        }
    }
    Ok(snapshot)
}
pub async fn load_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
) -> Result<Arc<Snapshot>, sqlx::Error> {
    decode(sqlx::query("SELECT a.map_id,a.revision,r.document FROM map_active a JOIN map_releases r ON r.revision=a.revision AND r.map_id=a.map_id").fetch_all(&mut **tx).await?)
}
fn decode(rows: Vec<sqlx::postgres::PgRow>) -> Result<Arc<Snapshot>, sqlx::Error> {
    let mut snapshot = Snapshot::default();
    for r in rows {
        let id: String = r.get("map_id");
        let d: Document = serde_json::from_value(r.get::<Json<Value>, _>("document").0)
            .map_err(|e| sqlx::Error::Decode(Box::new(e)))?;
        if !DEFAULTS.contains_key(&id) {
            return Err(sqlx::Error::Protocol(
                "invalid published map configuration".into(),
            ));
        }
        snapshot.active.insert(id, (r.get("revision"), d));
    }
    Ok(Arc::new(snapshot))
}
pub fn validate(id: &str, d: &Document) -> Vec<String> {
    let Some(base) = DEFAULTS.get(id) else {
        return vec!["未知地图".into()];
    };
    let map = WorldMap::load(id).unwrap();
    let mut errors = Vec::new();
    let mut point = |label: &str, c: [i32; 2]| {
        if !map.walkable(c) {
            errors.push(format!("{label}: 坐标不可行走"));
        }
    };
    point("出生点", d.spawn);
    point("驿站", d.station);
    for r in &d.residents {
        point(&r.id, r.cell);
    }
    for p in &d.portals {
        point(&p.id, p.cell);
        for c in &p.cells {
            point(&p.id, *c);
        }
    }
    for n in &d.gathering {
        point(&n.id, n.cell);
    }
    let same_ids = |a: Vec<&str>, b: Vec<&str>| {
        a.len() == b.len()
            && a.iter().collect::<BTreeSet<_>>().len() == a.len()
            && a.into_iter().collect::<BTreeSet<_>>() == b.into_iter().collect()
    };
    if !same_ids(
        d.residents.iter().map(|p| p.id.as_str()).collect(),
        base.residents.iter().map(|p| p.id.as_str()).collect(),
    ) || !same_ids(
        d.portals.iter().map(|p| p.id.as_str()).collect(),
        base.portals.iter().map(|p| p.id.as_str()).collect(),
    ) || !same_ids(
        d.gathering.iter().map(|p| p.id.as_str()).collect(),
        base.gathering.iter().map(|p| p.id.as_str()).collect(),
    ) {
        errors.push("仅支持修改现有点位，不能新增／删除资产或任务引用ID".into());
    }
    for r in &d.residents {
        if !(1..=86400).contains(&r.respawn_seconds) {
            errors.push(format!("{}: 刷新时间须为1～86400秒", r.id));
        }
    }
    let mut cells = BTreeSet::new();
    for p in &d.portals {
        if p.cells.is_empty()
            || p.cells.len() > 32
            || !p.cells.contains(&p.cell)
            || p.name.is_empty()
            || p.name.chars().count() > 64
            || p.name.chars().any(char::is_control)
            || !DEFAULTS.contains_key(&p.target_map)
            || p.target_map == id
            || base
                .portals
                .iter()
                .find(|b| b.id == p.id)
                .is_some_and(|b| b.legacy != p.legacy)
        {
            errors.push(format!("{}: 无效传送配置", p.id));
        }
        if let Some(c) = p.arrival {
            if WorldMap::load(&p.target_map).is_none_or(|m| !m.walkable(c)) {
                errors.push(format!("{}: 到达坐标不可行走", p.id));
            }
        }
        if p.enabled {
            for c in &p.cells {
                if !cells.insert(*c) {
                    errors.push("传送触发格重叠".into());
                }
            }
        }
    }
    if cells.contains(&d.spawn) {
        errors.push("出生点不能位于传送触发格".into());
    }
    for n in &d.gathering {
        if n.map_id != id
            || !["iron", "copper", "gancao", "danggui"].contains(&n.material.as_str())
            || !(1000..=60000).contains(&n.duration_ms)
            || !(1000..=86400000).contains(&n.respawn_ms)
            || !(1..=10).contains(&n.min_quantity)
            || !(n.min_quantity..=10).contains(&n.max_quantity)
            || n.enabled && (cells.contains(&n.cell) || n.cell == d.spawn)
        {
            errors.push(format!("{}: 无效采集配置或与传送／出生格冲突", n.id));
        }
    }
    if map.walkable(d.spawn) {
        let mut reached = BTreeSet::from([d.spawn]);
        let mut queue = std::collections::VecDeque::from([d.spawn]);
        while let Some(c) = queue.pop_front() {
            for delta in [[0, -1], [1, 0], [0, 1], [-1, 0]] {
                let n = [c[0] + delta[0], c[1] + delta[1]];
                if map.walkable(n) && reached.insert(n) {
                    queue.push_back(n);
                }
            }
        }
        for p in d.residents.iter().filter(|p| p.enabled) {
            if !reached.contains(&p.cell) {
                errors.push(format!("{}: 出生点无法抵达", p.id));
            }
        }
        for n in d.gathering.iter().filter(|n| n.enabled) {
            if !reached.contains(&n.cell) {
                errors.push(format!("{}: 出生点无法抵达", n.id));
            }
        }
    }
    errors
}
pub fn validate_with_active(id: &str, d: &Document, active: &Snapshot) -> Vec<String> {
    let mut errors = validate(id, d);
    for source in ids() {
        let rules = if source == id {
            d
        } else {
            active.document(&source)
        };
        for portal in rules.portals.iter().filter(|p| p.enabled) {
            if !DEFAULTS.contains_key(&portal.target_map) {
                continue;
            }
            let target = if portal.target_map == id {
                d
            } else {
                active.document(&portal.target_map)
            };
            let arrival = portal.arrival.unwrap_or(target.spawn);
            if target
                .portals
                .iter()
                .any(|p| p.enabled && p.cells.contains(&arrival))
            {
                errors.push(format!(
                    "{} / {}: 到达格不能落在目标地图传送触发格上",
                    source, portal.id
                ));
            }
        }
    }
    errors
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bundled_defaults_validate() {
        for (id, d) in DEFAULTS.iter() {
            assert!(validate(id, d).is_empty(), "{id}: {:?}", validate(id, d));
        }
    }
    #[test]
    fn reject_bad_positions_and_identity() {
        let mut d = DEFAULTS["qingyun_trail"].clone();
        d.spawn = [-1, 0];
        assert!(!validate("qingyun_trail", &d).is_empty());
        d = DEFAULTS["qingyun_trail"].clone();
        d.residents[0].id = "forged".into();
        assert!(!validate("qingyun_trail", &d).is_empty());
    }
}
