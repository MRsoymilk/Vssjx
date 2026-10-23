use super::*;

fn player(job:i16,level:i32,revision:i16)->(Loaded,Context){
    let id=Uuid::new_v4();
    let character=Character{id,display_name:"恢复验证".into(),name_rules_version:crate::characters::NAME_RULES_VERSION.into(),
        rules_version:crate::characters::RULES_VERSION.into(),job,gender:0,school:3,level,xp:0,gold:1000,hp:1,mp:0,
        quest_stage:0,map_id:"qingyun_trail".into(),cell_x:4,cell_y:4,state_revision:"0".into(),corpse:None,
        balance_revision:revision,balance_respec_available:false};
    let loaded=Loaded{character,rules:Default::default(),gathering:json!({}),endless:Default::default(),
        hunt_pressure:Default::default(),ai:Default::default(),defeated:0,respawns:Default::default(),battle:None,
        potions:6,equipped:false,weapon_owned:false,allocated:[0;5],gear:Default::default(),quantities:Default::default(),loot:Default::default()};
    let context=Context{character:id,session:Uuid::new_v4(),owner:0,connection_epoch:0,cell:[4,4],target_cell:None,
        moving:false,map_id:"qingyun_trail".into(),position_revision:0,duel_active:false};
    (loaded,context)
}
fn use_item(id:&str)->Command{
    Command{operation_id:Uuid::new_v4(),action:Action::Use,target:Some(id.into()),battle_id:None,expected_revision:Some("0".into()),
        attributes:None,quantity:Some(1),enemy_slot:None,encounter_version:None}
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
            item.equipped=true;item.upgrade=6;
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
