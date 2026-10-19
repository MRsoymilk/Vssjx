use std::time::Instant;
use uuid::Uuid;
use vssjx_server::{duel, population, pve_rules::{self, Action, Stats}, skills, team_rules};

fn stats() -> Stats {
    let mut result = pve_rules::stats(0, 1, false);
    result.hp = 1000; result.mp = 300; result.attack = 100; result.defense = 5;
    result
}

#[test]
fn critical_metadata_uses_the_actual_roll_and_resets() {
    let mut state = skills::State::default();
    state.crit = 1; state.crit_chance = 50;
    assert_eq!(state.critical(1, 0), 1);
    assert!(state.last_critical, "Rounding must not hide a genuine critical roll");
    assert_eq!(serde_json::to_value(&state).unwrap()["last_critical"], true);
    assert_eq!(state.critical(20, 99), 20);
    assert!(!state.last_critical);
    state.critical(20, 0); state.reset_turn();
    assert!(!state.last_critical);
    assert!(serde_json::to_value(&state).unwrap().get("last_critical").is_none());
    let old = serde_json::to_value(&state).unwrap();
    let loaded: skills::State = serde_json::from_value(old).unwrap();
    assert!(!loaded.last_critical, "Existing saves need no migration");
    assert_eq!(state.critical(0, 0), 0);
    assert!(!state.last_critical, "Support skills must not flash");
}

#[test]
fn pve_snapshot_carries_critical_result() {
    let enemy = population::definitions().into_iter().find(|e| e.id == "wolf_a").unwrap();
    let mut battle = pve_rules::Battle::new(enemy, 1000, 300, 3);
    battle.enemy_hp = 5000; battle.skill_rules_version = 1;
    battle.skills.crit = 1; battle.skills.crit_chance = 100;
    battle.turn_selected(Action::Attack, 0, 3, 60, stats(), 0, 0, None, 0).unwrap();
    assert!(battle.skills.last_damage > 0 && battle.skills.last_critical);
    battle.turn_selected(Action::Guard, 0, 3, 60, stats(), 0, 0, None, 99).unwrap();
    assert!(!battle.skills.last_critical);
}

#[test]
fn team_events_attach_critical_to_the_specific_hit() {
    let mut effects = skills::State::new(0, 3, 60, 1);
    effects.crit = 1; effects.crit_chance = 100;
    let fighter = team_rules::Fighter {
        id: Uuid::new_v4(), name: "同道".into(), job: 0, gender: 0, school: 3,
        level: 60, appearance: [1,0,0], stats: stats(), hp: 1000, mp: 300,
        potions: 3, effects, guarding: false,
    };
    let me = fighter.id;
    let mut enemy = population::definitions().into_iter().find(|e| e.id == "wolf_a").unwrap();
    enemy.hp = 5000;
    let mut battle = team_rules::Battle::new("qingyun_trail".into(), vec![fighter], vec![enemy], 1000);
    battle.act(me, "attack", Some("m0"), None, 2000, 0).unwrap();
    assert!(battle.events.iter().any(|e| e.actor == me.to_string() && e.critical && e.damage > 0));
    assert!(battle.events.iter().filter(|e| e.actor == "m0").all(|e| !e.critical));
    let encoded = serde_json::to_value(&battle.events).unwrap();
    assert_eq!(encoded[0]["critical"], true);
}

#[test]
fn duel_events_keep_each_sides_critical_result() {
    fn fighter(name: &str) -> duel::Fighter {
        duel::Fighter { id: Uuid::new_v4(), name: name.into(), job: 0, gender: 0,
            school: 3, level: 50, speed: 100, stats: stats(), appearance: [1,0,0],
            hp: 1000, mp: 300, effects: skills::State::new(0,3,50,50), guarding: false }
    }
    let now = Instant::now();
    let mut a = fighter("甲甲"); let b = fighter("乙乙");
    a.effects.crit = 1; a.effects.crit_chance = 100;
    let ids = [a.id, b.id];
    let mut arena = duel::Arena::default();
    let offer = arena.invite(ids[0], ids[1], a.name.clone(), b.name.clone(), now).unwrap();
    let id = arena.start(offer, ids[1], [a,b], now).unwrap();
    let mut command = duel::Command { request_id: Uuid::new_v4(), action: "attack".into(),
        target: None, invite_id: None, battle_id: Some(id), expected_revision: Some("0".into()), skill: None };
    arena.act(ids[0], &command, now, [0;3]).unwrap();
    command.request_id = Uuid::new_v4(); command.action = "guard".into();
    arena.act(ids[1], &command, now, [0;3]).unwrap();
    let events = &arena.battles[&id].events;
    assert!(events.iter().any(|e| e.actor == ids[0] && e.critical && e.damage > 0));
    assert!(events.iter().filter(|e| e.actor == ids[1]).all(|e| !e.critical));
}
