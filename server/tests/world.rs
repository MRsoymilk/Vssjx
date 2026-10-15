use vssjx_server::world_map::{Motion, WorldMap};
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
