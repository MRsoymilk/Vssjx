use uuid::Uuid;
use vssjx_server::{attributes,monster_combat,population,skills,team_rules::{Battle,Event,Fighter}};

fn encounter(players:usize,enemies:usize)->Battle {
    let stats=attributes::balanced_stats(1,60,false,[0;5]);
    let fighters=(0..players).map(|_|Fighter{id:Uuid::new_v4(),name:"持续伤害验证".into(),job:1,gender:0,school:3,level:60,appearance:[0;3],stats,hp:100,mp:stats.mp,potions:3,effects:skills::State::new(1,3,60,1),guarding:false}).collect();
    let wolf=population::definitions().into_iter().find(|e|e.id=="wolf_a").unwrap();
    let mut b=Battle::new("qingyun_trail".into(),fighters,vec![wolf;enemies],1000);
    for e in &mut b.enemies {e.hp=100;e.definition.hp=100;e.effects.enemy_sleep=2;}
    b
}
fn guard_round(b:&mut Battle) {
    let now=b.selection_starts_ms+1000;
    let ids:Vec<_>=b.fighters.iter().filter(|f|f.hp>0).map(|f|f.id).collect();
    for id in ids {b.act(id,"guard",None,None,now,99).unwrap();}
}

#[test]
fn mixed_statuses_on_ten_targets_form_one_round_end_batch() {
    let mut b=encounter(5,5);
    for (i,f) in b.fighters.iter_mut().enumerate() {
        f.effects.regen=2;f.effects.regen_amount=7;
        b.wounds.insert(f.id.to_string(),(3,11+i as i32));
    }
    for e in &mut b.enemies {
        e.dots.insert(format!("{}/bleed",b.fighters[0].id),(1,3));
        e.dots.insert(format!("{}/poison",b.fighters[1].id),(2,5));
        e.dots.insert(format!("{}/future_burn",b.fighters[2].id),(3,7));
    }
    let before=serde_json::to_value(&b).unwrap();
    guard_round(&mut b);
    let ticks:Vec<_>=b.events.iter().filter(|e|e.periodic).collect();
    assert_eq!(ticks.len(),10);
    assert!(b.events[b.events.len()-10..].iter().all(|e|e.periodic));
    assert!(ticks.iter().all(|e|e.action=="dot"&&e.actor==e.target&&e.healed==0&&!e.missed&&!e.critical));
    for (i,f) in b.fighters.iter().enumerate() {
        assert_eq!(f.hp,107-(11+i as i32));
        assert_eq!(f.effects.regen,1);
        assert_eq!(b.wounds[&f.id.to_string()].0,2);
        assert_eq!(ticks.iter().find(|e|e.target==f.id.to_string()).unwrap().damage,11+i as i32);
    }
    for e in &b.enemies {
        assert_eq!(e.hp,85);
        assert_eq!(e.dots.len(),2);
        assert_eq!(e.dots[&format!("{}/poison",b.fighters[1].id)].0,1);
        assert_eq!(e.dots[&format!("{}/future_burn",b.fighters[2].id)].0,2);
        assert_eq!(ticks.iter().find(|t|t.target==e.slot).unwrap().damage,15);
    }
    // Five guards, five heals and one simultaneous periodic group.
    assert_eq!(b.selection_starts_ms,2000+11*3000+1000);
    assert_eq!(b.deadline_ms-b.selection_starts_ms,30000);
    let wire=serde_json::to_value(&b).unwrap();
    let restored:Battle=serde_json::from_value(wire.clone()).unwrap();
    assert_eq!(serde_json::to_value(restored).unwrap(),wire);
    if let Ok(path)=std::env::var("SSJX_PERIODIC_FIXTURE") {
        std::fs::write(path,serde_json::to_vec(&serde_json::json!({"before":before,"after":wire})).unwrap()).unwrap();
    }
}

#[test]
fn lethal_ticks_finish_the_batch_before_reviving_or_ending() {
    for everyone_dies in [false,true] {
        let mut b=encounter(2,2);
        b.enemies[0].elite=Some(monster_combat::Elite{party_size:2,revives_left:1});b.monster_revision=2;
        for e in &mut b.enemies {e.hp=1;e.dots.insert("poison".into(),(1,10));}
        for (i,f) in b.fighters.iter_mut().enumerate() {
            if everyone_dies||i==0 {
                f.hp=1;b.wounds.insert(f.id.to_string(),(1,10));
            }
        }
        guard_round(&mut b);
        assert!(b.wounds.is_empty());
        assert!(b.enemies.iter().all(|e|e.dots.is_empty()));
        if everyone_dies {
            assert_eq!(b.outcome,"defeat");
            assert!(!b.events.iter().any(|e|e.action=="revive"));
            assert_eq!(b.events.iter().filter(|e|e.periodic).count(),4);
        }else{
            assert!(b.active());
            assert_eq!(b.events.iter().filter(|e|e.periodic).count(),3);
            assert_eq!(b.events.last().unwrap().action,"revive");
            assert!(b.events[b.events.len()-4..b.events.len()-1].iter().all(|e|e.periodic&&e.damage==1));
            assert_eq!(b.enemies[0].elite.as_ref().unwrap().revives_left,0);
        }
    }
}

#[test]
fn reflected_hits_keep_their_attack_position_and_old_events_still_decode() {
    let old=serde_json::json!({"actor":"m0","target":"m0","action":"dot","skill":"","damage":9,"healed":0,"missed":false,"critical":false});
    let event:Event=serde_json::from_value(old.clone()).unwrap();
    assert!(!event.periodic);
    assert_eq!(serde_json::to_value(event).unwrap(),old);
    let mut observed=false;
    for _ in 0..30 {
        let mut b=encounter(1,1);
        b.fighters[0].hp=b.fighters[0].stats.hp;
        b.fighters[0].effects.passive_physical=100;
        b.enemies[0].effects.enemy_sleep=0;b.enemies[0].definition.attack=200;
        b.wounds.insert(b.fighters[0].id.to_string(),(2,3));
        guard_round(&mut b);
        if let Some(index)=b.events.iter().position(|e|e.action=="dot"&&e.actor!=e.target) {
            assert!(!b.events[index].periodic);
            assert_eq!(b.events[index-1].actor,"m0");
            assert!(b.events.last().unwrap().periodic);
            observed=true;break;
        }
    }
    assert!(observed);
}
