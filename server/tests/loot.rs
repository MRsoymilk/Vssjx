use std::collections::BTreeMap;
use uuid::Uuid;
use vssjx_server::{attributes,loot,shop};
#[test]
fn rolls_are_unique_slot_legal_level_bounded_and_immutable_after_serialization(){
    for job in 0..3{for gender in 0..2{for slot in shop::SLOTS{
        let d=shop::ITEMS.iter().find(|d|d.slot==slot&&d.equip_error(job,gender).is_none()).unwrap();
        for level in [1,30,60]{for quality in ["white","blue","yellow"]{
            let id=Uuid::new_v4();let a=loot::roll(&d.id,level,quality,17,id).unwrap();let b=loot::roll(&d.id,level,quality,17,id).unwrap();
            assert_eq!(a,b);assert!(a.valid(job,gender));
            assert_eq!(serde_json::from_value::<loot::Item>(serde_json::to_value(&a).unwrap()).unwrap(),a);
            let mut bad=a.clone();bad.level=61;assert!(!bad.valid(job,gender));
            if !a.affixes.is_empty(){bad=a.clone();bad.affixes[0].value=1000000;assert!(!bad.valid(job,gender));}
        }}
    }}}
    assert!(loot::roll("sword",1,"orange",17,Uuid::new_v4()).is_err());
    assert!(loot::roll("sword",1,"yellow",17,Uuid::nil()).is_err());
}
#[test]
fn legacy_migration_preserves_fixed_stats_ids_and_all_appearances(){
    let mut gear=BTreeMap::new();
    for slot in shop::SLOTS{gear.insert(format!("ai/eva01/mzs/{slot}"),true);}
    let mut state=loot::State::default();state.sync_legacy(&gear,0,0);assert!(state.valid(0,0));let before=state.clone();state.sync_legacy(&gear,0,0);assert_eq!(state,before);
    assert_eq!(state.items.len(),10);assert!(state.items.iter().all(|i|i.affixes.is_empty()&&i.legacy));
    let mut stats=attributes::balanced_stats(0,30,false,[0;5]);let (attack,defense)=shop::bonus(&gear);attributes::gear_bonus(&mut stats,attack,defense);
    let expected=serde_json::to_value(stats).unwrap();state.apply_stats(&mut stats,0);
    assert_eq!(serde_json::to_value(stats).unwrap(),expected,"Legacy rows cannot add fixed bonuses a second time");
    assert_eq!(state.look(shop::appearance(&gear)),shop::appearance(&gear));
}
#[test]
fn instance_equips_replace_legacy_slots_enforce_capacity_and_preserve_other_copies(){
    let mut gear=BTreeMap::from([("sword".into(),true)]);let mut s=loot::State::default();s.sync_legacy(&gear,1,0);
    let a=loot::roll("sword",30,"yellow",1,Uuid::new_v4()).unwrap();let b=loot::roll("sword",30,"yellow",2,Uuid::new_v4()).unwrap();s.items.extend([a.clone(),b.clone()]);
    assert_eq!(s.apply("gear_equip",a.id,&mut gear,29,59),Err("EQUIPMENT_LEVEL_REQUIRED"));
    s.apply("gear_equip",a.id,&mut gear,30,59).unwrap();assert_eq!(gear["sword"],false);assert!(s.valid(1,0));
    assert_eq!(s.apply("gear_equip",a.id,&mut gear,30,59),Err("EQUIPMENT_UNCHANGED"));
    assert_eq!(s.apply("gear_unequip",a.id,&mut gear,30,60),Err("BAG_FULL"));
    assert!(s.items.iter().any(|i|i.id==a.id&&i.equipped));assert!(s.items.contains(&b));
    s.apply("gear_unequip",a.id,&mut gear,30,59).unwrap();
    s.pending.push(loot::roll("sword",1,"blue",3,Uuid::new_v4()).unwrap());let id=s.pending[0].id;
    assert_eq!(s.apply("gear_claim",id,&mut gear,30,60),Err("BAG_FULL"));
    s.apply("gear_claim",id,&mut gear,30,59).unwrap();assert!(s.pending.is_empty());assert!(s.valid(1,0));
    assert_eq!(s.apply("gear_claim",id,&mut gear,30,59),Err("INSTANCE_NOT_OWNED"));
}
#[test]
fn affix_channels_have_actual_combat_effects_and_retain_caps(){
    let mut stats=attributes::balanced_stats(2,60,false,[60,180,0,0,60]);
    let mut i=loot::roll("weapon_2",60,"yellow",17,Uuid::new_v4()).unwrap();
    // Aggregation is exercised separately from validation using hand-authored
    // modifiers, so damage/hit/crit effects cannot pass merely by serialization.
    i.equipped=true;i.affixes=vec![loot::Affix{kind:"power".into(),value:30},loot::Affix{kind:"crit_damage".into(),value:1000},loot::Affix{kind:"dot".into(),value:1000},loot::Affix{kind:"reduction".into(),value:200}];
    let base=stats;let mut s=loot::State::default();s.items.push(i);s.apply_stats(&mut stats,2);
    assert!(stats.attack>base.attack);assert_eq!(stats.balance.unwrap().physical_attack,base.balance.unwrap().physical_attack);
    assert!(attributes::dot_damage(stats,240,3000)>attributes::direct_damage(stats,240,3000,0));
    assert!(attributes::incoming(400,60,stats,false,0)<attributes::incoming(400,60,base,false,0));
    let mut fx=vssjx_server::skills::State::default();assert_eq!(attributes::critical_at(stats,true,&mut fx,100,0),160);
    stats.balance.as_mut().unwrap().reduction_bp=99999;assert_eq!(attributes::extra_reduction(100,stats),75);
}
