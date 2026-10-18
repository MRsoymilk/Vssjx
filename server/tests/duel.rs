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
        stats: Stats {
            hp: 300,
            mp: 300,
            attack: 100,
            defense: 5,
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
            .start(offer, a.id, [a.clone(), b.clone()], 0, now)
            .is_err()
    );
    let duel = arena.start(offer, b.id, [a, b], 0, now).unwrap();
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
            0,
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
fn turns_revisions_and_forged_battle_ids_are_fenced() {
    let (mut a, x, y, id, now) = arena();
    let mut c = command("attack");
    c.battle_id = Some(id);
    c.expected_revision = Some("0".into());
    assert_eq!(a.act(y, &c, now, 99), Err("DUEL_NOT_YOUR_TURN"));
    assert_eq!(a.battles[&id].fighters[0].hp, 300);
    let mut forged = c.clone();
    forged.battle_id = Some(Uuid::new_v4());
    assert_eq!(a.act(x, &forged, now, 99), Err("DUEL_NOT_FOUND"));
    a.act(x, &c, now, 99).unwrap();
    assert_eq!(a.battles[&id].fighters[1].hp, 205);
    assert_eq!(a.act(x, &c, now, 99), Err("DUEL_STALE_REVISION"));
    assert_eq!(a.battles[&id].fighters[1].hp, 205);
    c.expected_revision = Some("1".into());
    a.act(y, &c, now, 99).unwrap();
    assert_eq!(a.battles[&id].fighters[0].hp, 205);
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
fn surrender_timeout_and_disconnect_release_both_players() {
    for mode in ["flee", "timeout", "disconnect"] {
        let (mut a, x, y, id, now) = arena();
        if mode == "flee" {
            let mut c = command("flee");
            c.battle_id = Some(id);
            c.expected_revision = Some("0".into());
            a.act(y, &c, now, 0).unwrap();
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
        assert!(!a.active(x) && !a.active(y));
        assert!(a.battles[&id].winner.is_some());
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
        a.start(offer, y.id, [x, y], 0, now + Duration::from_secs(31)),
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
    assert_eq!(a.act(x, &c, now, 0), Err("SKILL_ROLE_MISMATCH"));
    c.skill = Some("legacy_0".into());
    a.act(x, &c, now, 0).unwrap();
    assert!(a.battles[&id].fighters[0].mp < 300);
    let battle = a.battles.get_mut(&id).unwrap();
    battle.fighters[0].effects.reflect_physical = 2;
    battle.fighters[0].effects.physical_percent = 100;
    let old = battle.fighters[1].hp;
    let mut attack = command("attack");
    attack.battle_id = Some(id);
    attack.expected_revision = Some("1".into());
    a.act(y, &attack, now, 99).unwrap();
    assert!(a.battles[&id].fighters[1].hp < old);
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
        let id = a
            .start(offer, y.id, [x.clone(), y.clone()], 0, now)
            .unwrap();
        let mut c = command("flee");
        c.battle_id = Some(id);
        c.expected_revision = Some("0".into());
        a.act(x.id, &c, now, 0).unwrap();
        assert_eq!(a.battles.len(), 1);
    }
}
