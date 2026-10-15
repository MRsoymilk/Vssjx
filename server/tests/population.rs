use serde_json::Value;
use vssjx_server::{population::Population, world_map::WorldMap};

#[test]
fn residents_spawn_and_patrol_on_one_authoritative_map() {
    let map = WorldMap::default();
    let mut population = Population::new(&map);
    assert_eq!(population.residents.len(), 5);
    let (first, packet) = population.packet_since(None).unwrap();
    let packet: Value = serde_json::from_str(&packet).unwrap();
    assert_eq!(packet["entities"][0]["name"], "清微道人");
    let home = population.get("qingwei").unwrap().motion.cell;
    let mut moved = false;
    for _ in 0..1200 {
        population.advance(&map, 0.1);
        for actor in &population.residents {
            assert!(map.walkable(actor.motion.cell));
            if let Some(next) = actor.motion.next {
                assert!(map.walkable(next));
                assert_eq!(
                    (next[0] - actor.motion.cell[0]).abs() + (next[1] - actor.motion.cell[1]).abs(),
                    1
                );
            }
            assert!(
                (actor.motion.cell[0] - actor.definition.cell[0])
                    .abs()
                    .max((actor.motion.cell[1] - actor.definition.cell[1]).abs())
                    <= 2
            );
            moved |= actor.definition.kind == "wolf" && actor.motion.cell != actor.definition.cell;
        }
    }
    assert!(moved);
    assert_eq!(population.get("qingwei").unwrap().motion.cell, home);
    assert!(population.packet_since(Some(first)).is_some());
    assert_eq!(
        population.packet_since(None).unwrap(),
        population.packet_since(None).unwrap()
    );
}
