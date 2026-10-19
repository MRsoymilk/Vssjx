use vssjx_server::{
    attributes, population,
    pve_rules::{self, Action, Battle, Command},
};
#[test]
fn offline_ui_vectors_match_the_authoritative_attribute_contract() {
    let cases: serde_json::Value = serde_json::from_str(include_str!(
        "../../client/tests/fixtures/attribute_vectors.json"
    ))
    .unwrap();
    for c in cases.as_array().unwrap() {
        let a: [i32; 5] = serde_json::from_value(c["allocated"].clone()).unwrap();
        let job = c["job"].as_i64().unwrap() as i16;
        let level = c["level"].as_i64().unwrap() as i32;
        let equipped = c["equipped"].as_bool().unwrap();
        assert_eq!(
            serde_json::to_value(attributes::stats(job, level, equipped, a)).unwrap(),
            c["stats"]
        );
        let p = attributes::profile(job, level, equipped, a);
        for key in ["available", "recommended"] {
            assert_eq!(p[key], c[key]);
        }
        for key in [
            "physical_attack",
            "magic_attack",
            "physical_crit",
            "magic_crit",
        ] {
            assert_eq!(p["combat"][key], c[key]);
        }
    }
}
#[test]
fn agility_and_focus_have_separate_physical_and_magic_ratings() {
    for job in 0..3 {
        for agility in [0, 1, 50, 300] {
            let profile = attributes::profile(job, 60, false, [0, 0, 0, agility, 0]);
            assert_eq!(profile["combat"]["physical_crit"], agility);
            assert_eq!(profile["combat"]["magic_crit"], 0);
            assert_eq!(profile["combat"]["physical_evasion"], agility);
            assert_eq!(profile["combat"]["physical_hit"], 100 + agility);
            let focus = attributes::profile(job, 60, false, [0, 0, 0, 0, agility]);
            assert_eq!(focus["combat"]["magic_crit"], agility);
            assert_eq!(focus["combat"]["magic_evasion"], agility);
            assert_eq!(focus["combat"]["magic_hit"], 100 + agility);
        }
        let other = attributes::profile(job, 60, true, [50, 50, 50, 0, 50]);
        assert_eq!(other["combat"]["physical_crit"], 0);
        assert_eq!(other["combat"]["magic_crit"], 50);
    }
}
#[test]
fn points_and_recommendations_are_level_bounded() {
    for job in 0..3 {
        for level in 1..=60 {
            let a = [0; 5];
            let r = attributes::recommended(job, level, a);
            assert_eq!(attributes::available(level, r), 0);
            assert!(r.iter().all(|v| *v >= 0 && *v <= 300));
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
    assert_eq!(new.hp, old.hp);
    assert_eq!(new.mp, old.mp + 5);
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
fn every_primary_changes_only_its_originally_described_stats() {
    let deltas = [
        vec![("hp", 8), ("mp", 1)],
        vec![("mp", 5), ("magic_attack", 2)],
        vec![("mp", 1), ("physical_attack", 2)],
        vec![
            ("physical_crit", 1),
            ("physical_hit", 1),
            ("physical_evasion", 1),
        ],
        vec![("magic_crit", 1), ("magic_hit", 1), ("magic_evasion", 1)],
    ];
    for job in 0..3 {
        let baseline = attributes::profile(job, 60, true, [0; 5]);
        for i in 0..5 {
            let mut a = [0; 5];
            a[i] = 1;
            let changed = attributes::profile(job, 60, true, a);
            for (key, base) in baseline["combat"].as_object().unwrap() {
                let delta = deltas[i]
                    .iter()
                    .find(|(k, _)| *k == key)
                    .map_or(0, |(_, v)| *v);
                assert_eq!(
                    changed["combat"][key].as_i64().unwrap() - base.as_i64().unwrap(),
                    delta,
                    "job {job}, primary {i}, field {key}"
                );
            }
        }
    }
}
#[test]
fn physical_and_magical_power_include_equipment_without_cross_allocations() {
    for job in 0..3 {
        let base = attributes::stats(job, 50, true, [0; 5]);
        let spirit = attributes::stats(job, 50, true, [0, 50, 0, 0, 0]);
        let strength = attributes::stats(job, 50, true, [0, 0, 50, 0, 0]);
        assert_eq!(
            attributes::for_attack(spirit, job, false).attack,
            base.attack
        );
        assert_eq!(
            attributes::for_attack(spirit, job, true).attack,
            base.attack + 100
        );
        assert_eq!(
            attributes::for_attack(strength, job, false).attack,
            base.attack + 100
        );
        assert_eq!(
            attributes::for_attack(strength, job, true).attack,
            base.attack
        );
    }
}
#[test]
fn ratings_are_bounded_and_one_point_works_at_basis_point_precision() {
    use vssjx_server::skills::State;
    let a = attributes::stats(1, 60, false, [0, 0, 0, 300, 0]);
    let f = attributes::stats(2, 60, false, [0, 0, 0, 0, 300]);
    assert_eq!(attributes::hit_chance(None, Some(a), false), 7000);
    assert_eq!(attributes::hit_chance(None, Some(a), true), 10000);
    assert_eq!(attributes::hit_chance(Some(a), Some(a), false), 10000);
    assert_eq!(attributes::hit_chance(None, Some(f), true), 7000);
    let one = attributes::stats(1, 1, false, [0, 0, 0, 1, 0]);
    let mut effects = State::default();
    assert_eq!(
        attributes::critical_at(one, false, &mut effects, 100, 9),
        150
    );
    assert!(effects.last_critical);
    assert_eq!(
        attributes::critical_at(one, false, &mut effects, 100, 10),
        100
    );
    assert!(!effects.last_critical);
    assert_eq!(
        attributes::critical_at(one, true, &mut effects, 100, 0),
        100
    );
    effects.crit = 2;
    effects.crit_chance = 60;
    assert_eq!(
        attributes::critical_at(a, false, &mut effects, 100, 7499),
        150
    );
    assert_eq!(
        attributes::critical_at(a, false, &mut effects, 100, 7500),
        100
    );
}
#[test]
fn saved_stats_retain_inputs_but_shared_battle_frames_hide_allocations() {
    let stats = attributes::stats(2, 50, true, [10, 20, 30, 40, 50]);
    let saved = serde_json::to_value(stats).unwrap();
    let restored: pve_rules::Stats = serde_json::from_value(saved.clone()).unwrap();
    assert_eq!(restored.attributes, stats.attributes);
    let shared = attributes::public_battle(
        serde_json::json!({"fighters":[{"stats":saved}],"events":[{"fighters":[{"stats":saved}]}]}),
    );
    assert!(shared["fighters"][0]["stats"].get("attributes").is_none());
    assert!(
        shared["events"][0]["fighters"][0]["stats"]
            .get("attributes")
            .is_none()
    );
    assert_eq!(shared["fighters"][0]["stats"]["attack"], stats.attack);
}
#[test]
fn existing_commands_keep_their_receipt_digest_shape() {
    let value = serde_json::json!({"operation_id":uuid::Uuid::new_v4(),"action":"attack","target":null,"battle_id":null,"expected_revision":null});
    let command: Command = serde_json::from_value(value.clone()).unwrap();
    assert_eq!(serde_json::to_value(command).unwrap(), value);
}
