use serde_json::{Value, json};
use vssjx_server::combat_balance::{self as b, Hit};

#[test]
fn shared_vectors_match_the_candidate_contract() {
    let v: Value =
        serde_json::from_str(include_str!("../../shared/data/balance-v1-vectors.json")).unwrap();
    for row in v["stats"].as_array().unwrap() {
        let points = serde_json::from_value(row["points"].clone()).unwrap();
        assert_eq!(
            serde_json::to_value(
                b::profile(
                    row["job"].as_i64().unwrap(),
                    row["level"].as_i64().unwrap(),
                    points
                )
                .unwrap()
            )
            .unwrap(),
            row["expected"]
        );
    }
    for row in v["damage"].as_array().unwrap() {
        let hit: Hit = serde_json::from_value(row["input"].clone()).unwrap();
        assert_eq!(
            serde_json::to_value(b::damage(&hit).unwrap()).unwrap(),
            row["expected"]
        );
    }
    for row in v["ratings"].as_array().unwrap() {
        assert_eq!(
            json!(
                b::critical_chance(
                    row["level"].as_i64().unwrap(),
                    row["rating"].as_i64().unwrap(),
                    row["bonus_bp"].as_i64().unwrap()
                )
                .unwrap()
            ),
            row["expected"]
        );
    }
    for row in v["hit"].as_array().unwrap() {
        assert_eq!(
            json!(
                b::hit_chance(
                    row["level"].as_i64().unwrap(),
                    row["hit"].as_i64().unwrap(),
                    row["evasion"].as_i64().unwrap()
                )
                .unwrap()
            ),
            row["expected"]
        );
    }
    for row in v["aoe"].as_array().unwrap() {
        assert_eq!(
            json!(
                b::aoe_coefficient(
                    row["coefficient_bp"].as_i64().unwrap(),
                    row["targets"].as_i64().unwrap()
                )
                .unwrap()
            ),
            row["expected"]
        );
    }
    for row in v["boss"].as_array().unwrap() {
        assert_eq!(
            json!(
                b::boss_hp(
                    row["hp"].as_i64().unwrap(),
                    row["members"].as_i64().unwrap()
                )
                .unwrap()
            ),
            row["expected"]
        );
    }
}

#[test]
fn invalid_values_never_wrap_or_silently_grant_points() {
    assert!(b::profile(-1, 1, [0; 5]).is_err());
    assert!(b::profile(3, 1, [0; 5]).is_err());
    for l in [-1, 0, 61, i64::MAX] {
        assert!(b::profile(0, l, [0; 5]).is_err());
        assert!(
            b::damage(&Hit {
                level: l,
                ..Default::default()
            })
            .is_err()
        );
    }
    assert!(b::profile(0, 1, [6, 0, 0, 0, 0]).is_err());
    assert!(b::profile(0, 60, [-1, 0, 0, 0, 0]).is_err());
    for n in [-1, 1000001, i64::MAX] {
        assert!(
            b::damage(&Hit {
                attack: n,
                ..Default::default()
            })
            .is_err()
        );
        assert!(b::critical_chance(60, n, 0).is_err());
    }
    assert!(
        b::damage(&Hit {
            coefficient_bp: 30001,
            ..Default::default()
        })
        .is_err()
    );
    for n in [0, 6, i64::MAX] {
        assert!(b::boss_hp(1000, n).is_err());
        assert!(b::aoe_coefficient(8000, n).is_err());
    }
    assert!(serde_json::from_value::<Hit>(json!({"reward":999})).is_err());
}

#[test]
fn defensive_and_rating_curves_are_monotonic_and_bounded() {
    for l in 1..=60 {
        let mut previous = 1000;
        for defense in (0..=10000).step_by(25) {
            let hit = Hit {
                attack: 1000,
                defense,
                level: l,
                ..Default::default()
            };
            let d = b::damage(&hit).unwrap();
            assert!((400..=previous).contains(&d.damage));
            previous = d.damage;
            assert_eq!(
                b::damage(&Hit {
                    guarding: true,
                    ..hit
                })
                .unwrap()
                .damage,
                d.damage / 2
            );
        }
        let mut previous = 0;
        for rating in (0..=10000).step_by(25) {
            let chance = b::critical_chance(l, rating, 0).unwrap();
            assert!((previous.max(500)..=5000).contains(&chance));
            previous = chance;
            assert!((8000..=9900).contains(&b::hit_chance(l, 0, rating).unwrap()));
        }
        for job in 0..3 {
            assert_eq!(
                b::profile(job, l, [l * 5, 0, 0, 0, 0]).unwrap().available,
                0
            );
        }
    }
}

#[test]
fn aoe_and_party_budget_do_not_double_multiply_actor_count() {
    for count in 1..=5 {
        assert!(b::aoe_coefficient(8000, count).unwrap() * count <= 24000);
    }
    assert_eq!(b::boss_hp(1000, 5).unwrap(), 4200);
    // Accepted input extremes remain bounded in i64, even in debug builds.
    assert!(
        b::damage(&Hit {
            attack: 1000000,
            defense: 1000000,
            level: 60,
            coefficient_bp: 30000,
            increased_bp: 1000000,
            critical: true,
            critical_multiplier_bp: 1000000,
            legendary_bp: 1000000,
            ..Default::default()
        })
        .unwrap()
        .damage
            > 0
    );
}
