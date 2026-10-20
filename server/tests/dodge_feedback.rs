use uuid::Uuid;
use std::time::Instant;
use vssjx_server::{attributes,duel,population,pve_rules::{self,Action},skills,team_rules::{Battle,Fighter}};
fn fighter()->Fighter {
    let stats=attributes::balanced_stats(1,60,false,[0;5]);
    Fighter{id:Uuid::new_v4(),name:"闪避验证".into(),job:1,gender:0,school:3,level:60,appearance:[1,0,0],stats,hp:stats.hp,mp:stats.mp,potions:3,effects:skills::State::new(1,3,60,1),guarding:false}
}
fn battle(mut f:Fighter)->Battle {
    f.stats.balance.as_mut().unwrap().hit_bonus=[0;2];
    let mut d=population::definitions().into_iter().find(|d|d.id=="wolf_a").unwrap();d.hp=20000;
    Battle::new("qingyun_trail".into(),vec![f],vec![d],1000)
}
#[test]
fn ordinary_and_skill_misses_have_explicit_per_target_flags(){
    for action in ["attack","skill"] {
        let mut found=false;
        for _ in 0..512 {
            let mut b=battle(fighter());let id=b.fighters[0].id;
            let skill=skills::ITEMS.iter().find(|s|s.active&&s.job==1&&s.damage_percent>0&&s.target=="enemy").unwrap();
            b.act(id,action,Some("m0"),if action=="skill"{Some(&skill.id)}else{None},2000,99).unwrap();
            let event=b.events.iter().find(|e|e.actor==id.to_string()).unwrap();
            if !event.missed {continue;}
            assert_eq!(event.damage,0);assert!(!event.critical);assert!(b.fighters[0].effects.last_missed);
            let raw=serde_json::to_value(&b).unwrap();let restored:Battle=serde_json::from_value(raw).unwrap();
            assert!(restored.events.iter().any(|e|e.missed));found=true;break;
        }
        assert!(found);
    }
}
#[test]
fn monster_miss_has_no_reflection_bleeding_or_damage(){
    let mut found=false;
    for _ in 0..512 {
        let mut f=fighter();f.job=0;f.stats.balance.as_mut().unwrap().evade_bonus=[50000;2];
        let mut b=battle(f);b.empower_hunt();let id=b.fighters[0].id;
        b.act(id,"guard",None,None,2000,0).unwrap();
        assert!(!b.events[0].missed,"Guard's zero damage is not a dodge");
        let misses:Vec<_>=b.events.iter().filter(|e|e.actor=="m0"&&e.missed).collect();
        if misses.is_empty(){continue;}
        assert!(misses.iter().all(|e|e.damage==0&&!e.critical));
        if b.events.iter().filter(|e|e.actor=="m0").all(|e|e.missed){assert!(b.wounds.is_empty());assert!(!b.events.iter().any(|e|e.action=="dot"));}
        found=true;break;
    }
    assert!(found);
}
#[test]
fn legacy_pve_and_saved_skill_state_keep_miss_flags_without_migration(){
    let mut state:skills::State=serde_json::from_str("{}").unwrap();assert!(!state.last_missed&&!state.last_enemy_missed);
    state.last_missed=true;state.last_enemy_missed=true;let state:skills::State=serde_json::from_value(serde_json::to_value(state).unwrap()).unwrap();assert!(state.last_missed&&state.last_enemy_missed);
    let mut state=state;state.reset_turn();assert!(!state.last_missed&&!state.last_enemy_missed);
    let mut observed=false;
    for _ in 0..512 {
        let d=population::definitions().into_iter().find(|d|d.id=="wolf_a").unwrap();let mut b=pve_rules::Battle::new(d,1000,400,3);
        let mut stats=fighter().stats;stats.balance.as_mut().unwrap().hit_bonus=[0;2];
        b.turn_selected(Action::Attack,1,3,60,stats,0,0,None,99).unwrap();
        if b.skills.last_missed {assert_eq!(b.skills.last_damage,0);observed=true;break;}
    }
    assert!(observed);
}
#[test]
fn duel_publishes_miss_for_the_specific_attack_and_not_guard(){
    let mut found=false;
    for _ in 0..512 {
        let now=Instant::now();
        let make=||{let f=fighter();duel::Fighter{id:f.id,name:f.name,job:f.job,gender:0,school:3,level:60,stats:f.stats,speed:100,appearance:[1,0,0],hp:f.hp,mp:f.mp,effects:f.effects,guarding:false}};
        let mut a=make();let b=make();a.stats.balance.as_mut().unwrap().hit_bonus=[0;2];let ids=[a.id,b.id];
        let mut arena=duel::Arena::default();let offer=arena.invite(ids[0],ids[1],a.name.clone(),b.name.clone(),now).unwrap();let id=arena.start(offer,ids[1],[a,b],now).unwrap();
        let mut command=duel::Command{request_id:Uuid::new_v4(),action:"attack".into(),target:None,invite_id:None,battle_id:Some(id),expected_revision:Some("0".into()),skill:None};
        arena.act(ids[0],&command,now,[99;3]).unwrap();command.action="guard".into();command.request_id=Uuid::new_v4();arena.act(ids[1],&command,now,[99;3]).unwrap();
        let events=&arena.battles[&id].events;assert!(events.iter().filter(|e|e.action=="guard").all(|e|!e.missed));
        if events.iter().any(|e|e.missed&&e.actor==ids[0]){assert!(events.iter().filter(|e|e.missed).all(|e|e.damage==0&&e.reflected==0&&!e.critical));found=true;break;}
    }
    assert!(found);
}
