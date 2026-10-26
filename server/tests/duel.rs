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
    assert_eq!(a.battles[&id].fighters[1].hp, 105); // 95 direct + defender's 100 physical attack
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
            assert_eq!(event.reflected,120,"defender 120 × own reflection ratio, independent of attacker {attack}");
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
            b.fighters[1].hp, 200,
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

fn revised_arena(jobs: [i16; 2], first: usize) -> (Arena, Uuid, Uuid, Uuid, Instant) {
    let now = Instant::now();
    let fighters = jobs.map(|job| {
        let mut stats = vssjx_server::attributes::balanced_stats(job, 60, false, [0; 5]);
        stats.hp = 10000;
        stats.attack = 500;
        let b = stats.balance.as_mut().unwrap();
        b.physical_attack = 500;
        b.magic_attack = 500;
        Fighter::from_snapshot(&json!({"state":{"stats":stats,"attributes":{"allocated":[0,0,0,0,0]},
            "character":{"id":Uuid::new_v4(),"display_name":"切磋回归","job":job,"gender":0,"school":3,"level":60}}}), [1,0,0]).unwrap()
    });
    let [x, y] = fighters.each_ref().map(|f| f.id);
    let mut arena = Arena::default();
    let offer = arena.invite(x, y, fighters[0].name.clone(), fighters[1].name.clone(), now).unwrap();
    let id = arena.start(offer, y, fighters, now).unwrap();
    arena.battles.get_mut(&id).unwrap().fighters[first].speed = 300;
    (arena, x, y, id, now)
}
fn paired_actions(arena: &mut Arena, id: Uuid, now: Instant, choices: [(&str, Option<&str>); 2]) {
    let ids = arena.battles[&id].fighters.each_ref().map(|f| f.id);
    let revision = arena.battles[&id].decision_revision.to_string();
    for (who, (action, skill)) in ids.into_iter().zip(choices) {
        let mut c = command(action);
        c.battle_id = Some(id);c.expected_revision = Some(revision.clone());c.skill = skill.map(str::to_owned);
        arena.act(who, &c, now, [0, 0, 99]).unwrap();
    }
}
#[test]
fn poison_is_unreflectable_and_ticks_full_caster_attack_even_against_guard_and_reduction(){
    for _ in 0..40{
        let(mut arena,x,_,id,now)=revised_arena([1,0],0);
        let b=arena.battles.get_mut(&id).unwrap();
        b.fighters[1].stats.balance.as_mut().unwrap().reduction_bp=2500;
        let before=[b.fighters[0].hp,b.fighters[1].hp];let attack=b.fighters[0].stats.attack;
        paired_actions(&mut arena,id,now,[("skill",Some("sheet_052")),("guard",None)]);
        let b=&arena.battles[&id];let event=b.events.iter().find(|e|e.actor==x).unwrap();
        if event.missed{continue;}
        assert_eq!(event.reflected,0);assert_eq!(b.fighters[0].hp,before[0]);
        assert_eq!(b.fighters[1].hp,before[1]-event.damage-attack);
        assert_eq!(b.fighters[0].effects.poison_damage,attack);assert!(b.fighters[0].effects.poison_fixed);
        return;
    }
    panic!("Expected an ordinary landed poison cast");
}
#[test]
fn attack_based_heals_keep_the_full_attack_amount_in_duels(){
    for skill in ["sheet_039","sheet_041"]{
        let(mut arena,_,_,id,now)=revised_arena([2,1],0);
        let b=arena.battles.get_mut(&id).unwrap();b.fighters[0].hp=1;
        let attack=b.fighters[0].stats.balance.unwrap().magic_attack;
        paired_actions(&mut arena,id,now,[("skill",Some(skill)),("guard",None)]);
        let b=&arena.battles[&id];assert_eq!(b.fighters[0].hp,1+attack);
        assert_eq!(b.fighters[0].effects.regen,0);
    }
}
#[test]
fn lishi_reflection_stays_full_own_physical_attack_in_revised_duels(){
    for _ in 0..40{
        let(mut arena,_,y,id,now)=revised_arena([0,1],0);
        let b=arena.battles.get_mut(&id).unwrap();let attack=b.fighters[0].stats.balance.unwrap().physical_attack;
        b.fighters[1].stats.balance.as_mut().unwrap().reduction_bp=2500;
        paired_actions(&mut arena,id,now,[("guard",None),("attack",None)]);
        let b=&arena.battles[&id];let event=b.events.iter().find(|e|e.actor==y).unwrap();
        if event.missed{continue;}
        assert_eq!(event.reflected,attack);assert_eq!(b.fighters[0].effects.passive_physical,100);
        return;
    }
    panic!("Expected an ordinary landed attack");
}
#[test]
fn solid_guard_in_duels_spends_fixed_mana_and_blocks_the_opponents_hit(){
    for magical in [false,true]{
        let (mut arena,x,y,id,now)=arena();
        let battle=arena.battles.get_mut(&id).unwrap();
        for f in &mut battle.fighters{f.stats.hp=3000;f.hp=3000;}
        battle.fighters[0].speed=300;
        battle.fighters[1].job=if magical{2}else{1};
        let cost=skills::item("sheet_012").unwrap().mp_cost;
        paired_actions(&mut arena,id,now,[("skill",Some("sheet_012")),if magical{("skill",Some("legacy_2"))}else{("attack",None)}]);
        let battle=&arena.battles[&id];
        let hit=battle.events.iter().find(|e|e.actor==y).unwrap();
        let raw=if magical{180-5}else{100-5};
        assert_eq!(hit.damage,raw-25);
        assert_eq!(battle.fighters[0].hp,3000-(raw-25));
        assert_eq!(battle.fighters[0].mp,300-cost);
        assert_eq!((battle.fighters[0].effects.defense,battle.fighters[0].effects.defense_flat),(1,25));
        assert!(battle.events.iter().any(|e|e.actor==x&&e.skill=="sheet_012"));
        let next=now+Duration::from_secs(5);
        arena.tick(next,&std::collections::HashMap::from([(x,(true,true)),(y,(true,true))]));
        paired_actions(&mut arena,id,next,[("guard",None),if magical{("skill",Some("legacy_2"))}else{("attack",None)}]);
        assert_eq!(arena.battles[&id].events.iter().find(|e|e.actor==y).unwrap().damage,(raw/2-25).max(0));
        assert_eq!(arena.battles[&id].fighters[0].effects.defense,0,"Fixed shield lasts exactly two duel rounds including the cast");
    }
}
#[test]
fn revised_sleep_and_silence_each_block_one_action_for_fast_and_slow_casters() {
    for effect in ["sleep", "silence"] {
        let skill = skills::ITEMS.iter().find(|s| s.active && s.effect == effect).unwrap();
        for first in [0, 1] {
            let mut observed = false;
            for _ in 0..40 {
                let (mut arena, x, y, id, mut now) = revised_arena([skill.job, 2], first);
                let initial_mp = arena.battles[&id].fighters[0].mp;
                let cost = vssjx_server::skill_balance::cost(skill, arena.battles[&id].fighters[0].stats);
                let expected_action = if effect == "sleep" { "sleep" } else { "fizzle" };
                let mut blocked = 0;
                for round in 0..3 {
                    let before_mp = arena.battles[&id].fighters[1].mp;
                    let target_skill = if round == 0 && first == 1 { "legacy_2" } else if round < 2 { "sheet_018" } else { "legacy_2" };
                    paired_actions(&mut arena, id, now, [if round == 0 { ("skill", Some(&skill.id)) } else { ("guard", None) }, ("skill", Some(target_skill))]);
                    let b = &arena.battles[&id];
                    if round == 0 && b.events.iter().any(|e| e.actor == x && e.missed) { break; }
                    let target_event = b.events.iter().find(|e| e.actor == y).unwrap();
                    if round == usize::from(first == 1) {
                        assert_eq!(target_event.action, expected_action);
                        assert_eq!(b.fighters[1].mp, before_mp, "A cancelled spell consumes no mana");
                        assert_eq!(b.fighters[1].effects.remaining(target_skill), 0, "A cancelled spell starts no cooldown");
                        blocked += 1;
                    } else { assert_eq!(target_event.action, "skill"); }
                    if round == 0 {
                        assert_eq!(b.fighters[0].mp, initial_mp - cost);
                        assert_eq!(b.fighters[0].effects.remaining(&skill.id), 0);
                        assert_eq!(b.fighters[0].effects.balance.as_ref().unwrap().control_protection, 2);
                        let remaining = if effect == "sleep" { b.fighters[0].effects.enemy_sleep } else { b.fighters[0].effects.enemy_silence };
                        assert_eq!(remaining, i32::from(first == 1));
                    }
                    now += Duration::from_secs(5);
                    arena.tick(now, &std::collections::HashMap::from([(x, (true,true)), (y, (true,true))]));
                    if round == 2 { observed = true; }
                }
                if observed { assert_eq!(blocked, 1);break; }
            }
            assert!(observed, "No landed {effect} sample for initiative {first}");
        }
    }
}
#[test]
fn landed_damage_still_wakes_sleep_and_silence_expires_after_a_basic_or_guard_action() {
    let mut woke = false;
    for _ in 0..40 {
        let (mut a, x, y, id, now) = revised_arena([1, 2], 0);
        a.battles.get_mut(&id).unwrap().fighters[0].effects.enemy_sleep = 1;
        paired_actions(&mut a, id, now, [("attack", None), ("skill", Some("legacy_2"))]);
        if a.battles[&id].events.iter().any(|e| e.actor == x && e.missed) { continue; }
        assert_eq!(a.battles[&id].events.iter().find(|e| e.actor == y).unwrap().action, "skill");
        woke = true;break;
    }
    assert!(woke);
    for action in ["attack", "guard"] {
        let (mut a, _, y, id, now) = revised_arena([1, 2], 0);
        a.battles.get_mut(&id).unwrap().fighters[0].effects.enemy_silence = 1;
        paired_actions(&mut a, id, now, [("guard", None), (action, None)]);
        assert_eq!(a.battles[&id].events.iter().find(|e| e.actor == y).unwrap().action, action);
        assert_eq!(a.battles[&id].fighters[0].effects.enemy_silence, 0);
    }
}
#[test]
fn revised_reflection_uses_own_attack_ratio_without_mitigation_or_reflect_loops() {
    for (job, action, skill, magical) in [(0,"attack",None,false),(2,"attack",None,true),(2,"skill",Some("legacy_2"),true)] {
        for active in [false, true] {
            for mitigated in [false, true] {
                let mut observed = false;
                for _ in 0..40 {
                    let (mut a, x, _, id, now) = revised_arena([job, 0], 0);
                    let b = a.battles.get_mut(&id).unwrap();
                    let attacker = &mut b.fighters[0];
                    attacker.effects.passive_physical = 100;attacker.effects.passive_magic = 100;
                    let stats = attacker.stats.balance.as_mut().unwrap();
                    stats.physical_defense = if mitigated {780} else {0};
                    stats.magic_defense = if mitigated {1560} else {0};
                    stats.reduction_bp = if mitigated {2000} else {0};
                    if mitigated { attacker.effects.defense = 2;attacker.effects.defense_percent = 25; }
                    let defender = &mut b.fighters[1];
                    defender.effects.passive_physical = if magical {0} else {20};
                    defender.effects.passive_magic = if magical {20} else {0};
                    if active {
                        if magical { defender.effects.reflect_magic = 2;defender.effects.magic_percent = 60; }
                        else { defender.effects.reflect_physical = 2;defender.effects.physical_percent = 60; }
                    }
                    let hp = b.fighters.each_ref().map(|f| f.hp);
                    paired_actions(&mut a, id, now, [(action, skill), ("guard", None)]);
                    let b = &a.battles[&id];let event = b.events.iter().find(|e| e.actor == x).unwrap();
                    if event.missed { assert_eq!(event.reflected,0);continue; }
                    // Reflection is own physical attack; armor, guard and PvP
                    // damage scale cannot reduce it, and it cannot reflect again.
                    let expected = if active{300}else{100};
                    assert_eq!(event.reflected,expected);
                    assert_eq!(event.fighters[0].hp,hp[0]-expected);
                    assert_eq!(event.fighters[1].hp,hp[1]-event.damage,"Reflection never reflects recursively");
                    assert_eq!(event.fighters[0].effects.last_reflected,expected);
                    observed = true;break;
                }
                assert!(observed,"No landed reflection sample");
            }
        }
    }
}
#[test]
fn revised_magical_basic_attacks_never_trigger_physical_only_reflection() {
    let mut observed = false;
    for _ in 0..40 {
        let (mut a, x, _, id, now) = revised_arena([2, 0], 0);
        let defender = &mut a.battles.get_mut(&id).unwrap().fighters[1];
        defender.effects.passive_magic = 0;defender.effects.reflect_magic = 0;
        defender.effects.passive_physical = 100;defender.effects.reflect_physical = 2;defender.effects.physical_percent = 100;
        paired_actions(&mut a, id, now, [("attack", None), ("guard", None)]);
        let event = a.battles[&id].events.iter().find(|e| e.actor == x).unwrap();
        if event.missed { continue; }
        assert!(event.damage>0);assert_eq!(event.reflected,0);observed=true;break;
    }
    assert!(observed);
}
