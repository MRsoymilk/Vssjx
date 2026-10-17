use serde_json::json;
use vssjx_server::{skills::{self,State},pve_rules::Stats};
fn stats()->Stats{Stats{hp:1000,mp:400,attack:100,defense:20}}
#[test]
fn catalog_restrictions_and_typed_effects(){
    assert_eq!(skills::ITEMS.len(),33);
    for s in skills::ITEMS.iter(){
        assert!(skills::check(&s.id,(s.job+1)%3,s.school.max(0),60).is_err());
        if s.school>=0{assert!(skills::check(&s.id,s.job,(s.school+1)%3,60).is_err());}
        if s.unlock_level>1{assert!(skills::check(&s.id,s.job,s.school.max(0),s.unlock_level-1).is_err());}
        assert_eq!(skills::check(&s.id,s.job,s.school.max(0),60).is_ok(),s.active);
    }
    let mut state=State::new(0,2,45,1);
    assert_eq!(state.passive_physical,20);assert_eq!(state.enemy_hit(50,false),(50,10));assert_eq!(state.enemy_hit(50,true),(50,0));
    let mut hp=10;let mut mp=100;
    let heal=skills::ITEMS.iter().find(|s|s.name=="起死回生").unwrap();
    state.cast(heal,stats(),&mut hp,&mut mp,5,0);
    state.after_player(&mut hp,1000);assert_eq!(hp,160);
    state.end_turn();state.after_player(&mut hp,1000);assert_eq!(hp,310);
    state.after_player(&mut hp,1000);assert_eq!(hp,310);
    let dot=skills::ITEMS.iter().find(|s|s.name=="推窗望月").unwrap();
    state.cast(dot,stats(),&mut hp,&mut mp,5,0);
    assert_eq!(state.after_player(&mut hp,1000),20);assert_eq!(state.after_player(&mut hp,1000),20);assert_eq!(state.after_player(&mut hp,1000),0);
    let sleep=skills::ITEMS.iter().find(|s|s.name=="醉生梦死").unwrap();
    state.cast(sleep,stats(),&mut hp,&mut mp,5,99);assert_eq!(state.enemy_sleep,0);
    state.cast(sleep,stats(),&mut hp,&mut mp,5,0);assert_eq!(state.enemy_sleep,2);
    state.end_turn();assert_eq!(state.enemy_sleep,1);state.end_turn();assert_eq!(state.enemy_sleep,0);
    let mana=skills::ITEMS.iter().find(|s|s.name=="偷天换日").unwrap();
    state.enemy_mp=7;mp=20;state.cast(mana,stats(),&mut hp,&mut mp,5,0);
    assert_eq!(state.enemy_mp,0);assert_eq!(mp,20-mana.mp_cost+7);
}
#[test]
fn shared_vectors_are_stable(){
    let vectors:Vec<_>=skills::ITEMS.iter().map(|s|{
        let mut state=State::new(s.job,s.school.max(0),60,10);
        state.reset_turn();let mut hp=100;let mut mp=200;
        let damage=state.cast(s,stats(),&mut hp,&mut mp,5,0);
        let dot=state.after_player(&mut hp,1000);
        let hit=state.enemy_hit(100,false);state.end_turn();
        json!({"id":s.id,"hp":hp,"mp":mp,"damage":damage,"dot":dot,"incoming":hit.0,"reflected":hit.1,"state":state})
    }).collect();
    let value=json!(vectors);
    if let Ok(path)=std::env::var("SSJX_WRITE_SKILL_VECTORS"){
        std::fs::write(path,serde_json::to_string_pretty(&value).unwrap()+"\n").unwrap();
    }else{
        let expected:serde_json::Value=serde_json::from_str(include_str!("../../client/tests/fixtures/skills_golden.json")).unwrap();
        assert_eq!(value,expected);
    }
}
