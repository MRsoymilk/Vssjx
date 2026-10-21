use vssjx_server::{endless::{self,Progress,Run},population,ai_world,world_map::WorldMap};
#[test]
fn every_next_stage_gets_stronger_for_all_character_levels(){
    for level in 1..=60{
        let mut last=Run{stage:1,level}.monster().unwrap();
        for stage in 2..=300{
            let next=Run{stage,level}.monster().unwrap();
            assert!(next.hp>last.hp&&next.attack>last.attack&&next.defense>=last.defense);
            assert_eq!(next.level,level);assert_eq!(next.gold,last.gold);assert_eq!(next.xp,last.xp);last=next;
        }
    }
    assert!(Run{stage:0,level:1}.monster().is_err());assert!(Run{stage:1,level:61}.monster().is_err());assert_eq!(Run{stage:1000000,level:60}.monster().unwrap_err(),"ENDLESS_LIMIT");
}
#[test]
fn victories_advance_once_and_restarts_preserve_records_and_entry_level(){
    let mut p=Progress::default();assert!(p.valid());let run=p.begin(15).unwrap();assert_eq!(p.begin(15),Err("BATTLE_ACTIVE"));
    p.finish(run,true).unwrap();assert_eq!((p.stage,p.best,p.level,p.in_progress),(2,1,15,false));assert!(p.finish(run,true).is_err());
    let mut p:Progress=serde_json::from_value(serde_json::to_value(p).unwrap()).unwrap();let run=p.begin(30).unwrap();assert_eq!(run.level,15,"Levelling up does not rewrite the entry-level snapshot");
    p.finish(run,true).unwrap();assert_eq!((p.stage,p.best),(3,2));let run=p.begin(30).unwrap();p.finish(run,false).unwrap();assert_eq!((p.stage,p.best,p.level,p.in_progress),(1,2,0,false));assert_eq!(p.begin(30).unwrap().level,30);
}
#[test]
fn npc_is_added_to_the_hub_without_rewriting_existing_world_or_quest_catalog(){
    let m=WorldMap::load(endless::map()).unwrap();let npc=population::definitions_for(endless::map()).into_iter().find(|d|d.id==endless::npc()).unwrap();assert!(m.walkable(npc.cell));assert_eq!(npc.kind,"npc");
    let source:serde_json::Value=serde_json::from_str(ai_world::BYTES).unwrap();let raw=source["maps"].as_array().unwrap().iter().find(|m|m["map_id"]==endless::map()).unwrap();
    assert_eq!(ai_world::map(endless::map()).unwrap()["residents"].as_array().unwrap().len(),raw["residents"].as_array().unwrap().len()+1);
    assert_eq!(ai_world::map(endless::map()).unwrap()["quests"],raw["quests"]);assert!(ai_world::target_cell(endless::map(),endless::npc()).is_some());assert!(ai_world::target_cell("ai_002",endless::npc()).is_none());
}
#[test]
fn bad_progress_and_unmatched_settlements_cannot_skip_stages(){
    let mut p=Progress{stage:3,best:0,level:15,in_progress:false};assert!(!p.valid());assert!(p.begin(15).is_err());
    let mut p=Progress::default();let run=p.begin(15).unwrap();let before=p.clone();assert!(p.finish(Run{stage:2,..run},true).is_err());assert_eq!(p,before);
    let mut value=serde_json::to_value(p).unwrap();value["best"]=serde_json::json!(-1);let p:Progress=serde_json::from_value(value).unwrap();assert!(!p.valid());
}
