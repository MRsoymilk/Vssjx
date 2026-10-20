use vssjx_server::{attributes, monster_combat as ai, population, skills, team_rules::{Battle,Fighter}};
use uuid::Uuid;
fn fighter()->Fighter {
    let stats=attributes::balanced_stats(1,60,false,[100,0,100,100,0]);
    Fighter{id:Uuid::new_v4(),name:"同道".into(),job:1,gender:0,school:3,level:60,appearance:[0;3],stats,hp:stats.hp,mp:stats.mp,potions:3,effects:skills::State::new(1,3,60,60),guarding:false}
}
fn battle(count:usize)->Battle{
    let mut d=population::definitions_for("ancient_ruins").into_iter().find(|d|d.id=="boss").unwrap();d.hp=20000;d.attack=120;
    Battle::new("ancient_ruins".into(),(0..count).map(|_|fighter()).collect(),vec![d],1000)
}
fn turn(b:&mut Battle,roll:i32){let now=b.selection_starts_ms+1;let ids:Vec<_>=b.fighters.iter().filter(|f|f.hp>0).map(|f|f.id).collect();for id in ids{b.act(id,"guard",None,None,now,roll).unwrap();}}
#[test]
fn count_boundaries_and_attack_budgets(){
    for (r,n) in [(0,1),(59,1),(60,2),(87,2),(88,3),(99,3)]{assert_eq!(ai::solo_count(r),n);}
    let d=battle(1).enemies[0].definition.clone();
    let combo=ai::plan(&d,0,false,false);assert_eq!(combo.hits,2);assert_eq!(combo.coefficient*2,14000);
    assert!(ai::plan(&d,30,false,false).all);assert!(!ai::plan(&d,30,false,true).all);
    assert!(ai::plan(&d,50,false,false).bleed);
    let wolf=population::definitions()[1].clone();assert_eq!(ai::plan(&wolf,0,false,false).hits,1);
    assert_eq!(ai::critical(&wolf,100,0),(150,true));assert_eq!(ai::critical(&wolf,100,8),(100,false));assert_eq!(ai::critical(&d,100,14),(150,true));assert_eq!(ai::critical(&d,0,0),(0,false));
}
#[test]
fn combo_has_separate_hits_and_sweep_hits_every_living_fighter(){
    let mut b=battle(1);turn(&mut b,0);
    assert_eq!(b.events.iter().filter(|e|e.skill=="monster_combo").count(),2);
    let mut b=battle(3);b.fighters[2].hp=0;turn(&mut b,30);
    let hits:Vec<_>=b.events.iter().filter(|e|e.skill=="monster_sweep").collect();assert_eq!(hits.len(),2);assert_ne!(hits[0].target,hits[1].target);
    let mut old=battle(1);old.monster_revision=0;turn(&mut old,0);assert_eq!(old.events.iter().filter(|e|e.actor=="m0").count(),1);assert!(!old.events.iter().any(|e|e.critical));
}
#[test]
fn sleep_prevents_specials_and_criticals_are_saved_in_events(){
    let mut b=battle(1);b.enemies[0].effects.enemy_sleep=1;turn(&mut b,0);assert!(!b.events.iter().any(|e|e.actor=="m0"));
    let mut b=battle(1);turn(&mut b,0);assert!(b.events.iter().any(|e|e.actor=="m0"&&e.critical));
    let restored:Battle=serde_json::from_value(serde_json::to_value(&b).unwrap()).unwrap();assert_eq!(restored.monster_revision,1);assert!(restored.events.iter().any(|e|e.critical));
}
#[test]
fn bleed_persists_ticks_once_per_round_and_expires(){
    let mut observed=false;
    for _ in 0..30{
        let mut b=battle(1);turn(&mut b,50);
        if b.wounds.is_empty(){continue;}
        let id=b.fighters[0].id.to_string();assert_eq!(b.wounds[&id].0,2);assert_eq!(b.events.iter().filter(|e|e.skill=="monster_bleed").count(),1);
        let mut b:Battle=serde_json::from_value(serde_json::to_value(&b).unwrap()).unwrap();
        turn(&mut b,99);assert_eq!(b.wounds[&id].0,1);turn(&mut b,99);assert!(b.wounds.is_empty());turn(&mut b,99);assert!(!b.events.iter().any(|e|e.skill=="monster_bleed"));observed=true;break;
    }
    assert!(observed);
}

#[test]
fn solo_formation_targets_aoe_and_saved_rounds_are_authoritative(){
    use vssjx_server::pve_rules::{Battle as Solo,Action};
    let mut sources:Vec<_>=population::definitions().into_iter().filter(|d|d.kind!="npc").take(3).collect();
    for d in &mut sources{d.hp=10000;}
    let mut b=Solo::new_formation("qingyun_trail".into(),fighter(),sources,1000);
    assert_eq!(b.formation.as_ref().unwrap().enemies.len(),3);
    let before=serde_json::to_value(&b).unwrap();
    assert_eq!(b.turn_formation(Action::Attack,None,Some("m9"),2000,99),Err("INVALID_BATTLE_TARGET"));assert_eq!(serde_json::to_value(&b).unwrap(),before);
    b.turn_formation(Action::Attack,None,Some("m2"),2000,99).unwrap();
    let group=b.formation.as_ref().unwrap();assert_eq!(group.enemies[0].hp,10000);assert_eq!(group.enemies[1].hp,10000);assert!(group.events.iter().any(|e|e.actor==group.fighters[0].id.to_string()&&e.target=="m2"));
    let mut b:Solo=serde_json::from_value(serde_json::to_value(&b).unwrap()).unwrap();
    let skill=skills::ITEMS.iter().find(|s|s.active&&s.job==1&&s.target=="all_enemies").unwrap();
    let mp=b.mp;let cost=vssjx_server::skill_balance::cost(skill,b.frozen_stats.unwrap());
    b.turn_formation(Action::Skill,Some(&skill.id),Some("m1"),2001,99).unwrap();
    assert_eq!(b.mp,mp-cost);assert_eq!(b.round,2);
    assert_eq!(b.formation.as_ref().unwrap().events.iter().filter(|e|e.skill==skill.id).count(),3);
    assert!(b.defeated_enemies().is_empty());
    b.turn_formation(Action::Flee,None,None,2002,99).unwrap();assert_eq!(b.outcome,"fled");
    let before=serde_json::to_value(&b).unwrap();assert_eq!(b.turn_formation(Action::Attack,None,Some("m0"),2003,99),Err("BATTLE_FINISHED"));assert_eq!(serde_json::to_value(&b).unwrap(),before);
    let boss=population::definitions_for("ancient_ruins").into_iter().find(|d|d.id=="boss").unwrap();
    let budget=vssjx_server::skill_balance::monster(boss.clone()).hp;
    let guard=population::definitions_for("ancient_ruins").into_iter().find(|d|d.id=="guardian").unwrap();
    let b=Solo::new_formation("ancient_ruins".into(),fighter(),vec![boss,guard],1000);
    assert_eq!(b.enemy.hp,budget,"Legacy envelope keeps the primary template for client validation");
    assert_eq!(b.enemy_hp,b.formation.as_ref().unwrap().enemies[0].hp,"Primary current HP matches its allocated encounter share");
    assert_eq!(b.formation.unwrap().enemies.iter().map(|e|e.hp).sum::<i32>(),budget);
}
