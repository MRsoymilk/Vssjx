use super::*;

fn player(job:i16,level:i32,revision:i16)->(Loaded,Context){
    let id=Uuid::new_v4();
    let character=Character{skill_proficiency:Json(Default::default()),id,display_name:"恢复验证".into(),name_rules_version:crate::characters::NAME_RULES_VERSION.into(),
        rules_version:crate::characters::RULES_VERSION.into(),job,gender:0,school:3,level,xp:0,gold:1000,hp:1,mp:0,
        quest_stage:0,map_id:"qingyun_trail".into(),cell_x:4,cell_y:4,state_revision:"0".into(),corpse:None,
        balance_revision:revision,balance_respec_available:false};
    let loaded=Loaded{character,incoming_trade:None,rules:Default::default(),gathering:json!({}),endless:Default::default(),
        hunt_pressure:Default::default(),ai:Default::default(),defeated:0,respawns:Default::default(),battle:None,
        potions:6,equipped:false,weapon_owned:false,allocated:[0;5],gear:Default::default(),quantities:Default::default(),loot:Default::default(),gourds:Default::default()};
    let context=Context{character:id,session:Uuid::new_v4(),owner:0,connection_epoch:0,cell:[4,4],target_cell:None,
        moving:false,map_id:"qingyun_trail".into(),position_revision:0,duel_active:false};
    (loaded,context)
}
fn use_item(id:&str)->Command{
    Command{operation_id:Uuid::new_v4(),action:Action::Use,target:Some(id.into()),battle_id:None,expected_revision:Some("0".into()),
        attributes:None,quantity:Some(1),enemy_slot:None,encounter_version:None}
}

#[test]
fn confirmed_wound_medicines_restore_fixed_hp_and_preserve_existing_inventory(){
    for (id,name,healing,price) in [
        ("original/ix15","金疮药",500,5),("original/ix16","小金疮药",800,10),
        ("original/ix17","中金疮药",1000,8),("original/ix18","大金疮药",1500,14),
    ]{
        let item=crate::shop::item(id).unwrap();
        assert_eq!((item.name.as_str(),item.slot.as_str(),item.restore_hp,item.restore_mp,item.price),(name,"consumable",healing,0,price));
        for revision in [0,1]{for job in 0..3{
            let (mut loaded,context)=player(job,60,revision);loaded.allocated=[300,0,0,0,0];
            loaded.gear.insert(id.into(),false);loaded.quantities.insert(id.into(),2);loaded.character.mp=7;
            assert!(loaded.stats().hp>healing+1);
            loaded.apply(&use_item(id),&context).unwrap();
            assert_eq!((loaded.character.hp,loaded.character.mp),(1+healing,7));
            assert_eq!(loaded.quantities[id],1);
            loaded.character.hp=loaded.stats().hp-1;
            loaded.apply(&use_item(id),&context).unwrap();assert_eq!(loaded.character.hp,loaded.stats().hp);
            loaded.gear.insert(id.into(),false);loaded.quantities.insert(id.into(),1);
            assert_eq!(loaded.apply(&use_item(id),&context),Err("HP_FULL"));assert_eq!(loaded.quantities[id],1);
        }}
    }
}

#[test]
fn named_attribute_stones_keep_material_behavior_without_inventing_permanent_points(){
    for (id,name) in [("original/ix31","敏捷石"),("original/ix32","力量石"),("original/ix33","体质石"),("original/ix34","灵性石"),("original/ix35","定力石")]{
        let item=crate::shop::item(id).unwrap();
        assert_eq!((item.name.as_str(),item.slot.as_str(),item.price),(name,"material",35));
        let (mut loaded,context)=player(0,60,1);
        loaded.gear.insert(id.into(),false);loaded.quantities.insert(id.into(),2);
        assert_eq!(loaded.apply(&use_item(id),&context),Err("ITEM_NOT_USABLE"));
        assert_eq!((loaded.character.hp,loaded.character.mp,loaded.allocated),(1,0,[0;5]));
        assert_eq!(loaded.quantities[id],2);
    }
}

#[test]
fn lotus_leaf_chicken_restores_6000_hp_without_retaining_old_mana_effect(){
    const ID:&str="original/ix26";
    let item=crate::shop::item(ID).unwrap();
    assert_eq!((item.name.as_str(),item.slot.as_str(),item.restore_hp,item.restore_mp,item.price),("荷叶烧鸡","consumable",6000,0,6));
    for revision in [0,1]{for job in 0..3{
        let (mut loaded,context)=player(job,1,revision);
        loaded.gear.insert(ID.into(),false);loaded.quantities.insert(ID.into(),2);
        let max_hp=loaded.stats().hp;loaded.character.mp=7;
        loaded.apply(&use_item(ID),&context).unwrap();
        assert_eq!(loaded.character.hp,6001.min(max_hp));assert_eq!(loaded.character.mp,7);
        assert_eq!(loaded.quantities[ID],1);
        assert_eq!(loaded.apply(&use_item(ID),&context),Err("HP_FULL"));assert_eq!(loaded.quantities[ID],1);
    }}
}

#[test]
fn confirmed_ginseng_restores_4000_mana_without_healing_hp_or_wasting_items(){
    const ID:&str="original/ix14";
    let item=crate::shop::item(ID).unwrap();
    assert_eq!((item.name.as_str(),item.slot.as_str(),item.restore_hp,item.restore_mp,item.price),("极品人参","consumable",0,4000,10));
    for revision in [0,1]{for job in 0..3{
        let (mut loaded,context)=player(job,60,revision);
        loaded.gear.insert(ID.into(),false);loaded.quantities.insert(ID.into(),2);
        let max_mp=loaded.stats().mp;
        loaded.apply(&use_item(ID),&context).unwrap();
        assert_eq!(loaded.character.mp,4000.min(max_mp));assert_eq!(loaded.character.hp,1);
        assert_eq!(loaded.quantities[ID],1);
        assert_eq!(loaded.apply(&use_item(ID),&context),Err("HP_FULL"));assert_eq!(loaded.quantities[ID],1);
    }}
}

#[test]
fn confirmed_boneblood_herb_restores_fixed_8000_without_waste_or_changing_mana(){
    const ID:&str="original/ix10";
    let item=crate::shop::item(ID).unwrap();
    assert_eq!((item.name.as_str(),item.slot.as_str(),item.restore_hp,item.restore_mp,item.price),("生骨融血草","consumable",8000,0,10));
    for revision in [0,1]{for job in 0..3{
        let (mut loaded,context)=player(job,60,revision);
        loaded.gear.insert(ID.into(),false);loaded.quantities.insert(ID.into(),3);
        let hp=loaded.stats().hp;
        loaded.character.mp=7;
        loaded.apply(&use_item(ID),&context).unwrap();
        assert_eq!(loaded.character.hp,(1+8000).min(hp));assert_eq!(loaded.character.mp,7);
        assert_eq!(loaded.quantities[ID],2);
        assert_eq!(loaded.apply(&use_item(ID),&context),Err("HP_FULL"));assert_eq!(loaded.quantities[ID],2);
        let mut command=use_item(ID);command.quantity=Some(2);
        assert_eq!(loaded.apply(&command,&context),Err("INVALID_QUANTITY"));assert_eq!(loaded.quantities[ID],2);
    }}
}

#[test]
fn world_potion_matches_battle_healing_for_all_jobs_and_both_rule_revisions(){
    for revision in [0,1]{for job in 0..3{for level in [1,5,30,60]{
        let (mut loaded,context)=player(job,level,revision);let stats=loaded.stats();
        let expected=if revision==1{(stats.hp/5).max(45)}else{45};
        let f=crate::team_rules::Fighter{id:loaded.character.id,name:loaded.character.display_name.clone(),job,gender:0,school:3,level,
            appearance:[1,0,0],stats,hp:1,mp:0,potions:6,effects:crate::skills::State::new(job,3,level,1),guarding:false};
        let mut enemy=population::definitions().remove(0);enemy.hp=10000;enemy.attack=1;
        let mut battle=crate::team_rules::Battle::new(context.map_id.clone(),vec![f],vec![enemy],0);
        battle.act(loaded.character.id,"potion",None,None,1,99).unwrap();
        let healed=battle.events.iter().find(|e|e.action=="potion").unwrap().healed;
        loaded.apply(&use_item("potion"),&context).unwrap();
        assert_eq!(loaded.character.hp-1,expected);assert_eq!(loaded.character.hp-1,healed);
        assert_eq!(loaded.potions,5);assert_eq!(loaded.character.mp,0);
        loaded.character.hp=stats.hp-1;
        loaded.apply(&use_item("potion"),&context).unwrap();
        assert_eq!(loaded.character.hp,stats.hp);assert_eq!(loaded.potions,4);
        assert_eq!(loaded.apply(&use_item("potion"),&context),Err("HP_FULL"));assert_eq!(loaded.potions,4);
    }}}
}

#[test]
fn other_medicine_keeps_its_catalog_amount_and_invalid_uses_do_not_consume(){
    let (mut loaded,context)=player(0,60,1);
    loaded.gear.insert("original/ix1".into(),false);loaded.quantities.insert("original/ix1".into(),2);
    loaded.apply(&use_item("original/ix1"),&context).unwrap();
    assert_eq!(loaded.character.hp,46);assert_eq!(loaded.quantities["original/ix1"],1);
    let mut command=use_item("potion");command.quantity=Some(2);
    assert_eq!(loaded.apply(&command,&context),Err("INVALID_QUANTITY"));assert_eq!(loaded.potions,6);
    command=use_item("potion");command.expected_revision=Some("1".into());
    assert_eq!(loaded.apply(&command,&context),Err("STALE_EQUIPMENT"));assert_eq!(loaded.potions,6);
    loaded.potions=0;
    assert_eq!(loaded.apply(&use_item("potion"),&context),Err("WEAPON_NOT_OWNED"));assert_eq!(loaded.character.hp,46);
}

#[test]
fn equipped_percentage_hp_is_recomputed_before_respec_ratios(){
    for job in 0..3{
        let (mut loaded,context)=player(job,60,1);loaded.allocated=[90,60,90,30,30];
        for slot in ["armor","hat"]{
            let template=crate::shop::ITEMS.iter().find(|d|d.slot==slot&&d.equip_error(job,0).is_none()).unwrap();
            let mut item=crate::loot::roll(&template.id,60,"yellow",17,Uuid::new_v4()).unwrap();
            item.equipped=true;item.bound=true;item.upgrade=6;
            item.affixes=vec![("hp_percent",400),("hp",120),("mana",80),("defense",40)].into_iter().map(|(kind,value)|crate::loot::Affix{kind:kind.into(),value}).collect();
            loaded.loot.items.push(item);
        }
        let original=loaded.loot.clone();assert!(original.valid(job,0));
        loaded.gear.insert("restored/rebirth_pill".into(),false);loaded.quantities.insert("restored/rebirth_pill".into(),2);
        let before=loaded.stats();loaded.character.hp=before.hp/2;loaded.character.mp=before.mp/2;
        let hp=loaded.character.hp;let mp=loaded.character.mp;
        loaded.apply(&use_item("restored/rebirth_pill"),&context).unwrap();let after=loaded.stats();
        assert_eq!(loaded.allocated,[0;5]);assert_eq!(loaded.loot,original);
        assert_eq!(loaded.character.hp,hp*after.hp/before.hp);assert_eq!(loaded.character.mp,mp*after.mp/before.mp);
        assert_eq!(loaded.quantities["restored/rebirth_pill"],1);
        assert_eq!(loaded.apply(&use_item("restored/rebirth_pill"),&context),Err("NO_ALLOCATED_ATTRIBUTES"));
        assert_eq!(loaded.quantities["restored/rebirth_pill"],1);
    }
}

#[test]
fn gourd_purchase_supply_switches_and_empty_containers_are_conservative(){
    let (mut a,c)=player(0,60,1);let maxima=a.stats();
    let mut buy=use_item(crate::gourds::HP);buy.action=Action::Buy;
    a.apply(&buy,&c).unwrap();assert_eq!(a.character.gold,800);
    assert!(a.auto_supply());assert_eq!(a.character.hp,maxima.hp);assert_eq!(a.character.mp,0);
    assert_eq!(a.gourds.0[crate::gourds::HP].remaining,10000-maxima.hp+1);
    let stable=a.gourds.clone();assert!(!a.auto_supply());assert_eq!(a.gourds,stable);
    assert_eq!(a.apply(&buy,&c),Err("ITEM_ALREADY_OWNED"));
    let mut toggle=buy.clone();toggle.action=Action::GourdDisable;toggle.quantity=None;
    a.apply(&toggle,&c).unwrap();a.character.hp=1;assert!(!a.auto_supply());
    a.gourds.0.get_mut(crate::gourds::HP).unwrap().remaining=7;
    toggle.action=Action::GourdEnable;a.apply(&toggle,&c).unwrap();assert!(a.auto_supply());
    assert_eq!(a.character.hp,8);assert_eq!(a.gourds.0[crate::gourds::HP].remaining,0);
    assert_eq!(a.quantities[crate::gourds::HP],1);assert!(a.gourds.valid(&a.gear,&a.quantities));
    let mut discard=buy;discard.action=Action::Discard;a.apply(&discard,&c).unwrap();
    assert!(a.gourds.0.is_empty());assert!(a.gourds.valid(&a.gear,&a.quantities));
}

#[test]
fn gourd_supply_cannot_touch_active_battles_or_resurrect_and_refills_require_npc(){
    let (mut a,mut c)=player(1,30,1);
    let mut command=use_item(crate::gourds::MP);command.action=Action::Buy;a.apply(&command,&c).unwrap();
    let enemy=population::definitions().remove(1);a.battle=Some(Battle::new(enemy,1,0,6));
    assert!(!a.auto_supply());assert_eq!(a.character.mp,0);
    command.action=Action::GourdDisable;command.quantity=None;assert_eq!(a.apply(&command,&c),Err("BATTLE_ACTIVE"));
    a.battle.as_mut().unwrap().outcome="fled".into();assert!(a.auto_supply());
    a.battle=None;a.character.hp=0;a.character.mp=0;assert!(!a.auto_supply());
    a.character.hp=1;a.die([10,14]).unwrap();assert!(!a.auto_supply());
    assert_eq!(a.apply(&command,&c),Err("SOUL_STATE"));
    a.character.corpse=None;a.character.hp=1;
    command.action=Action::GourdRefillMp;command.target=Some("qingwei".into());c.target_cell=Some([10,13]);
    assert_eq!(a.apply(&command,&c),Err("RESIDENT_TOO_FAR"));c.cell=[10,14];
    a.apply(&command,&c).unwrap();assert_eq!(a.gourds.0[crate::gourds::MP].remaining,5000);
    assert_eq!(a.apply(&command,&c),Err("GOURD_FULL"));
    command.target=Some("wolf_a".into());assert_eq!(a.apply(&command,&c),Err("GOURD_NPC_REQUIRED"));
}
