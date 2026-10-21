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
fn complete(b: &mut Battle, now: i64) {
    let ids: Vec<_> = b
        .fighters
        .iter()
        .filter(|f| f.hp > 0 && !b.commands.contains_key(&f.id))
        .map(|f| f.id)
        .collect();
    for id in ids {
        b.act(id, "guard", None, None, now, 99).unwrap();
    }
}
#[test]
fn lone_participant_keeps_base_stats_and_can_complete_rounds() {
    let f = fighter(1, 20);
    let original = population::definitions()
        .into_iter()
        .find(|d| d.kind != "npc")
        .unwrap();
    let mut b = Battle::new(
        "qingyun_trail".into(),
        vec![f],
        vec![original.clone()],
        1000,
    );
    assert_eq!(b.enemies.len(), 1);
    assert_eq!(
        (
            b.enemies[0].hp,
            b.enemies[0].definition.attack,
            b.enemies[0].definition.defense
        ),
        (original.hp, original.attack, original.defense)
    );
    let me = b.fighters[0].id;
    b.act(me, "guard", None, None, 2000, 99).unwrap();
    assert_eq!(b.turn, 0);
    assert_eq!(b.round, 2);
    assert_eq!(b.events.len(), 2);
    assert_eq!(b.events[1].target, me.to_string());
    b.enemies[0].hp = 1;
    b.act(me, "attack", Some("m0"), None, b.selection_starts_ms, 99)
        .unwrap();
    assert_eq!(b.outcome, "victory");
    assert_eq!(b.events.len(), 1);
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
fn outsiders_and_dead_targets_cannot_spend_mana() {
    let mut b = encounter();
    let before = serde_json::to_value(&b).unwrap();
    assert_eq!(
        b.act(Uuid::new_v4(), "attack", Some("m0"), None, 2000, 0),
        Err("TEAM_NOT_PARTICIPATING")
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
    complete(&mut b, 3000);
    assert!(b.enemies.iter().all(|e| e.hp < 1000));
    assert_eq!(
        b.fighters[0].mp,
        mp - skills::item("sheet_004").unwrap().mp_cost
    );
    assert_eq!(
        b.events
            .iter()
            .filter(|e| e.actor == id.to_string())
            .count(),
        3
    );
}
#[test]
fn failures_and_potions_are_authoritative() {
    let mut b = encounter();
    let id = b.fighters[0].id;
    assert_eq!(b.act(id, "potion", None, None, 2000, 0), Err("HP_FULL"));
    b.fighters[0].hp -= 50;
    let count = b.fighters[0].potions;
    b.act(id, "potion", None, None, 2000, 0).unwrap();
    complete(&mut b, 3000);
    assert_eq!(b.fighters[0].potions, count - 1);
    assert!(
        b.events
            .iter()
            .any(|e| e.actor == id.to_string() && e.action == "potion" && e.healed == 45)
    );
}
#[test]
fn killed_monsters_never_take_a_turn() {
    let mut b = encounter();
    b.enemies[0].hp = 0;
    b.enemies[1].hp = 0;
    b.enemies[2].hp = 0;
    b.act(b.fighters[0].id, "guard", None, None, 2000, 99)
        .unwrap();
    complete(&mut b, 3000);
    assert_eq!(b.outcome, "victory");
    assert!(b.events.iter().all(|e| !e.actor.starts_with('m')));
}
#[test]
fn group_support_buffs_living_allies_and_charges_only_caster() {
    let mut b = encounter();
    b.fighters = vec![fighter(2, 35), fighter(1, 35)];
    for f in &mut b.fighters {
        f.hp -= 100;
    }
    let before = b.fighters.iter().map(|f| f.mp).collect::<Vec<_>>();
    b.act(b.fighters[0].id, "skill", None, Some("sheet_041"), 2000, 99)
        .unwrap();
    complete(&mut b, 3000);
    assert!(b.fighters.iter().all(|f| f.effects.regen > 0));
    assert_eq!(
        b.fighters[0].mp,
        before[0] - skills::item("sheet_041").unwrap().mp_cost
    );
    assert_eq!(
        b.fighters[1].mp,
        (before[1] + 5).min(b.fighters[1].stats.mp)
    );
    assert_eq!(b.events.iter().filter(|e| e.action == "skill").count(), 2);
}
#[test]
fn enemy_debuffs_remain_on_the_selected_monster() {
    let s = skills::ITEMS
        .iter()
        .find(|s| s.effect == "bleed" && s.active)
        .unwrap();
    let mut b = encounter();
    b.fighters[0] = fighter(s.job, 60);
    for e in &mut b.enemies {
        e.hp = 10000;
        e.definition.hp = 10000;
    }
    b.act(b.fighters[0].id, "skill", Some("m1"), Some(&s.id), 2000, 0)
        .unwrap();
    b.act(b.fighters[1].id, "guard", None, None, 3000, 0)
        .unwrap();
    assert_eq!(b.enemies[1].effects.enemy_bleed, (s.duration - 1).max(0));
    assert!(b.enemies[1].effects.bleed_damage > 0);
    assert_eq!(b.enemies[0].effects.enemy_bleed, 0);
    assert_eq!(b.fighters[0].effects.enemy_bleed, 0);
}
#[test]
fn whole_round_uses_one_deadline_and_accepts_any_player_first() {
    let mut b = encounter();
    let deadline = b.deadline_ms;
    let hp = b.enemies[0].hp;
    b.act(b.fighters[1].id, "attack", Some("m0"), None, 2000, 99)
        .unwrap();
    assert_eq!(b.deadline_ms, deadline);
    assert_eq!(b.enemies[0].hp, hp);
    assert!(b.events.is_empty());
    assert_eq!(
        b.act(b.fighters[1].id, "guard", None, None, 3000, 99),
        Err("TEAM_COMMAND_LOCKED")
    );
    b.act(b.fighters[0].id, "guard", None, None, 4000, 99)
        .unwrap();
    assert_eq!(b.round, 2);
    assert!(b.commands.is_empty());
    assert_eq!(b.events[0].actor, b.fighters[0].id.to_string());
    assert_eq!(b.events[1].actor, b.fighters[1].id.to_string());
    assert!(b.events[2..].iter().all(|e| e.actor.starts_with('m')));
    assert_eq!(b.deadline_ms - b.selection_starts_ms, 30_000);
    assert_eq!(
        b.act(b.fighters[0].id, "guard", None, None, 4001, 99),
        Err("TEAM_PLAYBACK_ACTIVE")
    );
}
#[test]
fn actual_playback_completion_opens_a_full_window_without_estimated_wait() {
    let mut b = encounter();
    complete(&mut b, 2000);
    let original_start = b.selection_starts_ms;
    let round = b.round_revision;
    let events = serde_json::to_value(&b.events).unwrap();
    b.acknowledge_playback(b.fighters[0].id, round, 3000).unwrap();
    assert_eq!(b.selection_starts_ms, original_start);
    let after_first = b.revision;
    b.acknowledge_playback(b.fighters[0].id, round, 3100).unwrap();
    assert_eq!(b.revision, after_first);
    // A process restart preserves the first member's acknowledgement.
    b = serde_json::from_value(serde_json::to_value(&b).unwrap()).unwrap();
    b.acknowledge_playback(b.fighters[1].id, round, 4000).unwrap();
    assert!(b.selection_starts_ms < original_start);
    assert_eq!(b.selection_starts_ms, 4000);
    assert_eq!(b.deadline_ms, 34000);
    assert_eq!(serde_json::to_value(&b.events).unwrap(), events);
    b.acknowledge_playback(b.fighters[1].id, round, 5000).unwrap();
    assert_eq!(b.deadline_ms, 34000);
    b.act(b.fighters[0].id, "guard", None, None, 4001, 99).unwrap();
}
#[test]
fn playback_acknowledgements_are_fenced_to_living_fighters_and_current_round() {
    let mut b = encounter();
    assert_eq!(b.acknowledge_playback(b.fighters[0].id, 0, 1001), Err("STALE_BATTLE"));
    complete(&mut b, 2000);
    let round = b.round_revision;
    assert_eq!(b.acknowledge_playback(Uuid::new_v4(), round, 3000), Err("TEAM_NOT_PARTICIPATING"));
    assert_eq!(b.acknowledge_playback(b.fighters[0].id, round - 1, 3000), Err("STALE_BATTLE"));
    b.fighters[1].hp = 0;
    assert_eq!(b.acknowledge_playback(b.fighters[1].id, round, 3000), Err("TEAM_NOT_PARTICIPATING"));
    b.acknowledge_playback(b.fighters[0].id, round, 4000).unwrap();
    assert_eq!(b.selection_starts_ms, 4000);
    complete(&mut b, 5000);
    assert!(b.playback_ready.is_empty());
    assert_eq!(b.acknowledge_playback(b.fighters[0].id, round, 6000), Err("STALE_BATTLE"));
}
#[test]
fn older_or_disconnected_clients_keep_bounded_playback_fallback() {
    let mut b = encounter();
    complete(&mut b, 2000);
    let start = b.selection_starts_ms;
    let deadline = b.deadline_ms;
    b.acknowledge_playback(b.fighters[0].id, b.round_revision, 3000).unwrap();
    assert!(!b.expire(start, 99));
    b.act(b.fighters[1].id, "guard", None, None, start, 99).unwrap();
    b.acknowledge_playback(b.fighters[0].id, b.round_revision, start + 1).unwrap();
    assert_eq!(b.deadline_ms, deadline);
    assert!(b.expire(deadline, 99));
}
#[test]
fn timeout_executes_every_missing_player_and_monster_once() {
    let mut b = encounter();
    b.act(b.fighters[1].id, "attack", Some("m0"), None, 2000, 99)
        .unwrap();
    assert!(!b.expire(b.deadline_ms - 1, 99));
    assert_eq!(
        b.act(b.fighters[0].id, "guard", None, None, b.deadline_ms, 99),
        Err("TEAM_ROUND_EXPIRED")
    );
    assert!(b.expire(b.deadline_ms, 99));
    assert_eq!(b.round, 2);
    assert_eq!(b.events[0].action, "guard");
    assert_eq!(b.events[1].action, "attack");
    assert_eq!(
        b.events.iter().filter(|e| e.actor.starts_with('m')).count(),
        3
    );
    assert!(!b.expire(b.selection_starts_ms, 99));
}
#[test]
fn dead_participants_do_not_hold_collection_and_queued_targets_retarget() {
    let mut b = encounter();
    b.enemies[0].hp = 1;
    let id = b.fighters[1].id;
    b.act(id, "attack", Some("m0"), None, 2000, 99).unwrap();
    b.act(b.fighters[0].id, "attack", Some("m0"), None, 3000, 99)
        .unwrap();
    assert_eq!(b.events[1].target, "m1");
    b.fighters[1].hp = 0;
    assert_eq!(
        b.act(id, "guard", None, None, b.selection_starts_ms, 99),
        Err("TEAM_NOT_PARTICIPATING")
    );
    b.act(
        b.fighters[0].id,
        "guard",
        None,
        None,
        b.selection_starts_ms,
        99,
    )
    .unwrap();
    assert_eq!(b.round, 3);
}
#[test]
fn queued_intents_and_deadline_survive_serialization() {
    let mut b = encounter();
    b.act(b.fighters[1].id, "guard", None, None, 2000, 99)
        .unwrap();
    let mut restored: Battle = serde_json::from_value(serde_json::to_value(&b).unwrap()).unwrap();
    assert_eq!(restored.deadline_ms, b.deadline_ms);
    assert_eq!(restored.commands.len(), 1);
    restored
        .act(restored.fighters[0].id, "guard", None, None, 3000, 99)
        .unwrap();
    assert_eq!(restored.round, 2);
}
#[test]
fn defense_does_not_expire_before_the_enemy_phase() {
    let mut b = encounter();
    b.fighters[0].effects.defense = 1;
    b.fighters[0].effects.defense_percent = 50;
    b.act(b.fighters[0].id, "guard", None, None, 2000, 99)
        .unwrap();
    assert_eq!(b.fighters[0].effects.defense, 1);
    b.act(b.fighters[1].id, "guard", None, None, 3000, 99)
        .unwrap();
    assert_eq!(b.fighters[0].effects.defense, 0);
}
