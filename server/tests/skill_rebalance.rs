use uuid::Uuid;
use vssjx_server::{attributes, population, pve_rules, skills, skill_balance, team_rules::{Battle,Fighter}};
fn fighter(job:i16,attack:i32)->Fighter{
    let stats=pve_rules::Stats{hp:10000,mp:1000,attack,defense:100,attributes:[0;5],balance:None};
    Fighter{id:Uuid::new_v4(),name:"技能验证".into(),job,gender:0,school:3,level:60,appearance:[0;3],
        hp:1,mp:stats.mp,stats,potions:6,effects:skills::State::new(job,3,60,1),guarding:false}
}
#[test]
fn three_hundred_percent_overrides_cannot_be_silently_capped_by_generic_group_rules(){
    for id in ["sheet_015","sheet_037","sheet_006","sheet_042","sheet_008"]{
        let skill=skills::item(id).unwrap();
        for count in [1,2,5]{assert_eq!(skill_balance::coefficient(skill,count),30000);}
    }
    assert_eq!(skills::item("sheet_045").unwrap().target,"all_enemies");
    assert_eq!(skills::ITEMS.iter().filter(|s|s.name=="横扫千军").count(),1);
}
#[test]
fn wanjian_has_exactly_seventy_percent_critical_chance_in_both_rule_versions(){
    for modern in [false,true]{
        let stats=if modern{attributes::balanced_stats(1,60,false,[0;5])}else{fighter(1,100).stats};
        let mut state=skills::State::new(1,3,60,1);state.last_skill="sheet_008".into();
        let count=(0..10000).filter(|roll|attributes::critical_at(stats,false,&mut state,100,*roll)>100).count();
        assert_eq!(count,7000);
        let count=(0..100).filter(|roll|state.critical(100,*roll)>100).count();assert_eq!(count,70);
        state.reset_turn();assert_eq!(attributes::critical_at(stats,false,&mut state,100,6999),100,"Specific crit does not leak to the following attack");
    }
}
#[test]
fn heal_is_immediate_attack_based_and_group_uses_the_caster_not_the_recipient(){
    for id in ["sheet_039","sheet_041"]{
        let skill=skills::item(id).unwrap();
        for maximum in [10000,20000]{
            let mut stats=fighter(2,137).stats;stats.hp=maximum;
            let mut state=skills::State::new(2,3,60,1);let(mut hp,mut mp)=(1,1000);
            assert_eq!(state.cast(skill,stats,&mut hp,&mut mp,0,99),0);
            assert_eq!((hp,state.last_healed,state.regen),(138,137,0));
            state.after_player(&mut hp,maximum);state.end_balance_round(&mut hp,maximum);assert_eq!(hp,138);
        }
    }
    let a=fighter(2,137);let id=a.id;let b=fighter(1,9000);
    let mut enemy=population::definitions().into_iter().find(|e|e.id=="wolf_a").unwrap();enemy.hp=100000;enemy.attack=1;
    let mut battle=Battle::new("qingyun_trail".into(),vec![a,b],vec![enemy],1000);
    battle.act(id,"skill",None,Some("sheet_041"),2000,99).unwrap();
    battle.act(battle.fighters[1].id,"guard",None,None,2001,99).unwrap();
    let heals:Vec<_>=battle.events.iter().filter(|e|e.skill=="sheet_041").collect();
    assert_eq!(heals.len(),2);assert!(heals.iter().all(|e|e.healed==137));
    assert_eq!(battle.fighters[0].effects.proficiency.0["sheet_041"],1);
}
#[test]
fn poison_ticks_exact_own_attack_independent_of_enemy_defense(){
    let skill=skills::item("sheet_052").unwrap();assert!(skill.unreflectable);
    for modern in [false,true]{for defense in [0,100000]{
        let stats=if modern{attributes::balanced_stats(1,60,false,[0;5])}else{fighter(1,137).stats};
        let mut state=skills::State::new(1,3,60,1);let(mut hp,mut mp)=(stats.hp,1000);
        state.cast(skill,stats,&mut hp,&mut mp,defense,99);
        assert!(state.poison_fixed);assert_eq!(state.poison_damage,stats.attack);
        let mut state:skills::State=serde_json::from_value(serde_json::to_value(state).unwrap()).unwrap();
        let damage=if modern{state.end_balance_round(&mut hp,stats.hp)}else{state.after_player(&mut hp,stats.hp)};
        assert_eq!(damage,stats.attack);
    }}
}
#[test]
fn all_skills_are_ready_even_in_saved_cooldowns_and_can_cast_consecutively(){
    for skill in skills::ITEMS.iter().filter(|s|s.active){
        let mut state=skills::State::new(skill.job,3,60,1);
        let stats=attributes::balanced_stats(skill.job,60,false,[0;5]);state.enable_stun(stats);
        state.balance.as_mut().unwrap().cooldowns.insert(skill.id.clone(),3);
        assert_eq!(state.remaining(&skill.id),0);assert_eq!(skill_balance::cooldown(skill),0);
    }
    let mut a=fighter(0,100);a.hp=a.stats.hp;let id=a.id;
    let mut enemy=population::definitions().into_iter().find(|e|e.id=="wolf_a").unwrap();enemy.hp=100000;enemy.attack=1;
    let mut battle=Battle::new("qingyun_trail".into(),vec![a],vec![enemy;5],1000);
    for _ in 0..2{battle.act(id,"skill",Some("m4"),Some("user_hengsao_qianjun"),battle.selection_starts_ms+1,99).unwrap();}
    assert_eq!(battle.fighters[0].effects.proficiency.0["user_hengsao_qianjun"],2);
    assert_eq!(battle.fighters[0].mp,970);
}
