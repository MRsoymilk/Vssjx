use std::{collections::HashMap,time::{Duration,Instant}};
use serde_json::json;
use uuid::Uuid;
use vssjx_server::{attributes,skills,skill_balance,population,team_rules,pve_rules::Stats,duel};

fn stats(job:i16)->Stats{let mut s=attributes::balanced_stats(job,60,false,[60;5]);s.hp=100000;s}
fn fighter(job:i16)->team_rules::Fighter{
    let s=stats(job);
    team_rules::Fighter{id:Uuid::new_v4(),name:"眩晕验证".into(),job,gender:0,school:3,level:60,appearance:[1,0,0],stats:s,hp:s.hp,mp:s.mp,potions:6,effects:skills::State::new(job,3,60,1),guarding:false}
}
#[test]
fn thunder_keeps_damage_cost_and_exact_chance_with_three_turn_cooldown(){
    let s=skills::item("sheet_010").unwrap();let stats=stats(0);
    assert_eq!(s.stun.as_ref().unwrap().chance,35);
    assert_eq!(s.stun.as_ref().unwrap().actions,1);
    assert_eq!(skill_balance::kind(s),"single");
    assert_eq!(skill_balance::coefficient(s,1),16000);
    assert_eq!(skill_balance::cost(s,stats),(stats.mp*900+9999)/10000);
    let mut successes=0;
    for roll in 0..100{
        let mut state=skills::State::new(0,3,60,1);state.enable_stun(stats);
        let(mut hp,mut mp)=(stats.hp,stats.mp);
        let damage=state.cast(s,stats,&mut hp,&mut mp,20,roll);
        assert!(damage>0);assert_eq!(state.enemy_stun,if roll<35{1}else{0});
        successes+=state.enemy_stun;
        assert_eq!(state.remaining(&s.id),4);
        state.end_turn();assert_eq!(state.remaining(&s.id),3);
        // Stun is an action token, not a round-end timer.
        assert_eq!(state.enemy_stun,if roll<35{1}else{0});
    }
    assert_eq!(successes,35);
}
#[test]
fn damage_does_not_wake_stun_and_other_controls_share_protection(){
    let stats=stats(0);let mut state=skills::State::new(0,3,60,1);state.enable_stun(stats);
    let(mut hp,mut mp)=(stats.hp,stats.mp*10);
    state.cast(skills::item("sheet_010").unwrap(),stats,&mut hp,&mut mp,20,0);
    assert_eq!(state.balance.as_ref().unwrap().control_protection,3);
    state.cast(skills::item("legacy_0").unwrap(),stats,&mut hp,&mut mp,20,0);
    assert_eq!(state.enemy_stun,1);
    state.cast(skills::item("sheet_051").unwrap(),stats,&mut hp,&mut mp,20,0);
    assert_eq!(state.enemy_sleep,0);
    state.cast(skills::item("sheet_021").unwrap(),stats,&mut hp,&mut mp,20,0);
    assert_eq!(state.enemy_silence,0);
    assert!(state.consume_stun());assert!(!state.consume_stun());
    state.end_turn();state.end_turn();state.end_turn();
    state.cast(skills::item("sheet_051").unwrap(),stats,&mut hp,&mut mp,20,0);
    assert_eq!(state.enemy_sleep,1);
    state.cast(skills::item("sheet_010").unwrap(),stats,&mut hp,&mut mp,20,0);
    assert_eq!(state.enemy_stun,0,"Sleep protection also rejects new stuns");
}
#[test]
fn misses_old_saves_and_roundtrips_do_not_invent_or_reroll_control(){
    let stats=stats(0);let skill=skills::item("sheet_010").unwrap();
    let mut old=skills::State::new(0,3,60,1);old.activate(stats);
    let encoded=serde_json::to_value(&old).unwrap();assert!(encoded.get("enemy_stun").is_none());assert!(encoded["balance"].get("stun_revision").is_none());
    let mut old:skills::State=serde_json::from_value(encoded).unwrap();let(mut hp,mut mp)=(stats.hp,stats.mp);
    old.cast(skill,stats,&mut hp,&mut mp,20,0);
    assert_eq!(old.enemy_stun,0);assert_eq!(old.remaining(&skill.id),1,"An existing fight retains the old zero cooldown");
    let mut new=skills::State::new(0,3,60,1);new.enable_stun(stats);
    new.miss(skill,stats,&mut mp);assert_eq!(new.enemy_stun,0);assert_eq!(new.balance.as_ref().unwrap().control_protection,0);assert_eq!(new.remaining(&skill.id),4);
    new.cast(skill,stats,&mut hp,&mut mp,20,0);
    let wire=serde_json::to_value(&new).unwrap();let mut restored:skills::State=serde_json::from_value(wire.clone()).unwrap();
    assert_eq!(serde_json::to_value(&restored).unwrap(),wire);assert_eq!(restored.enemy_stun,1);assert!(restored.consume_stun());
}
#[test]
fn party_target_skips_entire_monster_action_and_survives_followup_damage(){
    for _ in 0..40{
        let mut enemy=population::definitions().into_iter().find(|d|d.id=="wolf_a").unwrap();enemy.hp=100000;
        let mut b=team_rules::Battle::new("qingyun_trail".into(),vec![fighter(0),fighter(1)],vec![enemy],1000);
        b.act(b.fighters[0].id,"skill",Some("m0"),Some("sheet_010"),2000,0).unwrap();
        b.act(b.fighters[1].id,"attack",Some("m0"),None,2001,0).unwrap();
        if b.events.iter().any(|e|e.actor==b.fighters[0].id.to_string()&&e.missed){continue;}
        assert_eq!(b.events.iter().filter(|e|e.action=="stun").count(),1);
        assert!(!b.events.iter().any(|e|e.actor=="m0"&&matches!(e.action.as_str(),"attack"|"skill")));
        assert_eq!(b.enemies[0].effects.enemy_stun,0);
        assert_eq!(b.fighters[0].effects.remaining("sheet_010"),3);
        assert!(b.enemies[0].effects.balance.as_ref().unwrap().control_protection>0);
        let wire=serde_json::to_value(&b).unwrap();let restored:team_rules::Battle=serde_json::from_value(wire.clone()).unwrap();assert_eq!(serde_json::to_value(restored).unwrap(),wire);
        return;
    }
    panic!("No landed sample after 40 attempts");
}
fn duel_fighter(job:i16,speed:i32)->duel::Fighter{
    let stats=stats(job);
    let value=json!({"state":{"battle":null,"stats":stats,"attributes":{"allocated":[0,0,0,0,0]},"character":{"id":Uuid::new_v4(),"display_name":"切磋眩晕","job":job,"gender":0,"school":3,"level":60}}});
    let mut f=duel::Fighter::from_snapshot(&value,[1,0,0]).unwrap();f.speed=speed;f
}
fn command(id:Uuid,revision:u64,action:&str,skill:Option<&str>)->duel::Command{
    duel::Command{request_id:Uuid::new_v4(),action:action.into(),target:None,invite_id:None,battle_id:Some(id),expected_revision:Some(revision.to_string()),skill:skill.map(str::to_owned)}
}
#[test]
fn slower_duel_stun_survives_round_end_and_cancels_next_spell_without_cost(){
    for _ in 0..40{
        let now=Instant::now();let a=duel_fighter(0,100);let b=duel_fighter(2,300);let ids=[a.id,b.id];
        let mut arena=duel::Arena::default();let offer=arena.invite(a.id,b.id,a.name.clone(),b.name.clone(),now).unwrap();let id=arena.start(offer,b.id,[a,b],now).unwrap();
        arena.act(ids[0],&command(id,0,"skill",Some("sheet_010")),now,[0,0,99]).unwrap();
        arena.act(ids[1],&command(id,0,"attack",None),now,[0,0,99]).unwrap();
        let battle=&arena.battles[&id];
        if battle.events.iter().any(|e|e.actor==ids[0]&&e.missed){continue;}
        assert_eq!(battle.events[0].actor,ids[1]);
        assert_eq!(battle.fighters[0].effects.enemy_stun,1,"The already-acted victim must still lose its next action");
        let available=HashMap::from([(ids[0],(true,true)),(ids[1],(true,true))]);let later=now+Duration::from_secs(5);arena.tick(later,&available);
        let mp=arena.battles[&id].fighters[1].mp;let revision=arena.battles[&id].decision_revision;
        arena.act(ids[0],&command(id,revision,"guard",None),later,[0,99,99]).unwrap();
        arena.act(ids[1],&command(id,revision,"skill",Some("sheet_018")),later,[0,99,99]).unwrap();
        let battle=&arena.battles[&id];
        assert_eq!(battle.events[0].action,"stun");assert_eq!(battle.events[0].actor,ids[1]);
        assert_eq!(battle.fighters[1].mp,mp);assert_eq!(battle.fighters[0].effects.enemy_stun,0);
        assert_eq!(battle.fighters[1].effects.remaining("sheet_018"),0);
        assert_eq!(battle.events.iter().filter(|e|e.actor==ids[1]).count(),1);
        return;
    }
    panic!("No landed duel sample after 40 attempts");
}
