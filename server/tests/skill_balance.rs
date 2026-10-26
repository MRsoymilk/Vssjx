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
        assert_eq!(b::cost(s,stats),s.mp_cost);
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
fn more_max_mana_buys_more_casts_without_increasing_any_skill_cost(){
    for s in skills::ITEMS.iter(){
        let mut stats=attributes::balanced_stats(s.job,60,false,[0;5]);
        for max_mp in [1,35,400,800,1000000]{
            stats.mp=max_mp;
            assert_eq!(b::cost(s,stats),s.mp_cost,"{} at max MP {max_mp}",s.id);
        }
        if s.active{
            assert!(800/b::cost(s,stats)>400/b::cost(s,stats));
            let mut state=skills::State::default();let mut hp=stats.hp;let mut mp=400;
            state.cast(s,stats,&mut hp,&mut mp,0,99);
            assert_eq!(mp,400-s.mp_cost,"No hidden max-MP charge on {}",s.id);
        }
    }
}

#[test]
fn solid_guard_blocks_fixed_damage_for_two_rounds_without_increasing_or_overflowing(){
    let s=skills::item("sheet_012").unwrap();
    for stats in [vssjx_server::pve_rules::stats(0,60,false),attributes::balanced_stats(0,60,false,[0;5])]{
        let mut state=skills::State::new(0,3,60,1);let mut hp=stats.hp;let mut mp=stats.mp;
        state.cast(s,stats,&mut hp,&mut mp,0,99);
        assert_eq!((hp,mp),(stats.hp,stats.mp-15));
        assert_eq!((state.defense,state.defense_percent,state.defense_flat),(2,0,25));
        state=serde_json::from_value(serde_json::to_value(&state).unwrap()).unwrap();
        for _ in 0..2{
            for magical in [false,true]{for raw in [0,1,24,25,26,100,10000,i32::MAX]{
                let damage=state.enemy_hit(raw,stats.attack,magical).0;
                assert_eq!(damage,(raw-25).max(0));assert!(damage<=raw);
            }}
            state.end_turn();
        }
        assert_eq!(state.enemy_hit(100,stats.attack,false).0,100);
        // Another defense skill must replace the old fixed shield rather than stack it.
        let other=skills::ITEMS.iter().find(|s|s.effect=="defense"&&s.id!="sheet_012").unwrap();
        state.cast(other,stats,&mut hp,&mut mp,0,99);
        assert_eq!(state.defense_flat,0);assert_eq!(state.defense_percent,other.value);
        assert_eq!(state.enemy_hit(100,stats.attack,false).0,100-other.value);
    }
}

#[test]
fn actual_solo_and_formation_solid_guard_reduces_the_same_monster_hit(){
    let mut stats=vssjx_server::pve_rules::stats(0,25,false);stats.hp=10000;stats.mp=400;
    let mut enemy=population::definitions().into_iter().find(|r|r.id=="wolf_a").unwrap();enemy.hp=100000;enemy.attack=1000;
    let mut solo=Battle::new(enemy.clone(),stats.hp,stats.mp,6);
    let raw=attributes::incoming(enemy.attack,enemy.level,stats,false,0);
    solo.turn_selected(Action::Skill,0,3,25,stats,0,0,Some("sheet_012"),99).unwrap();
    assert_eq!(solo.hp,stats.hp-(raw-25).max(0));assert_eq!(solo.mp,385);
    assert_eq!((solo.skills.defense,solo.skills.defense_flat),(1,25));
    let mut f=fighter(0);f.level=25;f.stats=stats;f.hp=stats.hp;f.mp=stats.mp;f.effects=skills::State::new(0,3,25,1);let id=f.id;
    let mut team=team_rules::Battle::new("qingyun_trail".into(),vec![f],vec![enemy.clone(),enemy],1000);
    team.act(id,"skill",None,Some("sheet_012"),team.selection_starts_ms+1,99).unwrap();
    let hits:Vec<_>=team.events.iter().filter(|e|e.target==id.to_string()&&e.actor!=id.to_string()).collect();
    assert_eq!(hits.len(),2);assert!(hits.iter().all(|e|e.damage==(raw-25).max(0)));
    assert_eq!(team.fighters[0].mp,385);assert_eq!((team.fighters[0].effects.defense,team.fighters[0].effects.defense_flat),(1,25));
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
    let boss=population::definitions_for("ancient_ruins").into_iter().find(|r|r.id=="boss").unwrap();let single=vssjx_server::progression::monster(b::monster(boss.clone())).hp;
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
