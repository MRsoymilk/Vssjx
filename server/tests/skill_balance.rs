use vssjx_server::{attributes,population,skill_balance as b,skills,pve_rules::{Action,Battle},team_rules};
use uuid::Uuid;
fn fighter(job:i16)->team_rules::Fighter{
    let stats=attributes::balanced_stats(job,60,false,[60,60,60,60,60]);
    team_rules::Fighter{id:Uuid::new_v4(),name:"同道".into(),job,gender:0,school:3,level:60,appearance:[1,0,0],hp:stats.hp,mp:stats.mp,stats,potions:6,effects:skills::State::new(job,3,60,60),guarding:false}
}
#[test]
fn mana_and_cooldowns_cover_all_named_skills_without_touching_legacy(){
    for s in skills::ITEMS.iter(){
        let stats=attributes::balanced_stats(s.job,60,false,[0;5]);
        assert!(b::cost(s,stats)>0&&b::cost(s,stats)<=stats.mp/5+1);
        assert!(b::coefficient(s,5)*5<=24000||s.target!="all_enemies");
        let legacy=vssjx_server::pve_rules::stats(s.job,60,false);
        assert_eq!(b::cost(s,legacy),s.mp_cost);
    }
    let s=skills::ITEMS.iter().find(|s|s.active&&s.target=="all_enemies").unwrap();
    let mut prior=attributes::balanced_stats(s.job,60,false,[0;5]);prior.balance.as_mut().unwrap().skills_revision=0;
    assert_eq!(b::cost(s,prior),s.mp_cost);
    let mut state=skills::State::default();state.activate(prior);assert!(state.balance.is_none());
    let stats=attributes::balanced_stats(s.job,60,false,[0;5]);let mut state=skills::State::default();
    let mut hp=stats.hp;let mut mp=stats.mp;
    state.cast(s,stats,&mut hp,&mut mp,240,99);
    assert_eq!(state.remaining(&s.id),3);state.end_turn();assert_eq!(state.remaining(&s.id),2);
    let encoded=serde_json::to_value(&state).unwrap();let mut state:skills::State=serde_json::from_value(encoded).unwrap();
    state.end_turn();assert_eq!(state.remaining(&s.id),1);state.end_turn();assert_eq!(state.remaining(&s.id),0);
}
#[test]
fn cast_validation_rejects_cooling_skill_without_spending_or_advancing(){
    let s=skills::ITEMS.iter().find(|s|s.active&&s.target=="all_enemies").unwrap();let stats=attributes::balanced_stats(s.job,60,false,[0;5]);
    let mut enemy=population::definitions().into_iter().find(|r|r.id=="spirit").unwrap();enemy.hp=10000;
    let mut battle=Battle::new(enemy,stats.hp,stats.mp,6);battle.frozen_stats=Some(stats);
    battle.turn_selected(Action::Skill,s.job,3,60,stats,0,0,Some(&s.id),99).unwrap();
    let before=serde_json::to_value(&battle).unwrap();
    assert_eq!(battle.turn_selected(Action::Skill,s.job,3,60,stats,0,0,Some(&s.id),99),Err("SKILL_COOLDOWN"));
    assert_eq!(serde_json::to_value(&battle).unwrap(),before);
}
#[test]
fn dot_ticks_once_per_complete_round_and_independent_teammates_keep_their_sources(){
    let s=skills::ITEMS.iter().find(|s|s.active&&matches!(s.effect.as_str(),"bleed"|"poison")).unwrap();
    let mut enemy=population::definitions().into_iter().find(|r|r.id=="spirit").unwrap();enemy.hp=100000;
    // Production hit rolls are intentionally independent; retry fresh samples rather than
    // making an ordinary 5% miss turn this persistence assertion into a flaky test.
    let mut observed=false;
    for _ in 0..50{
        let mut battle=team_rules::Battle::new("qingyun_trail".into(),vec![fighter(s.job),fighter(s.job)],vec![enemy.clone()],1000);
        for i in 0..2{battle.act(battle.fighters[i].id,"skill",Some("m0"),Some(&s.id),2000+i as i64,99).unwrap();}
        assert!(battle.enemies[0].dots.len()<=2);
        if battle.enemies[0].dots.len()==2{
            assert!(battle.enemies[0].dots.values().all(|(ticks,_)|*ticks==2));
            assert_eq!(battle.events.iter().filter(|e|e.action=="dot").count(),1);observed=true;break;
        }
    }
    assert!(observed,"Independent casters must coexist after landed casts");
}
#[test]
fn monster_spell_turns_respect_silence_and_boss_budget_counts_the_whole_encounter(){
    let spirit=population::definitions().into_iter().find(|r|r.id=="spirit").unwrap();
    assert!(b::monster_magical(&spirit,3,100,false));assert!(!b::monster_magical(&spirit,3,100,true));assert!(!b::monster_magical(&spirit,2,100,false));
    let boss=population::definitions_for("ancient_ruins").into_iter().find(|r|r.id=="boss").unwrap();let single=b::monster(boss.clone()).hp;
    let battle=team_rules::Battle::new("ancient_ruins".into(),(0..5).map(|_|fighter(1)).collect(),vec![boss,spirit],1000);
    assert_eq!(battle.enemies.iter().map(|e|e.hp).sum::<i32>(),single*42/10);
}

#[test]
fn pvp_isolated_survivability_does_not_change_world_stats(){
    let stats=attributes::balanced_stats(1,60,false,[60,0,180,60,0]);
    let profile=attributes::profile_for(stats,1,60,[60,0,180,60,0]);
    let snapshot=serde_json::json!({"state":{"battle":null,"stats":stats,"attributes":profile,"character":{"id":Uuid::new_v4(),"display_name":"同道","job":1,"gender":0,"school":3,"level":60}}});
    let fighter=vssjx_server::duel::Fighter::from_snapshot(&snapshot,[1,0,0]).unwrap();
    assert_eq!(fighter.hp,stats.hp*15/10);assert_eq!(fighter.stats.attack,stats.attack);
    assert_eq!(snapshot["state"]["stats"]["hp"],stats.hp);
    assert_eq!(b::n("pvp_damage_bp"),3500);
}
