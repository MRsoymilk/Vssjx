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
    assert_eq!(emei_knight["available"].as_array().unwrap().len(), 9);
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
    assert_eq!(skills::ITEMS.len(), 36);
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
    assert_eq!(state.enemy_hit(50, 100, false), (50, 20));
    assert_eq!(state.enemy_hit(50, 100, true), (50, 20));
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
fn reflection_scales_with_own_attack_not_received_damage_or_mitigation() {
    let mut state=State::new(0,3,60,1);
    for magical in [false,true] {
        for incoming in [1,50,5000] {
            assert_eq!(state.enemy_hit(incoming,120,magical),(incoming,24));
            assert_eq!(state.enemy_hit(incoming,240,magical),(incoming,48));
        }
    }
    state.reflect_physical=2;state.physical_percent=60;
    state.reflect_magic=2;state.magic_percent=60;
    state.defense=2;state.defense_percent=50;
    for magical in [false,true] {
        assert_eq!(state.enemy_hit(50,120,magical),(25,72));
        assert_eq!(state.enemy_hit(5000,120,magical),(2500,72));
        assert_eq!(state.enemy_hit(50,119,magical),(25,71));
        assert_eq!(state.enemy_hit(0,120,magical),(0,0));
        assert_eq!(state.enemy_hit(50,0,magical),(25,0));
    }
}

#[test]
fn active_reflection_casts_last_two_turns_without_stacking_with_passives() {
    for (id,magical) in [("sheet_011",false),("sheet_033",true)] {
        let skill=skills::item(id).unwrap();assert_eq!(skill.value,60);assert_eq!(skill.duration,2);
        let mut state=State::new(0,3,60,1);let mut hp=100;let mut mp=200;
        let mut own=stats();own.attack=120;
        assert_eq!(state.cast(skill,own,&mut hp,&mut mp,0,99),0);
        assert_eq!(state.enemy_hit(500,own.attack,magical),(500,72));
        assert_eq!(state.enemy_hit(500,own.attack,!magical),(500,24));
        state.end_turn();
        let mut state:State=serde_json::from_value(serde_json::to_value(state).unwrap()).unwrap();
        assert_eq!(state.enemy_hit(500,own.attack,magical),(500,72));
        state.end_turn();
        assert_eq!(state.enemy_hit(500,own.attack,magical),(500,24));
        assert_eq!(state.passive_physical,20);assert_eq!(state.passive_magic,20);
    }
}

#[test]
fn active_reflection_applies_once_per_hit_in_multi_enemy_rounds_then_expires() {
    use vssjx_server::{population,team_rules};
    let mut own=stats();own.attack=120;own.hp=10000;
    let id=uuid::Uuid::new_v4();
    let f=team_rules::Fighter{id,name:"多怪反弹".into(),job:0,gender:0,school:3,level:60,appearance:[0;3],stats:own,hp:own.hp,mp:own.mp,potions:6,effects:State::new(0,3,60,1),guarding:false};
    let mut enemy=population::definitions().into_iter().find(|e|e.id=="wolf_a").unwrap();enemy.attack=50;enemy.hp=10000;
    let mut b=team_rules::Battle::new("qingyun_trail".into(),vec![f],vec![enemy.clone(),enemy.clone(),enemy],1000);
    for (action,skill,expected,timer) in [("skill",Some("sheet_011"),72,1),("guard",None,78,0),("guard",None,30,0)] {
        b.act(id,action,None,skill,b.selection_starts_ms+1,99).unwrap();
        let reflected:Vec<_>=b.events.iter().filter(|e|e.actor==id.to_string()&&e.action=="dot").collect();
        assert_eq!(reflected.len(),3);assert!(reflected.iter().all(|e|e.damage==expected));
        assert_eq!(b.fighters[0].effects.reflect_physical,timer);
    }
}

#[test]
fn solo_and_formation_use_the_reflecting_fighters_stats() {
    use vssjx_server::{population,pve_rules::{Action,Battle},team_rules};
    let mut own=stats();own.attack=120;own.hp=10000;
    for attack in [50,500] {
        let mut enemy=population::definitions().into_iter().find(|e|e.id=="wolf_a").unwrap();enemy.attack=attack;enemy.hp=10000;
        let mut solo=Battle::new(enemy.clone(),own.hp,own.mp,6);
        solo.turn_selected(Action::Guard,0,3,60,own,0,0,None,99).unwrap();
        assert_eq!(solo.skills.last_reflected,30,"own 120 × 20% plus unchanged guard bonus 6");
        let id=uuid::Uuid::new_v4();
        let f=team_rules::Fighter{id,name:"反弹验证".into(),job:0,gender:0,school:3,level:60,appearance:[0;3],stats:own,hp:own.hp,mp:own.mp,potions:6,effects:State::new(0,3,60,1),guarding:false};
        let mut formation=team_rules::Battle::new("qingyun_trail".into(),vec![f],vec![enemy],1000);
        formation.act(id,"guard",None,None,formation.selection_starts_ms+1,99).unwrap();
        let reflection=formation.events.iter().find(|e|e.actor==id.to_string()&&e.action=="dot").unwrap();
        assert_eq!(reflection.damage,30,"formation must use its defender's own attack");
    }
}

#[test]
fn shared_vectors_are_stable() {
    let vectors:Vec<_>=skills::ITEMS.iter().map(|s|{
        let mut state=State::new(s.job,s.school.max(0),60,10);
        state.reset_turn();let mut hp=100;let mut mp=200;
        let damage=state.cast(s,stats(),&mut hp,&mut mp,5,0);
        let dot=state.after_player(&mut hp,1000);
        let hit=state.enemy_hit(100,stats().attack,false);state.end_turn();
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
