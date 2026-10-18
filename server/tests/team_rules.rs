use uuid::Uuid;
use vssjx_server::{
    population, pve_rules, skills,
    team_rules::{Battle, Fighter},
};
fn fighter(job: i16, level: i32) -> Fighter {
    let stats = pve_rules::stats(job, level, true);
    Fighter {
        id: Uuid::new_v4(),
        name: "同道".into(),
        job,
        gender: 0,
        school: 3,
        level,
        appearance: [1, 0, 0],
        stats,
        hp: stats.hp,
        mp: stats.mp,
        potions: 3,
        effects: skills::State::new(job, 3, level, 1),
        guarding: false,
    }
}
fn encounter() -> Battle {
    Battle::new(
        "qingyun_trail".into(),
        vec![fighter(1, 15), fighter(2, 15)],
        population::definitions()
            .into_iter()
            .filter(|d| d.kind != "npc")
            .take(3)
            .collect(),
        1000,
    )
}
#[test]
fn party_scaling_and_multiple_targets() {
    let b = encounter();
    assert_eq!(b.enemies.len(), 3);
    let original = population::definitions()
        .into_iter()
        .find(|d| d.id == b.enemies[0].definition.id)
        .unwrap();
    assert!(b.enemies[0].hp > original.hp && b.enemies[0].definition.attack > original.attack);
}
#[test]
fn each_player_acts_before_monsters() {
    let mut b = encounter();
    let hp: Vec<_> = b.fighters.iter().map(|f| f.hp).collect();
    b.act(b.fighters[0].id, "guard", None, None, 2000, 10)
        .unwrap();
    assert_eq!(b.turn, 1);
    assert_eq!(b.fighters.iter().map(|f| f.hp).collect::<Vec<_>>(), hp);
    b.act(b.fighters[1].id, "guard", None, None, 3000, 10)
        .unwrap();
    assert_eq!(b.round, 2);
    assert!(b.fighters.iter().map(|f| f.hp).sum::<i32>() < hp.iter().sum());
}
#[test]
fn foreign_turn_and_dead_targets_cannot_spend_mana() {
    let mut b = encounter();
    let before = serde_json::to_value(&b).unwrap();
    assert_eq!(
        b.act(b.fighters[1].id, "attack", Some("m0"), None, 2000, 0),
        Err("TEAM_NOT_YOUR_TURN")
    );
    assert_eq!(serde_json::to_value(&b).unwrap(), before);
    assert!(
        b.act(b.fighters[0].id, "attack", Some("m9"), None, 2000, 0)
            .is_err()
    );
    assert_eq!(serde_json::to_value(&b).unwrap(), before);
}
#[test]
fn area_skill_hits_every_living_enemy_for_one_mana_cost() {
    let mut b = encounter();
    for e in &mut b.enemies {
        e.hp = 1000;
        e.definition.hp = 1000;
    }
    let id = b.fighters[0].id;
    let mp = b.fighters[0].mp;
    b.act(id, "skill", Some("m1"), Some("sheet_004"), 2000, 99)
        .unwrap();
    assert!(b.enemies.iter().all(|e| e.hp < 1000));
    assert_eq!(
        b.fighters[0].mp,
        mp - skills::item("sheet_004").unwrap().mp_cost
    );
    assert_eq!(b.events.len(), 3);
}
#[test]
fn failures_and_potions_are_authoritative() {
    let mut b = encounter();
    let id = b.fighters[0].id;
    assert_eq!(b.act(id, "potion", None, None, 2000, 0), Err("HP_FULL"));
    b.fighters[0].hp -= 50;
    let count = b.fighters[0].potions;
    b.act(id, "potion", None, None, 2000, 0).unwrap();
    assert_eq!(b.fighters[0].potions, count - 1);
    assert_eq!(b.fighters[0].hp, b.fighters[0].stats.hp - 5);
}
#[test]
fn killed_monsters_never_take_a_turn() {
    let mut b = encounter();
    b.enemies[0].hp = 0;
    b.enemies[1].hp = 0;
    b.enemies[2].hp = 0;
    b.act(b.fighters[0].id, "guard", None, None, 2000, 99)
        .unwrap();
    assert_eq!(b.outcome, "victory");
    assert!(b.events.is_empty());
}
