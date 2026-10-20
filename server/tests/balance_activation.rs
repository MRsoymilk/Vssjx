use vssjx_server::{attributes,population,pve_rules::{Battle,Action,Stats}};

#[test]
fn active_profiles_include_two_channels_and_allocation_inputs(){
    for job in 0..3{
        for level in 1..=60{
            let a=[level,level,level,level,level];
            let mut s=attributes::balanced_stats(job,level,false,a);
            let b=s.balance.unwrap();
            attributes::gear_bonus(&mut s,14,27);
            assert_eq!(s.balance.unwrap().physical_attack,b.physical_attack+14);
            assert_eq!(s.balance.unwrap().magic_defense,b.magic_defense+27);
            assert_eq!(attributes::profile_for(s,job,level,a)["formula_revision"],3);
            assert_eq!(serde_json::from_value::<Stats>(serde_json::to_value(s).unwrap()).unwrap().balance.unwrap().level,level);
        }
    }
}

#[test]
fn frozen_solo_rules_ignore_later_character_stats(){
    let s=attributes::balanced_stats(0,30,false,[30,0,90,30,0]);
    let enemy=population::definitions().into_iter().find(|r|r.id=="wolf_a").unwrap();
    let mut battle=Battle::new(enemy,s.hp,s.mp,6);battle.frozen_stats=Some(s);
    // Guard has no critical/hit randomness affecting the MP result.
    let newer=attributes::balanced_stats(0,60,false,[0;5]);
    battle.turn_selected(Action::Guard,0,3,30,newer,0,0,None,99).unwrap();
    assert_eq!(battle.mp,s.mp);
    assert!(battle.frozen_stats.unwrap().balance.is_some());
    let old:Battle=serde_json::from_value(serde_json::json!({"id":uuid::Uuid::new_v4(),"enemy":battle.enemy,"hp":100,"mp":30,"potions":6,"enemy_hp":62,"round":0,"revision":0,"outcome":"active"})).unwrap();
    assert!(old.frozen_stats.is_none());
}

#[test]
fn modern_mitigation_and_rating_caps_are_used_by_live_adapters(){
    let s=attributes::balanced_stats(2,60,false,[80,160,0,0,60]);
    let magic=attributes::for_attack(s,2,true);let physical=attributes::for_attack(s,2,false);
    assert!(magic.attack>physical.attack);
    assert!(attributes::defense(s,true)>attributes::defense(s,false));
    assert!(attributes::direct_damage(magic,10000,10000,0)>1);
    assert_eq!(attributes::hit_chance(Some(s),Some(s),true),9500);
    let mut effects=vssjx_server::skills::State::default();
    assert_eq!(attributes::critical_at(s,true,&mut effects,100,0),150);
    assert_eq!(attributes::critical_at(s,true,&mut effects,100,9999),100);
}
