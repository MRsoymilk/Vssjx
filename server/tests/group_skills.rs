use uuid::Uuid;
use vssjx_server::{attributes, population, pve_rules, skills, team_rules::{Battle, Fighter}};

fn encounter(job: i16, count: usize, modern: bool) -> Battle {
    let stats = if modern { attributes::balanced_stats(job, 60, false, [0; 5]) }
        else { pve_rules::stats(job, 60, false) };
    let fighter = Fighter { id: Uuid::new_v4(), name: "群攻验证".into(), job, gender: 0,
        school: 3, level: 60, appearance: [0; 3], hp: stats.hp, mp: stats.mp, stats,
        potions: 6, effects: skills::State::new(job, 3, 60, 1), guarding: false };
    let mut enemy = population::definitions().into_iter().find(|e| e.id == "wolf_a").unwrap();
    enemy.hp = 100000; enemy.attack = 1;
    Battle::new("qingyun_trail".into(), vec![fighter], vec![enemy; count], 1000)
}

#[test]
fn dragons_hits_at_most_two_living_enemies_with_primary_first_and_one_charge() {
    let skill = "user_shuanglong_xizhu";
    for modern in [false, true] {
        for count in [1, 2, 5] {
            let mut b = encounter(2, count, modern);
            let id = b.fighters[0].id;
            let mp = b.fighters[0].mp;
            b.fighters[0].effects.proficiency.0.insert(skill.into(), 99);
            let primary = format!("m{}", count - 1);
            b.act(id, "skill", Some(&primary), Some(skill), 2000, 99).unwrap();
            let events: Vec<_> = b.events.iter().filter(|e| e.actor == id.to_string() && e.skill == skill).collect();
            assert_eq!(events.len(), count.min(2));
            assert_eq!(events[0].target, primary);
            if count > 1 { assert_eq!(events[1].target, "m0"); }
            assert!(events.iter().all(|e| e.skill_level == 6));
            assert_eq!(b.fighters[0].mp, mp - 15);
            assert_eq!(b.fighters[0].effects.proficiency.0[skill], 100);
            if modern { assert_eq!(b.fighters[0].effects.balance.as_ref().unwrap().targets, count.min(2) as i32); }
            for enemy in &b.enemies {
                if !events.iter().any(|e| e.target == enemy.slot) { assert_eq!(enemy.hp, enemy.definition.hp); }
            }
        }
    }
}

#[test]
fn dragons_skips_dead_enemies_and_rejections_leave_the_battle_unchanged() {
    let skill = "user_shuanglong_xizhu";
    let mut b = encounter(2, 5, true);
    let id = b.fighters[0].id;
    b.enemies[0].hp = 0;
    let before = serde_json::to_value(&b).unwrap();
    assert_eq!(b.act(id, "skill", Some("m0"), Some(skill), 2000, 99), Err("INVALID_BATTLE_TARGET"));
    assert_eq!(serde_json::to_value(&b).unwrap(), before);
    b.act(id, "skill", Some("m4"), Some(skill), 2000, 99).unwrap();
    let targets: Vec<_> = b.events.iter().filter(|e| e.skill == skill).map(|e| e.target.as_str()).collect();
    assert_eq!(targets, ["m4", "m1"]);
    assert_eq!(b.fighters[0].effects.remaining(skill), 2);
    let before = serde_json::to_value(&b).unwrap();
    assert_eq!(b.act(id, "skill", Some("m4"), Some(skill), b.selection_starts_ms + 1, 99), Err("SKILL_COOLDOWN"));
    assert_eq!(serde_json::to_value(&b).unwrap(), before);
    assert_eq!(skills::check(skill, 2, 3, 24).err(), Some("SKILL_LEVEL_REQUIRED"));
    assert_eq!(skills::check(skill, 0, 3, 60).err(), Some("SKILL_ROLE_MISMATCH"));
}

#[test]
fn hengsao_and_canghai_remain_full_group_attacks_without_duplicate_definitions() {
    for (skill, job, name) in [("user_hengsao_qianjun", 0, "横扫千军"), ("sheet_004", 1, "沧海明月")] {
        assert_eq!(skills::ITEMS.iter().filter(|s| s.name == name).count(), 1);
        assert_eq!(skills::item(skill).unwrap().max_targets, 0);
        for modern in [false, true] {
            let mut b = encounter(job, 5, modern);
            let id = b.fighters[0].id;
            let mp = b.fighters[0].mp;
            b.act(id, "skill", Some("m4"), Some(skill), 2000, 99).unwrap();
            let targets: Vec<_> = b.events.iter().filter(|e| e.actor == id.to_string() && e.skill == skill).map(|e| e.target.as_str()).collect();
            assert_eq!(targets, ["m0", "m1", "m2", "m3", "m4"]);
            assert_eq!(b.fighters[0].mp, mp - skills::item(skill).unwrap().mp_cost);
            assert_eq!(b.fighters[0].effects.proficiency.0[skill], 1);
        }
    }
}
