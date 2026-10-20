use serde_json::json;
use vssjx_server::{
    pve_rules::Stats,
    skills::{self, State},
};
fn stats() -> Stats {
    Stats {
        hp: 1000,
        mp: 400,
        attack: 100,
        defense: 20,
        attributes: [0; 5],
        balance: None,
    }
}
#[test]
fn all_school_identities_share_job_skills_but_not_level_or_class_permissions() {
    for job in 0..3 {
        for level in [1, 5, 15, 25, 35, 45, 50, 55, 60] {
            let unjoined = skills::view(job, 3, level);
            for school in 0..3 {
                assert_eq!(skills::view(job, school, level), unjoined);
            }
        }
    }
    let emei_knight = skills::view(1, 0, 50);
    assert_eq!(emei_knight["available"].as_array().unwrap().len(), 8);
    assert!(emei_knight["available"].as_array().unwrap().contains(&json!("sheet_051")));
    assert!(!emei_knight["available"].as_array().unwrap().contains(&json!("sheet_008")));
    assert_eq!(skills::check("sheet_008", 1, 0, 50).err(), Some("SKILL_LEVEL_REQUIRED"));
    assert_eq!(skills::check("sheet_011", 1, 0, 60).err(), Some("SKILL_ROLE_MISMATCH"));
}

#[test]
fn saved_encounter_refreshes_cross_school_passives_without_clearing_active_effects() {
    use vssjx_server::{population, pve_rules::{Action, Battle}};
    let enemy = population::definitions().into_iter().find(|e| e.id == "wolf_a").unwrap();
    let mut battle = Battle::new(enemy, 100, 200, 6);
    battle.enemy_hp = 10000;
    battle.skill_rules_version = 1;
    battle.skills.enemy_sleep = 2;
    battle.skills.defense = 2;
    battle.skills.defense_percent = 25;
    // Old saved encounters may have neither passive from the newly shared job pool.
    battle.turn_selected(Action::Guard, 0, 3, 60, stats(), 0, 0, None, 99).unwrap();
    assert_eq!(battle.skills.passive_physical, 20);
    assert_eq!(battle.skills.passive_magic, 20);
    assert_eq!(battle.skills.enemy_sleep, 1);
    assert_eq!(battle.skills.defense, 1);
    assert_eq!(battle.skills.defense_percent, 25);
    assert!(!battle.skills.last_enemy_acted);
}
#[test]
fn catalog_restrictions_and_typed_effects() {
    assert_eq!(skills::ITEMS.len(), 33);
    for s in skills::ITEMS.iter() {
        assert!(skills::check(&s.id, (s.job + 1) % 3, s.school.max(0), 60).is_err());
        for school in 0..=3 {
            assert_eq!(skills::check(&s.id, s.job, school, 60).is_ok(), s.active);
            assert!(skills::eligible(s, s.job, school, 60));
        }
        if s.unlock_level > 1 {
            assert!(skills::check(&s.id, s.job, s.school.max(0), s.unlock_level - 1).is_err());
        }
        assert_eq!(
            skills::check(&s.id, s.job, s.school.max(0), 60).is_ok(),
            s.active
        );
    }
    let mut state = State::new(0, 2, 45, 1);
    assert_eq!(state.passive_physical, 20);
    assert_eq!(state.enemy_hit(50, false), (50, 10));
    assert_eq!(state.enemy_hit(50, true), (50, 10));
    let mut hp = 10;
    let mut mp = 100;
    let heal = skills::ITEMS.iter().find(|s| s.name == "起死回生").unwrap();
    state.cast(heal, stats(), &mut hp, &mut mp, 5, 0);
    state.after_player(&mut hp, 1000);
    assert_eq!(hp, 160);
    state.end_turn();
    state.after_player(&mut hp, 1000);
    assert_eq!(hp, 310);
    state.after_player(&mut hp, 1000);
    assert_eq!(hp, 310);
    let dot = skills::ITEMS.iter().find(|s| s.name == "推窗望月").unwrap();
    state.cast(dot, stats(), &mut hp, &mut mp, 5, 0);
    assert_eq!(state.after_player(&mut hp, 1000), 20);
    assert_eq!(state.after_player(&mut hp, 1000), 20);
    assert_eq!(state.after_player(&mut hp, 1000), 0);
    let sleep = skills::ITEMS.iter().find(|s| s.name == "醉生梦死").unwrap();
    state.cast(sleep, stats(), &mut hp, &mut mp, 5, 99);
    assert_eq!(state.enemy_sleep, 0);
    state.cast(sleep, stats(), &mut hp, &mut mp, 5, 0);
    assert_eq!(state.enemy_sleep, 2);
    state.end_turn();
    assert_eq!(state.enemy_sleep, 1);
    state.end_turn();
    assert_eq!(state.enemy_sleep, 0);
    let mana = skills::ITEMS.iter().find(|s| s.name == "偷天换日").unwrap();
    state.enemy_mp = 7;
    mp = 20;
    state.cast(mana, stats(), &mut hp, &mut mp, 5, 0);
    assert_eq!(state.enemy_mp, 0);
    assert_eq!(mp, 20 - mana.mp_cost + 7);
}
#[test]
fn shared_vectors_are_stable() {
    let vectors:Vec<_>=skills::ITEMS.iter().map(|s|{
        let mut state=State::new(s.job,s.school.max(0),60,10);
        state.reset_turn();let mut hp=100;let mut mp=200;
        let damage=state.cast(s,stats(),&mut hp,&mut mp,5,0);
        let dot=state.after_player(&mut hp,1000);
        let hit=state.enemy_hit(100,false);state.end_turn();
        json!({"id":s.id,"hp":hp,"mp":mp,"damage":damage,"dot":dot,"incoming":hit.0,"reflected":hit.1,"state":state})
    }).collect();
    let value = json!(vectors);
    if let Ok(path) = std::env::var("SSJX_WRITE_SKILL_VECTORS") {
        std::fs::write(path, serde_json::to_string_pretty(&value).unwrap() + "\n").unwrap();
    } else {
        let expected: serde_json::Value = serde_json::from_str(include_str!(
            "../../client/tests/fixtures/skills_golden.json"
        ))
        .unwrap();
        assert_eq!(value, expected);
    }
}

#[test]
fn battle_eligibility_is_atomic_and_statuses_survive_reload() {
    use vssjx_server::{
        population,
        pve_rules::{Action, Battle},
    };
    let enemy = population::definitions()
        .into_iter()
        .find(|e| e.id == "wolf_a")
        .unwrap();
    for skill in skills::ITEMS.iter() {
        let mut b = Battle::new(enemy.clone(), 100, 200, 6);
        b.enemy_hp = 10000;
        let before = serde_json::to_value(&b).unwrap();
        assert!(
            b.turn_selected(
                Action::Skill,
                (skill.job + 1) % 3,
                skill.school.max(0),
                60,
                stats(),
                0,
                0,
                Some(&skill.id),
                0
            )
            .is_err()
        );
        assert_eq!(serde_json::to_value(&b).unwrap(), before);
        if skill.active {
            b.turn_selected(
                Action::Skill,
                skill.job,
                skill.school.max(0),
                60,
                stats(),
                0,
                0,
                Some(&skill.id),
                0,
            )
            .unwrap();
            assert_eq!(b.skills.last_skill, skill.id);
            let saved = serde_json::to_value(&b).unwrap();
            let restored: Battle = serde_json::from_value(saved.clone()).unwrap();
            assert_eq!(serde_json::to_value(restored).unwrap(), saved);
        } else {
            assert_eq!(
                b.turn_selected(
                    Action::Skill,
                    skill.job,
                    skill.school.max(0),
                    60,
                    stats(),
                    0,
                    0,
                    Some(&skill.id),
                    0
                ),
                Err("PASSIVE_SKILL")
            );
        }
    }
    let mut b = Battle::new(enemy, 100, 200, 6);
    b.enemy_hp = 10000;
    b.turn_selected(Action::Skill, 1, 1, 15, stats(), 0, 0, Some("sheet_051"), 0)
        .unwrap();
    assert!(!b.skills.last_enemy_acted);
    assert_eq!(b.skills.enemy_sleep, 1);
    b.turn_selected(Action::Guard, 1, 1, 15, stats(), 0, 0, None, 99)
        .unwrap();
    assert!(!b.skills.last_enemy_acted);
    assert_eq!(b.skills.enemy_sleep, 0);
    b.turn_selected(Action::Guard, 1, 1, 15, stats(), 0, 0, None, 99)
        .unwrap();
    assert!(b.skills.last_enemy_acted);
    // Pre-upgrade durable JSON has no status fields; it still loads and upgrades on action.
    let mut old = serde_json::to_value(&b).unwrap();
    old.as_object_mut().unwrap().remove("skills");
    old.as_object_mut().unwrap().remove("skill_rules_version");
    let mut restored: Battle = serde_json::from_value(old).unwrap();
    restored
        .turn_selected(Action::Guard, 1, 1, 15, stats(), 0, 0, None, 99)
        .unwrap();
    assert_eq!(restored.skill_rules_version, 1);
}
