use vssjx_server::{
    population,
    pve_rules::{Action, Battle, Command, stats},
};
fn battle() -> Battle {
    Battle::new(
        population::definitions()
            .into_iter()
            .find(|e| e.id == "wolf_a")
            .unwrap(),
        120,
        35,
        6,
    )
}
#[test]
fn legal_turns_and_rejections_are_bounded() {
    for job in 0..3 {
        let stats = stats(job, 1, true);
        let mut b = battle();
        b.hp = stats.hp;
        b.mp = 0;
        let unchanged = serde_json::to_value(&b).unwrap();
        assert_eq!(
            b.turn(Action::Skill, job, stats, 0, 0),
            Err("MP_INSUFFICIENT")
        );
        assert_eq!(serde_json::to_value(&b).unwrap(), unchanged);
        assert_eq!(b.turn(Action::Potion, job, stats, 0, 0), Err("HP_FULL"));
        b.turn(Action::Guard, job, stats, 0, 0).unwrap();
        assert_eq!(b.mp, 5);
        let before = b.potions;
        b.turn(Action::Potion, job, stats, 0, 0).unwrap();
        assert_eq!(b.potions, before - 1);
        b.turn(Action::Flee, job, stats, 0, 0).unwrap();
        assert_eq!(b.outcome, "fled");
        assert_eq!(
            b.turn(Action::Attack, job, stats, 0, 0),
            Err("BATTLE_FINISHED")
        );
    }
}
#[test]
fn battle_damage_victory_defeat_and_timeout() {
    let stats = stats(0, 1, true);
    let mut b = battle();
    b.enemy_hp = 1;
    b.turn(Action::Attack, 0, stats, 0, 0).unwrap();
    assert_eq!(b.outcome, "victory");
    assert_eq!(b.hp, 120);
    let mut b = battle();
    b.hp = 1;
    b.enemy_hp = 6;
    b.turn(Action::Guard, 0, stats, 0, 0).unwrap();
    assert_eq!(b.outcome, "defeat"); // lethal reflection cannot grant rewards
    let mut b = battle();
    b.round = 29;
    b.turn(Action::Guard, 0, stats, 0, 0).unwrap();
    assert_eq!(b.outcome, "fled");
}
#[test]
fn client_cannot_supply_damage_or_rewards() {
    let id = uuid::Uuid::new_v4();
    assert!(
        serde_json::from_value::<Command>(
            serde_json::json!({"operation_id":id,"action":"attack","gold":9999})
        )
        .is_err()
    );
    assert!(
        serde_json::from_value::<Command>(serde_json::json!({"operation_id":id,"action":"win"}))
            .is_err()
    );
}
