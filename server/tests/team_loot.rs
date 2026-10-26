use vssjx_server::{loot,team_loot::Pool,team_rules::Fighter,attributes,skills};use uuid::Uuid;
fn fighters()->Vec<Fighter>{(0..3).map(|_|{let stats=attributes::balanced_stats(1,60,false,[0;5]);Fighter{id:Uuid::new_v4(),name:"骰子验证".into(),job:1,gender:0,school:3,level:60,appearance:[0;3],stats,hp:stats.hp,mp:stats.mp,potions:3,effects:skills::State::new(1,3,60,60),guarding:false}}).collect()}
fn pool(f:&[Fighter])->Pool{Pool::new(vec![loot::roll("sword",30,"yellow",17,Uuid::new_v4()).unwrap()],f,1000)}
#[test]
fn highest_committed_roll_wins_and_players_cannot_change_decisions(){
    let f=fighters();let mut p=pool(&f);let id=p.drops[0].item.id;
    p.choose(f[0].id,id,Some(61),1001).unwrap();assert_eq!(p.choose(f[0].id,id,Some(100),1002),Err("TEAM_LOOT_DECIDED"));
    assert_eq!(p.choose(Uuid::new_v4(),id,Some(100),1002),Err("TEAM_NOT_PARTICIPATING"));
    p.choose(f[1].id,id,None,1003).unwrap();p.choose(f[2].id,id,Some(87),1004).unwrap();
    assert_eq!(p.drops[0].winner,Some(f[2].id));assert!(p.drops[0].resolved);assert!(!p.drops[0].delivered,"Inventory delivery is a separate part of the caller's transaction");
    let saved=serde_json::to_value(&p).unwrap();let p:Pool=serde_json::from_value(saved.clone()).unwrap();assert_eq!(serde_json::to_value(p).unwrap(),saved);
}
#[test]
fn passing_and_timeouts_never_compete_with_actual_rolls(){
    let f=fighters();let mut p=pool(&f);let id=p.drops[0].item.id;
    p.choose(f[0].id,id,Some(1),1001).unwrap();p.resolve(61000);assert_eq!(p.drops[0].winner,Some(f[0].id));assert_eq!(p.drops[0].choices.len(),3);
    let mut p=pool(&f);p.resolve(61000);assert!(p.drops[0].winner.is_none());assert!(p.drops[0].delivered);assert!(!p.pending());
    assert_eq!(p.choose(f[0].id,p.drops[0].item.id,Some(100),61001),Err("TEAM_LOOT_EXPIRED"));
}
#[test]
fn tied_highest_rolls_get_a_fair_finite_tiebreak_and_lower_rolls_cannot_win(){
    let f=fighters();let mut p=pool(&f);let id=p.drops[0].item.id;
    for (i,n) in [99,99,98].into_iter().enumerate(){p.choose(f[i].id,id,Some(n),1001).unwrap();}
    assert_eq!(p.drops[0].tie_scores.len(),2);assert!(!p.drops[0].tie_scores.contains_key(&f[2].id));
    assert_ne!(p.drops[0].tie_scores[&f[0].id],p.drops[0].tie_scores[&f[1].id]);
    let winner=p.drops[0].tie_scores.iter().max_by_key(|(_,n)|**n).unwrap().0;assert_eq!(p.drops[0].winner,Some(*winner));
}
#[test]
fn all_participants_can_roll_cross_class_gender_and_level_equipment(){
    let mut f=fighters();f[1].job=2;f[2].level=1;
    let item=loot::roll("ai/eva01/mfs/weapon",30,"yellow",17,Uuid::new_v4()).unwrap();let id=item.id;
    let mut p=Pool::new(vec![item,loot::roll("sword",1,"blue",29,Uuid::new_v4()).unwrap()],&f,1000);
    assert_eq!(p.drops[0].eligible,f.iter().map(|fighter|fighter.id).collect::<Vec<_>>());
    p.choose(f[0].id,id,Some(100),1001).unwrap();p.choose(f[1].id,id,Some(41),1002).unwrap();p.choose(f[2].id,id,None,1003).unwrap();
    assert!(p.drops[0].resolved);assert_eq!(p.drops[0].winner,Some(f[0].id));assert!(!p.drops[1].resolved);
}
#[test]
fn original_reward_instances_enter_party_pools_with_normal_eligibility_and_identity(){
    let mut f=fighters();f[1].job=0;f[2].gender=1;
    let mut seen=std::collections::BTreeSet::new();
    for slot in ["weapon","armor","hat"]{for seed in 0..64{
        let mut state=loot::State::default();state.focus=slot.into();state.reward(1,0,60,true,0,seed*7919);
        let original=state.items.clone();let mut p=Pool::new(state.items,&f,1000);
        for (index,item) in original.iter().enumerate(){
            assert_eq!(&p.drops[index].item,item);
            assert_eq!(p.drops[index].eligible,f.iter().map(|fighter|fighter.id).collect::<Vec<_>>());
            if item.template.starts_with("original/"){
                seen.insert(item.slot().to_owned());
                p.choose(f[0].id,item.id,Some(100),1001).unwrap();
            }
        }
        p.resolve(61000);
        for (index,item) in original.iter().enumerate(){if item.template.starts_with("original/"){assert_eq!(p.drops[index].winner,Some(f[0].id));assert_eq!(&p.drops[index].item,item);}}
    }}
    for slot in ["weapon","armor","hat"]{assert!(seen.contains(slot));}
}
