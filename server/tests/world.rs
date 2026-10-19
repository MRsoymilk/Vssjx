use vssjx_server::{
    world::{ClientMessage, decimal},
    world_map::{Motion, WorldMap},
};
#[test]
fn click_routes_do_not_enter_a_different_portal_on_the_way_to_the_goal() {
    let ruins = WorldMap::load("ancient_ruins").unwrap();
    for (start, goal) in [([5,16],[17,19]), ([17,19],[3,16])] {
        let route = ruins.route(start,goal).unwrap();
        assert_eq!(route.back(),Some(&goal));
        let intended = vssjx_server::ai_world::exit_target(&ruins.map_id,goal);
        for point in route {
            if let Some(destination) = vssjx_server::ai_world::exit_target(&ruins.map_id,point) {
                assert_eq!(Some(destination),intended);
            }
        }
    }
    assert!(ruins.route([5,16],[12,16]).unwrap().contains(&[12,16]));
}
#[test]
fn ruins_portal_and_population_are_reachable_and_separate() {
    let trail = WorldMap::default();
    let ruins = WorldMap::load("ancient_ruins").unwrap();
    assert_ne!(trail.hash(), ruins.hash());
    assert!(WorldMap::load("unknown").is_none());
    for map in [&trail, &ruins] {
        let (_, gate, destination, spawn) = map.portal();
        assert!(map.route(map.spawn, gate).is_some());
        assert!(WorldMap::load(destination).unwrap().walkable(spawn));
        for resident in vssjx_server::population::definitions_for(&map.map_id) {
            assert!(map.route(map.spawn, resident.cell).is_some());
        }
    }
    let residents = vssjx_server::population::definitions_for("ancient_ruins");
    assert_eq!(residents.iter().map(|r|r.id.as_str()).collect::<Vec<_>>(), ["guardian", "boss"]);
}
#[test]
fn map_export_includes_river_bridge_and_tree_blockers() {
    let map = WorldMap::default();
    assert!(!map.walkable([5, 10]));
    assert!(map.walkable([5, 16]));
    assert!(!map.walkable([8, 8]));
    assert!(!map.walkable([9, 8]));
    assert!(!map.walkable([0, 16]));
    assert!(map.route([10, 16], [3, 16]).is_some());
    assert!(map.route([10, 16], [8, 8]).is_none());
    let route = map.route([10, 16], [8, 7]).unwrap();
    let mut previous = [10, 16];
    for cell in route {
        assert!(map.walkable(cell));
        assert_eq!(
            (cell[0] - previous[0]).abs() + (cell[1] - previous[1]).abs(),
            1
        );
        previous = cell;
    }
}
#[test]
fn movement_budget_and_retargeting_cannot_teleport_or_accelerate() {
    let map = WorldMap::default();
    let mut moving = Motion::new([10, 16]);
    assert!(moving.move_to(&map, [20, 16]));
    moving.advance(0.1);
    assert_eq!(moving.cell, [10, 16]);
    assert_eq!(moving.next, Some([11, 16]));
    assert!((moving.progress - 0.45).abs() < 1e-6);
    for _ in 0..100 {
        assert!(moving.move_to(&map, [20, 16]));
        moving.stop();
    }
    assert!((moving.progress - 0.45).abs() < 1e-6);
    moving.advance(0.1);
    moving.advance(0.1);
    assert_eq!(moving.cell, [11, 16]);
    assert!(moving.next.is_none());
    assert!(moving.move_to(&map, [20, 16]));
    moving.advance(100.0);
    assert!((moving.progress - 0.45).abs() < 1e-6); // Long server stall grants at most one 100ms step.
}
#[test]
fn world_messages_reject_authoritative_positions_duplicates_and_bad_sequences() {
    assert_eq!(decimal("9223372036854775807").unwrap(), i64::MAX as u64);
    for raw in ["01", "+1", "-1", "1.0", "9223372036854775808", "1\n", ""] {
        assert!(decimal(raw).is_err());
    }
    assert!(
        serde_json::from_str::<ClientMessage>(r#"{"type":"world.move_to","position":[900,900]}"#)
            .is_err()
    );
    assert!(
        serde_json::from_str::<ClientMessage>(r#"{"type":"ping","type":"world.leave"}"#).is_err()
    );
    assert!(serde_json::from_str::<ClientMessage>(r#"{"type":"ping","gold":900}"#).is_err());
}
