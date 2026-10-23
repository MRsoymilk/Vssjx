use serde_json::json;
use std::time::{Duration, Instant};
use uuid::Uuid;
use vssjx_server::{
    duel::{Arena, Command, Fighter},
    pve_rules::Stats,
    skills,
};
fn fighter(name: &str, job: i16) -> Fighter {
    Fighter {
        id: Uuid::new_v4(),
        name: name.into(),
        job,
        gender: 0,
        school: 3,
        level: 50,
        speed: 100,
        stats: Stats {
            hp: 300,
            mp: 300,
            attack: 100,
            defense: 5,
            attributes: [0; 5],
            balance: None,
        },
        appearance: [1, 0, 0],
        hp: 300,
        mp: 300,
        effects: skills::State::new(job, 3, 50, 50),
        guarding: false,
    }
}
fn command(action: &str) -> Command {
    Command {
        request_id: Uuid::new_v4(),
        action: action.into(),
        target: None,
        invite_id: None,
        battle_id: None,
        expected_revision: None,
        skill: None,
    }
}
fn arena() -> (Arena, Uuid, Uuid, Uuid, Instant) {
    let now = Instant::now();
    let a = fighter("剑侠甲", 0);
    let b = fighter("剑侠乙", 1);
    let ids = [a.id, b.id];
    let mut arena = Arena::default();
    let offer = arena
        .invite(a.id, b.id, a.name.clone(), b.name.clone(), now)
        .unwrap();
    assert!(!arena.active(a.id) && !arena.active(b.id));
    assert!(
        arena
            .start(offer, a.id, [a.clone(), b.clone()], now)
            .is_err()
    );
    let duel = arena.start(offer, b.id, [a, b], now).unwrap();
    (arena, ids[0], ids[1], duel, now)
}
#[test]
fn only_explicit_recipient_can_start_and_both_are_busy() {
    let (mut a, x, y, id, now) = arena();
    assert!(a.active(x) && a.active(y));
    assert!(
        a.invite(x, Uuid::new_v4(), "甲甲".into(), "丙丙".into(), now)
            .is_err()
    );
    assert_eq!(a.battles[&id].fighters[0].hp, 300);
    assert!(
        a.start(
            Uuid::new_v4(),
            y,
            [fighter("甲甲", 0), fighter("乙乙", 1)],
            now
        )
        .is_err()
    );
}
#[test]
fn no_self_invites_and_one_pending_offer_per_player() {
    let mut a = Arena::default();
    let now = Instant::now();
    let x = Uuid::new_v4();
    let y = Uuid::new_v4();
    assert_eq!(
        a.invite(x, x, "甲甲".into(), "甲甲".into(), now),
        Err("DUEL_SELF")
    );
    a.invite(x, y, "甲甲".into(), "乙乙".into(), now).unwrap();
    assert_eq!(
        a.invite(y, x, "乙乙".into(), "甲甲".into(), now),
        Err("DUEL_BUSY")
    );
    assert_eq!(
        a.invite(Uuid::new_v4(), y, "丙丙".into(), "乙乙".into(), now),
        Err("DUEL_BUSY")
    );
}
#[test]
fn concurrent_choices_are_hidden_and_settle_only_after_both_commit() {
    let (mut a, x, y, id, now) = arena();
    let mut c = command("attack");
    c.battle_id = Some(id);
    c.expected_revision = Some("0".into());
    let mut forged = c.clone();
    forged.battle_id = Some(Uuid::new_v4());
    assert_eq!(a.act(x, &forged, now, [99; 3]), Err("DUEL_NOT_FOUND"));
    a.act(y, &c, now, [99; 3]).unwrap();
    assert_eq!(a.battles[&id].fighters[0].hp, 300);
    assert_eq!(a.battles[&id].decision_revision, 0);
    assert_eq!(a.act(y, &c, now, [99; 3]), Err("DUEL_ALREADY_SUBMITTED"));
    let mine = a.packet(x, None, now).unwrap().1["battle"].clone();
    let other = a.packet(y, None, now).unwrap().1["battle"].clone();
    assert!(mine["your_choice"].is_null());
    assert!(mine.get("choices").is_none());
    assert_eq!(other["your_choice"]["action"], "attack");
    assert_eq!(mine["submitted"], json!([false, true]));
    a.act(x, &c, now, [99; 3]).unwrap();
    assert_eq!(a.battles[&id].events.len(), 2);
    assert_eq!(a.battles[&id].fighters[0].hp, 205);
    assert_eq!(a.battles[&id].fighters[1].hp, 185); // 95 direct + defender's 100 × 20% reflection
    assert_eq!(a.act(x, &c, now, [99; 3]), Err("DUEL_RESOLVING"));
    a.tick(
        now + Duration::from_secs(4),
        &std::collections::HashMap::from([(x, (true, true)), (y, (true, true))]),
    );
    assert_eq!(a.battles[&id].round, 2);
    assert_eq!(
        a.act(y, &c, now + Duration::from_secs(4), [99; 3]),
        Err("DUEL_STALE_REVISION")
    );
}
#[test]
fn duplicates_and_conflicting_request_ids_cannot_apply_twice() {
    let (mut a, x, _, id, now) = arena();
    let mut c = command("attack");
    c.battle_id = Some(id);
    c.expected_revision = Some("0".into());
    let result = json!({"ok":true});
    a.remember(x, &c, result.clone());
    assert_eq!(a.cached(x, &c), Some(result));
    c.action = "guard".into();
    assert_eq!(a.cached(x, &c).unwrap()["code"], "DUEL_ID_CONFLICT");
    assert!(a.admit(x, now));
    assert!(!a.admit(x, now + Duration::from_millis(50)));
}
#[test]
fn surrender_and_disconnect_release_both_players_but_timeout_defaults_to_guard() {
    for mode in ["flee", "timeout", "disconnect"] {
        let (mut a, x, y, id, now) = arena();
        if mode == "flee" {
            let mut c = command("flee");
            c.battle_id = Some(id);
            c.expected_revision = Some("0".into());
            a.act(y, &c, now, [0; 3]).unwrap();
        } else {
            let mut online =
                std::collections::HashMap::from([(x, (true, true)), (y, (true, true))]);
            if mode == "disconnect" {
                online.remove(&x);
            }
            a.tick(
                now + Duration::from_secs(if mode == "timeout" { 31 } else { 1 }),
                &online,
            );
        }
        if mode == "timeout" {
            assert!(a.active(x) && a.active(y));
            assert!(a.battles[&id].events.iter().all(|e| e.action == "guard"));
        } else {
            assert!(!a.active(x) && !a.active(y));
            assert!(a.battles[&id].winner.is_some());
        }
    }
}
#[test]
fn offer_expiry_cannot_start_a_fight() {
    let now = Instant::now();
    let x = fighter("甲甲", 0);
    let y = fighter("乙乙", 1);
    let mut a = Arena::default();
    let offer = a
        .invite(x.id, y.id, x.name.clone(), y.name.clone(), now)
        .unwrap();
    assert_eq!(
        a.start(offer, y.id, [x, y], now + Duration::from_secs(31)),
        Err("DUEL_INVITE_EXPIRED")
    );
    assert!(a.battles.is_empty());
}
#[test]
fn skills_use_server_eligibility_mana_and_reflection() {
    let (mut a, x, y, id, now) = arena();
    let mut c = command("skill");
    c.skill = Some("legacy_2".into());
    c.battle_id = Some(id);
    c.expected_revision = Some("0".into());
    assert_eq!(a.act(x, &c, now, [0; 3]), Err("SKILL_ROLE_MISMATCH"));
    c.skill = Some("legacy_0".into());
    a.act(x, &c, now, [0; 3]).unwrap();
    assert_eq!(
        a.battles[&id].fighters[0].mp, 300,
        "A committed skill spends no mana before resolution"
    );
    let mut guard = command("guard");
    guard.battle_id = Some(id);
    guard.expected_revision = Some("0".into());
    a.act(y, &guard, now, [0; 3]).unwrap();
    assert!(a.battles[&id].fighters[0].mp < 300);
    let now = now + Duration::from_secs(4);
    a.tick(
        now,
        &std::collections::HashMap::from([(x, (true, true)), (y, (true, true))]),
    );
    let battle = a.battles.get_mut(&id).unwrap();
    battle.fighters[0].effects.reflect_physical = 2;
    battle.fighters[0].effects.physical_percent = 100;
    let old = battle.fighters[1].hp;
    let mut attack = command("attack");
    attack.battle_id = Some(id);
    attack.expected_revision = Some("1".into());
    a.act(y, &attack, now, [99; 3]).unwrap();
    guard.expected_revision = Some("1".into());
    a.act(x, &guard, now, [99; 3]).unwrap();
    assert!(a.battles[&id].fighters[1].hp < old);
}
#[test]
fn physical_and_magical_reflection_use_defenders_attack_in_duels() {
    for (magical,active) in [(false,false),(true,false),(false,true),(true,true)] {
        for attack in [50,200] {
            let (mut a,x,y,id,now)=arena();
            let b=a.battles.get_mut(&id).unwrap();
            b.fighters[0].stats.attack=120;b.fighters[0].speed=200;
            b.fighters[1].stats.attack=attack;
            if magical{b.fighters[1].job=2;b.fighters[1].effects=skills::State::new(2,3,50,50);}
            let mut guard=command("guard");guard.battle_id=Some(id);guard.expected_revision=Some("0".into());
            if active{guard.action="skill".into();guard.skill=Some(if magical{"sheet_033"}else{"sheet_011"}.into());}
            a.act(x,&guard,now,[99;3]).unwrap();
            let mut hit=command(if magical{"skill"}else{"attack"});hit.battle_id=Some(id);hit.expected_revision=Some("0".into());
            if magical{hit.skill=Some("legacy_2".into());}
            a.act(y,&hit,now,[99;3]).unwrap();
            let event=a.battles[&id].events.iter().find(|e|e.actor==y).unwrap();
            assert_eq!(event.reflected,if active{72}else{24},"defender 120 × own reflection ratio, independent of attacker {attack}");
        }
    }
}

#[test]
fn command_schema_rejects_damage_injection() {
    assert!(
        serde_json::from_value::<Command>(
            json!({"request_id":Uuid::new_v4(),"action":"attack","hp":999})
        )
        .is_err()
    );
    assert!(!command("accept").valid());
    assert!(!command("buy").valid());
}

#[test]
fn repeated_sparring_keeps_only_referenced_battle_history() {
    let mut a = Arena::default();
    let x = fighter("甲甲", 0);
    let y = fighter("乙乙", 1);
    let now = Instant::now();
    for _ in 0..100 {
        let offer = a
            .invite(x.id, y.id, x.name.clone(), y.name.clone(), now)
            .unwrap();
        let id = a.start(offer, y.id, [x.clone(), y.clone()], now).unwrap();
        let mut c = command("flee");
        c.battle_id = Some(id);
        c.expected_revision = Some("0".into());
        a.act(x.id, &c, now, [0; 3]).unwrap();
        assert_eq!(a.battles.len(), 1);
    }
}

#[test]
fn agility_determines_initiative_instead_of_arrival_order_and_ko_cancels_the_slower_choice() {
    for last in [0, 1] {
        let (mut a, x, y, id, now) = arena();
        let b = a.battles.get_mut(&id).unwrap();
        b.fighters[0].speed = 110;
        b.fighters[1].speed = 150;
        b.fighters[0].hp = 90;
        let mut c = command("attack");
        c.battle_id = Some(id);
        c.expected_revision = Some("0".into());
        let ids = [x, y];
        a.act(ids[1 - last], &c, now, [0; 3]).unwrap();
        a.act(ids[last], &c, now, [0; 3]).unwrap();
        let b = &a.battles[&id];
        assert_eq!(b.events.len(), 1);
        assert_eq!(b.events[0].actor, y);
        assert_eq!(b.winner, Some(y));
        assert_eq!(
            b.fighters[1].hp, 280,
            "Passive reflection still applies to the faster attacker"
        );
    }
}
#[test]
fn tied_speed_uses_server_tiebreak_and_slow_guard_protects_for_the_whole_round() {
    for tie in [0, 1] {
        let (mut a, x, y, id, now) = arena();
        let mut c = command("attack");
        c.battle_id = Some(id);
        c.expected_revision = Some("0".into());
        a.act(x, &c, now, [tie, 99, 99]).unwrap();
        a.act(y, &c, now, [tie, 99, 99]).unwrap();
        assert_eq!(a.battles[&id].events[0].actor, [x, y][tie as usize]);
    }
    let (mut a, x, y, id, now) = arena();
    a.battles.get_mut(&id).unwrap().fighters[1].speed = 200;
    let mut c = command("attack");
    c.battle_id = Some(id);
    c.expected_revision = Some("0".into());
    a.act(y, &c, now, [99; 3]).unwrap();
    c.action = "guard".into();
    a.act(x, &c, now, [99; 3]).unwrap();
    assert_eq!(a.battles[&id].fighters[0].hp, 253);
}
#[test]
fn speed_is_loaded_from_authoritative_allocated_agility() {
    let id = Uuid::new_v4();
    let value = json!({"state":{"character":{"id":id,"display_name":"青云客","job":0,"gender":0,"school":3,"level":20},"stats":{"hp":300,"mp":100,"attack":80,"defense":20},"attributes":{"allocated":[0,0,0,75,0]}}});
    assert_eq!(
        Fighter::from_snapshot(&value, [1, 0, 0]).unwrap().speed,
        175
    );
    let mut corrupt = value;
    corrupt["state"]["attributes"]["allocated"][3] = json!(9999);
    assert!(Fighter::from_snapshot(&corrupt, [1, 0, 0]).is_err());
}
#[test]
fn faster_seal_or_mana_drain_rechecks_the_committed_slower_skill_without_spending_mana() {
    for effect in ["silence", "mana_steal"] {
        let s = skills::ITEMS
            .iter()
            .find(|s| s.active && s.effect == effect)
            .unwrap();
        let (mut a, x, y, id, now) = arena();
        let b = a.battles.get_mut(&id).unwrap();
        b.fighters[0].job = s.job;
        b.fighters[0].speed = 200;
        b.fighters[1].mp = 9;
        let mut c = command("skill");
        c.battle_id = Some(id);
        c.expected_revision = Some("0".into());
        c.skill = Some("legacy_1".into());
        a.act(y, &c, now, [0; 3]).unwrap();
        c.skill = Some(s.id.clone());
        a.act(x, &c, now, [0; 3]).unwrap();
        let b = &a.battles[&id];
        assert_eq!(b.events[1].action, "fizzle");
        assert!(b.events[1].skill.is_empty());
        assert!(b.fighters[1].mp <= 9);
    }
}
#[test]
fn deadline_does_not_extend_after_first_choice_and_timeout_preserves_it() {
    let (mut a, x, y, id, now) = arena();
    let mut c = command("attack");
    c.battle_id = Some(id);
    c.expected_revision = Some("0".into());
    let deadline = a.battles[&id].deadline;
    a.act(x, &c, now + Duration::from_secs(29), [99; 3])
        .unwrap();
    assert_eq!(a.battles[&id].deadline, deadline);
    assert_eq!(
        a.act(y, &c, deadline, [99; 3]),
        Err("DUEL_DECISION_EXPIRED")
    );
    a.tick(
        deadline,
        &std::collections::HashMap::from([(x, (true, true)), (y, (true, true))]),
    );
    let b = &a.battles[&id];
    assert_eq!(b.fighters[1].hp, 253);
    assert_eq!(b.fighters[0].hp, 300);
    assert_eq!(b.events.iter().filter(|e| e.action == "attack").count(), 1);
}
#[test]
fn afk_rounds_are_bounded_and_no_new_round_opens_during_playback() {
    let (mut a, x, y, id, mut now) = arena();
    let online = std::collections::HashMap::from([(x, (true, true)), (y, (true, true))]);
    for round in 1..=50 {
        now += Duration::from_secs(31);
        a.tick(now, &online);
        assert_eq!(a.battles[&id].round, round);
        if round < 50 {
            a.tick(now + Duration::from_secs(3), &online);
            assert_eq!(a.battles[&id].round, round);
            now += Duration::from_secs(4);
            a.tick(now, &online);
        }
    }
    assert!(!a.active(x));
    assert_eq!(a.battles[&id].reason, "round_limit");
    assert_eq!(a.battles[&id].winner, None);
}
