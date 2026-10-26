use vssjx_server::{skill_proficiency::Progress,skills};

#[test]
fn ranks_advance_every_twenty_casts_and_stop_at_fifteen(){
    let mut progress=Progress::default();
    assert_eq!(progress.level("sheet_010"),1);
    for used in 1..=400{
        let rank=progress.record("sheet_010");
        assert_eq!(rank,(1+used/20).min(15) as u8);
    }
    assert_eq!(progress.0["sheet_010"],280);
    assert_eq!(progress.level("sheet_003"),1);
    assert!(progress.valid(0,60));
    assert!(!progress.valid(1,60));
    assert!(!progress.valid(0,1));
}

#[test]
fn unknown_and_passive_skills_cannot_be_trained(){
    let mut progress=Progress::default();
    progress.record("invented");progress.record("sheet_014");
    assert!(progress.is_empty());
    assert!(serde_json::from_str::<Progress>(r#"{"sheet_010":-1}"#).is_err());
    let over:Progress=serde_json::from_str(r#"{"sheet_010":281}"#).unwrap();
    assert!(!over.valid(0,60));
}

#[test]
fn old_and_saved_battle_states_keep_training_and_freeze_the_cast_rank(){
    let mut state=skills::State::new(0,3,60,1);
    for _ in 0..99{state.practice("sheet_010");}
    assert_eq!(state.last_skill_level,5);
    state.reset_turn();assert_eq!(state.last_skill_level,0);
    state.practice("sheet_010");assert_eq!(state.last_skill_level,6);
    let encoded=serde_json::to_value(&state).unwrap();
    let restored:skills::State=serde_json::from_value(encoded).unwrap();
    assert_eq!(restored.proficiency,state.proficiency);
    let legacy:skills::State=serde_json::from_str("{}").unwrap();
    assert!(legacy.proficiency.is_empty());
}

#[test]
fn queued_team_actions_train_only_the_caster_once_after_resolution(){
    use vssjx_server::{pve_rules,team_rules,population};
    use uuid::Uuid;
    let fighter=|job|{
        let stats=pve_rules::stats(job,60,false);
        team_rules::Fighter{id:Uuid::new_v4(),name:"修士".into(),job,gender:0,school:3,level:60,
            appearance:[1,0,0],hp:stats.hp,mp:stats.mp,stats,potions:6,effects:skills::State::new(job,3,60,1),guarding:false}
    };
    let mut a=fighter(0);a.effects.proficiency.0.insert("user_hengsao_qianjun".into(),19);
    let mut b=fighter(2);b.effects.proficiency.0.insert("sheet_041".into(),179);
    let ids=[a.id,b.id];
    let mut enemy=population::definitions().into_iter().find(|e|e.id=="wolf_a").unwrap();enemy.hp=100000;enemy.attack=1;
    let mut battle=team_rules::Battle::new("qingyun_trail".into(),vec![a,b],vec![enemy.clone(),enemy],1000);
    battle.act(ids[0],"skill",Some("m0"),Some("user_hengsao_qianjun"),2000,99).unwrap();
    assert_eq!(battle.fighters[0].effects.proficiency.0["user_hengsao_qianjun"],19,"Submitting an intent is not casting");
    battle.act(ids[1],"skill",None,Some("sheet_041"),2001,99).unwrap();
    assert_eq!(battle.fighters[0].effects.proficiency.0["user_hengsao_qianjun"],20);
    assert!(!battle.fighters[0].effects.proficiency.0.contains_key("sheet_041"));
    assert_eq!(battle.fighters[1].effects.proficiency.0["sheet_041"],180);
    assert_eq!(battle.events.iter().filter(|e|e.skill=="sheet_041"&&e.skill_level==10).count(),2);
    assert_eq!(battle.events.iter().filter(|e|e.skill=="user_hengsao_qianjun"&&e.skill_level==2).count(),2);
}
