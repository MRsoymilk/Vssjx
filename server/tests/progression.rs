use vssjx_server::{loot,progression,shop};
use uuid::Uuid;
#[test]
fn original_and_ai_art_drop_equally_across_classes_genders_slots_and_encounters(){
    let mut originals=std::collections::BTreeSet::new();let mut qualities=std::collections::BTreeSet::new();
    assert_eq!(progression::n("original_appearance_percent"),50);
    for job in 0..3{for gender in 0..2{for boss in [false,true]{
        let mut state=loot::State::default();state.focus="weapon".into();let mut counts=std::collections::BTreeMap::new();
        for seed in 0..2048{
            let full=seed%2==0;
            state.reward(job,gender,60,boss,if full{60}else{0},seed*7919);
            assert!(state.valid(job,gender));
            assert!(if full{state.items.is_empty()}else{state.pending.is_empty()});
            for item in state.items.drain(..).chain(state.pending.drain(..)){
                assert!(!item.legacy&&!item.bound);assert_eq!(item.level,60);
                let native=item.template.starts_with("original/");
                assert!(native||item.template.starts_with("ai/"));
                assert!(state.skins.contains(&item.template));
                counts.entry(item.slot().to_owned()).or_insert([0_usize;2])[usize::from(!native)]+=1;
                qualities.insert((native,item.quality.clone()));
                if native{originals.insert(item.template);}
            }
        }
        for slot in shop::SLOTS{let values=counts[slot];let total=values.iter().sum::<usize>();for count in values{assert!(count*100>=total*25&&count*100<=total*75,"job {job} gender {gender} {slot} boss {boss}: {values:?}");}}
    }}}
    let catalog:std::collections::BTreeSet<_>=shop::ITEMS.iter().filter(|d|d.equipment()&&d.id.starts_with("original/")).map(|d|d.id.clone()).collect();
    assert_eq!(originals,catalog,"Every original equipment template is reachable through actual rewards");
    for native in [false,true]{for quality in ["white","blue","yellow","orange","green"]{assert!(qualities.contains(&(native,quality.into())));}}
}
#[test]
fn drops_ignore_class_focus_and_retain_item_level_and_both_pity_guarantees(){
    let mut seen=std::collections::BTreeSet::new();
    for job in 0..3{for gender in 0..2{for slot in shop::SLOTS{
        let mut s=loot::State::default();s.focus=slot.into();let mut focused=0;let mut drops=0;let mut drought=0;
        for seed in 0..512{
            s.reward(job,gender,60,false,0,seed*7919+job as u32*104729+gender as u32*1717);
            assert!(s.valid(job,gender));
            if s.items.is_empty(){drought+=1;assert!(drought<8);}else{drought=0;}
            for i in s.items.drain(..){drops+=1;focused+=usize::from(i.slot()==slot);assert_eq!(i.level,60);if let Some(id)=i.legendary.or(i.set_id){seen.insert(id);}}
        }
        assert!(focused*100<drops*30,"Historical focus must not filter random drops");
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
#[test]
fn unfocused_nonpity_first_drops_cover_every_set_slot_for_every_build(){
    for job in 0..3{
        let mut counts=std::collections::BTreeMap::new();
        for seed in 0..12288{
            let mut state=loot::State::default();
            state.reward(job,0,60,true,0,seed);
            let item=&state.items[0];
            if let Some(build)=&item.set_id{*counts.entry((build.clone(),item.slot().to_owned())).or_insert(0)+=1;}
        }
        for build in vssjx_server::builds::DATA["items"].as_array().unwrap().iter().filter(|b|b["job"]==job){
            for slot in vssjx_server::builds::DATA["set_slots"].as_array().unwrap(){
                let key=(build["id"].as_str().unwrap().to_owned(),slot.as_str().unwrap().to_owned());
                assert!(counts.get(&key).copied().unwrap_or(0)>=10,"Natural first drops must cover {key:?}, without focus or pity");
            }
        }
    }
}
#[test]
fn every_upgrade_improves_nonzero_base_stats_even_on_low_level_accessories(){
    for slot in shop::SLOTS{
        let template=shop::ITEMS.iter().find(|d|d.slot==slot&&d.equip_error(0,0).is_none()).unwrap();
        for level in 1..=60{
            let mut item=loot::roll(&template.id,level,"yellow",17,Uuid::new_v4()).unwrap();
            let original=item.clone();let mut previous=item.base();
            for rank in 1..=6{
                item.upgrade=rank;let next=item.base();
                for (before,after) in [previous.0,previous.1,previous.2,previous.3].into_iter().zip([next.0,next.1,next.2,next.3]){
                    assert!(if before==0{after==0}else{after>before},"{slot} level {level} +{rank}: {before} -> {after}");
                }
                previous=next;
            }
            let restored:loot::Item=serde_json::from_value(serde_json::to_value(&item).unwrap()).unwrap();
            assert_eq!(restored.base(),previous);assert_eq!(restored.id,original.id);assert_eq!(restored.affixes,original.affixes);
            if slot=="wrist"&&level==15{assert_eq!(restored.base().1,14);}
            if slot=="ring"&&level==8{assert_eq!(restored.base().3,14);}
        }
    }
}
