use vssjx_server::{loot,progression,shop};
use uuid::Uuid;
#[test]
fn drops_obey_class_focus_item_level_and_both_pity_guarantees(){
    let mut seen=std::collections::BTreeSet::new();
    for job in 0..3{for gender in 0..2{for slot in shop::SLOTS{
        let mut s=loot::State::default();s.focus=slot.into();let mut focused=0;let mut drops=0;let mut drought=0;
        for seed in 0..160{
            s.reward(job,gender,60,false,0,seed*7919);
            assert!(s.valid(job,gender));
            if s.items.is_empty(){drought+=1;assert!(drought<8);}else{drought=0;}
            for i in s.items.drain(..){drops+=1;focused+=usize::from(i.slot()==slot);assert_eq!(i.level,60);if let Some(id)=i.legendary.or(i.set_id){seen.insert(id);}}
        }
        assert!(focused*100>=drops*65,"Directing loot must visibly favor the selected slot");
        for seed in 0..16{s.reward(job,gender,60,true,60,seed*1717);assert!(s.pending.len()==2);assert!(s.pending.iter().all(|i|i.quality!="white"));if s.bosses%8==0{assert!(s.pending[0].legendary.is_some()||s.pending[0].set_id.is_some());}s.pending.clear();}
        s.reward(job,gender,1,true,0,17);assert!(s.items.iter().all(|i|i.level==1&&i.legendary.is_none()&&i.set_id.is_none()));
    }}}
    assert_eq!(seen.len(),6,"All authored styles can actually drop");
}
#[test]
fn upgrading_is_six_small_base_steps_without_extra_affixes_or_item_loss(){
    let i=loot::roll("sword",60,"yellow",17,Uuid::new_v4()).unwrap();let original=i.clone();let id=i.id;let mut s=loot::State::default();s.items.push(i);s.scrap=10000;s.essence=100;let mut gold=10000;
    for level in 1..=6{progression::craft(&mut s,id,"gear_upgrade",None,&mut gold,17).unwrap();let i=&s.items[0];assert_eq!(i.upgrade,level);assert_eq!(i.affixes,original.affixes);assert_eq!(i.id,id);assert_eq!(i.base().0,original.base().0*(100+2*level)/100);assert!(s.valid(1,0));}
    let before=s.clone();let money=gold;assert_eq!(progression::craft(&mut s,id,"gear_upgrade",None,&mut gold,17),Err("UPGRADE_LIMIT"));assert_eq!(s,before);assert_eq!(gold,money);
}
#[test]
fn reroll_locks_one_slot_preserves_all_other_rolls_and_charges_only_after_validation(){
    let i=loot::roll_special("weapon_2",60,"orange","siphon",17,Uuid::new_v4()).unwrap();let original=i.clone();let id=i.id;let mut s=loot::State::default();s.items.push(i);s.scrap=10000;s.essence=100;let mut gold=100000;
    for roll in 1..=20{progression::craft(&mut s,id,"gear_reroll",Some(0),&mut gold,roll as u32).unwrap();let i=&s.items[0];assert_eq!(i.rerolls,roll);assert_eq!(i.reroll_index,Some(0));assert_eq!(i.affixes[1..],original.affixes[1..]);assert_eq!(i.legendary,original.legendary);assert!(s.valid(2,0));}
    let before=s.clone();let money=gold;assert!(progression::craft(&mut s,id,"gear_reroll",Some(1),&mut gold,1).is_err());assert_eq!(s,before);assert_eq!(gold,money);
    let i=loot::roll("sword",30,"yellow",17,Uuid::new_v4()).unwrap();let id=i.id;s.items=vec![i];s.scrap=0;
    let before=s.clone();assert_eq!(progression::craft(&mut s,id,"gear_upgrade",None,&mut gold,17),Err("MATERIALS_INSUFFICIENT"));assert_eq!(s,before);assert_eq!(gold,money);
}
#[test]
fn salvage_requires_owned_unequipped_nonlegacy_and_retains_unlocked_appearance(){
    let mut s=loot::State::default();let mut i=loot::roll("sword",30,"yellow",17,Uuid::new_v4()).unwrap();i.equipped=true;let id=i.id;s.items.push(i);let mut gold=0;
    let before=s.clone();assert_eq!(progression::craft(&mut s,id,"gear_salvage",None,&mut gold,17),Err("UNEQUIP_BEFORE_SALVAGE"));assert_eq!(s,before);
    s.items[0].equipped=false;progression::craft(&mut s,id,"gear_salvage",None,&mut gold,17).unwrap();assert!(s.items.is_empty());assert_eq!(s.scrap,8);assert!(s.skins.contains("sword"));
    assert_eq!(progression::craft(&mut s,id,"gear_salvage",None,&mut gold,17),Err("INSTANCE_NOT_OWNED"));
    s.sync_legacy(&std::collections::BTreeMap::from([("sword".into(),false)]),1,0);let id=s.items[0].id;assert_eq!(progression::craft(&mut s,id,"gear_salvage",None,&mut gold,17),Err("LEGACY_CRAFT_LOCKED"));
}
#[test]
fn old_battles_do_not_silently_gain_new_reward_rules(){
    let mut b=vssjx_server::pve_rules::Battle::new(vssjx_server::population::definitions().remove(0),100,40,3);assert_eq!(b.loot_revision,1);
    let mut value=serde_json::to_value(&b).unwrap();value.as_object_mut().unwrap().remove("loot_revision");b=serde_json::from_value(value).unwrap();assert_eq!(b.loot_revision,0);
}
