use vssjx_server::{
    attributes, population,
    pve_rules::{self, Action, Battle, Command},
};
#[test]
fn points_and_recommendations_are_level_bounded() {
    for job in 0..3 {
        for level in 1..=50 {
            let a = [0; 5];
            let r = attributes::recommended(job, level, a);
            assert_eq!(attributes::available(level, r), 0);
            assert!(r.iter().all(|v| *v >= 0 && *v <= 250));
            let b = pve_rules::stats(job, level, false);
            let old = attributes::stats(job, level, false, a);
            assert_eq!(
                (b.hp, b.mp, b.attack, b.defense),
                (old.hp, old.mp, old.attack, old.defense)
            );
        }
    }
}
#[test]
fn allocations_change_the_stats_used_by_combat() {
    let old = attributes::stats(1, 1, false, [0; 5]);
    let new = attributes::stats(1, 1, false, [0, 0, 5, 0, 0]);
    assert_eq!(new.hp, old.hp + 10);
    assert_eq!(new.attack, old.attack + 10);
    let enemy = population::definitions()
        .into_iter()
        .find(|e| e.id == "wolf_a")
        .unwrap();
    let mut original = Battle::new(enemy.clone(), old.hp, old.mp, 6);
    let mut boosted = Battle::new(enemy, new.hp, new.mp, 6);
    original.turn(Action::Attack, 1, old, 0, 0).unwrap();
    boosted.turn(Action::Attack, 1, new, 0, 0).unwrap();
    assert_eq!(original.enemy_hp - boosted.enemy_hp, 10);
}
#[test]
fn existing_commands_keep_their_receipt_digest_shape() {
    let value = serde_json::json!({"operation_id":uuid::Uuid::new_v4(),"action":"attack","target":null,"battle_id":null,"expected_revision":null});
    let command: Command = serde_json::from_value(value.clone()).unwrap();
    assert_eq!(serde_json::to_value(command).unwrap(), value);
}
