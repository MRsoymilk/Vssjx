use vssjx_server::{attributes,monster_combat as ai,population,skills,team_rules::{Battle,Fighter}};
use uuid::Uuid;
fn arena(party:usize)->Battle {
    let stats=attributes::balanced_stats(1,60,false,[0;5]);
    let fighters=(0..party).map(|_|Fighter{id:Uuid::new_v4(),name:"精英验证".into(),job:1,gender:0,school:3,level:60,appearance:[0;3],stats,hp:stats.hp,mp:stats.mp,potions:3,effects:skills::State::new(1,3,60,1),guarding:false}).collect();
    let wolf=population::definitions().into_iter().find(|d|d.id=="wolf_a").unwrap();
    let mut b=Battle::new("qingyun_trail".into(),fighters,vec![wolf],1000);b.empower_hunt();b
}
fn turn(b:&mut Battle,action:&str,roll:i32){let now=b.selection_starts_ms+1;let ids:Vec<_>=b.fighters.iter().filter(|f|f.hp>0).map(|f|f.id).collect();for id in ids{if !b.active(){break;}b.act(id,action,if action=="attack"{Some("m0")}else{None},None,now,roll).unwrap();}}
#[test]
fn map_species_counter_survives_roundtrip_and_stays_due_until_victory(){
    let mut p=ai::HuntPressure::default();assert!(p.valid());
    for _ in 0..4{assert!(!p.note("qingyun_trail","monster/langw"));}
    // Different resident IDs/coordinates do not enter the counter; species is authoritative art.
    let mut p:ai::HuntPressure=serde_json::from_value(serde_json::to_value(p).unwrap()).unwrap();
    assert!(p.note("qingyun_trail","monster/langw"));assert!(p.note("qingyun_trail","monster/langw"));assert_eq!(p.count,5);
    p.cleared("qingyun_trail","other");assert!(p.due());p.cleared("qingyun_trail","monster/langw");assert_eq!(p,Default::default());
    assert!(!p.note("qingyun_trail","monster/langw"));assert!(!p.note("qingyun_trail","monster/hs1"));assert_eq!(p.count,1);
    assert!(!p.note("ancient_ruins","monster/hs1"));assert_eq!(p.count,1);
    assert!(!ai::HuntPressure{count:6,..p}.valid());
    assert!(serde_json::from_str::<ai::HuntPressure>(r#"{"map":"x","species":"y","count":4,"client_override":true}"#).is_err());
}
#[test]
fn party_elite_is_tougher_and_specials_respect_silence(){
    let solo=arena(1);let party=arena(3);assert!(party.enemies[0].hp>solo.enemies[0].hp);
    assert!(party.enemies[0].definition.attack>solo.enemies[0].definition.attack);
    let e=&solo.enemies[0];let p=ai::elite_plan(e.elite.as_ref(),&e.definition,0,false,false);assert_eq!(p.hits,3);assert!(p.bleed);
    let e=&party.enemies[0];let p=ai::elite_plan(e.elite.as_ref(),&e.definition,0,false,false);assert_eq!(p.hits,4);
    assert!(ai::elite_plan(e.elite.as_ref(),&e.definition,99,false,false).all);
    let muted=ai::elite_plan(e.elite.as_ref(),&e.definition,99,true,true);assert!(!muted.all&&!muted.magical);
    assert_eq!(ai::elite_critical(e.elite.as_ref(),&e.definition,100,44),(200,true));assert_eq!(ai::elite_critical(e.elite.as_ref(),&e.definition,0,0),(0,false));
}
#[test]
fn death_revives_before_victory_and_saved_remaining_lives_are_finite(){
    let mut b=arena(1);b.enemies[0].hp=1;turn(&mut b,"attack",99);
    assert!(b.active());assert_eq!(b.enemies[0].elite.as_ref().unwrap().revives_left,0);
    assert!(b.events.iter().any(|e|e.action=="revive"&&e.healed>0));
    let mut b:Battle=serde_json::from_value(serde_json::to_value(b).unwrap()).unwrap();
    b.enemies[0].hp=1;turn(&mut b,"attack",99);assert_eq!(b.outcome,"victory");assert!(!b.events.iter().any(|e|e.action=="revive"));
}
#[test]
fn dot_death_revives_and_defeat_never_reanimates_the_winner(){
    let mut b=arena(1);b.enemies[0].hp=1;b.enemies[0].dots.insert("poison".into(),(3,10));b.enemies[0].effects.enemy_sleep=2;
    turn(&mut b,"guard",99);assert!(b.active());assert!(b.enemies[0].dots.is_empty());assert!(b.events.iter().any(|e|e.action=="revive"));
    let mut b=arena(1);b.fighters[0].hp=1;b.enemies[0].hp=1;b.enemies[0].dots.insert("poison".into(),(3,10));
    b.wounds.insert(b.fighters[0].id.to_string(),(1,10));b.enemies[0].effects.enemy_sleep=2;
    turn(&mut b,"guard",99);assert_eq!(b.outcome,"defeat");assert!(!b.events.iter().any(|e|e.action=="revive"));
}
#[test]
fn actual_elite_round_has_high_combo_and_control_still_works(){
    let mut b=arena(3);turn(&mut b,"guard",0);assert_eq!(b.events.iter().filter(|e|e.skill=="monster_combo").count(),4);
    let mut b=arena(3);turn(&mut b,"guard",99);assert_eq!(b.events.iter().filter(|e|e.skill=="monster_sweep").count(),3);
    let mut b=arena(1);b.enemies[0].effects.enemy_sleep=1;turn(&mut b,"guard",0);assert!(!b.events.iter().any(|e|e.actor=="m0"));
}

#[test]
fn old_team_request_receipts_keep_the_same_serialized_command() {
    let wire=serde_json::json!({"character_id":Uuid::new_v4(),"action":"challenge","operation_id":Uuid::new_v4(),"target":"spirit","battle_id":null,"expected_revision":null,"skill":null,"ready":null});
    let command:vssjx_server::teams::Command=serde_json::from_value(wire.clone()).unwrap();
    assert_eq!(serde_json::to_value(command).unwrap(),wire);
}
#[test]
fn reflection_death_stops_combo_and_uses_one_finite_life() {
    let mut observed=false;
    for _ in 0..30 {
        let mut b=arena(1);b.fighters[0].job=0;b.enemies[0].hp=1;
        turn(&mut b,"guard",0);
        if !b.events.iter().any(|e|e.action=="revive"){continue;}
        assert_eq!(b.events.iter().filter(|e|e.skill=="monster_combo").count(),1);
        assert_eq!(b.enemies[0].elite.as_ref().unwrap().revives_left,0);
        assert!(b.active());observed=true;break;
    }
    assert!(observed);
}
