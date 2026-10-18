use vssjx_server::{ai_world::{self,Progress},world_map::WorldMap,population::Population};

#[test]
fn entire_directory_is_playable_without_changing_recovered_maps(){
    assert_eq!(ai_world::maps().len(),214);
    for m in ai_world::maps(){
        let id=m["map_id"].as_str().unwrap();
        let map=WorldMap::load(id).unwrap();
        assert_eq!(map.hash(),ai_world::hash());
        let mut population=Population::new(&map);
        assert_eq!(population.residents.len(),m["residents"].as_array().unwrap().len());
        assert!((5..=32).contains(&population.residents.len()));
        for r in &population.residents {assert!(map.route(map.spawn,r.definition.cell).is_some());}
        for _ in 0..20{population.advance(&map,0.1);}
        for r in &population.residents{assert!(map.walkable(r.motion.cell));}
        for q in m["quests"].as_array().unwrap(){
            assert_eq!(ai_world::target_cell(id,q["id"].as_str().unwrap()),Some(population.residents[0].definition.cell));
        }
        let exits=m["exits"].as_array().unwrap();assert!((1..=2).contains(&exits.len()));
        for exit in exits{
            let cell=ai_world::cell(&exit["cell"]);
            assert_ne!(cell,map.spawn);
            assert!(map.route(map.spawn,cell).is_some());
            assert_eq!(ai_world::exit_target(id,cell).as_deref(),exit["target_map"].as_str());
            assert!(WorldMap::load(exit["target_map"].as_str().unwrap()).is_some());
            if let Some(cells)=exit["cells"].as_array(){
                for point in cells{
                    let point=ai_world::cell(point);
                    assert!(map.route(map.spawn,point).is_some());
                    assert_eq!(ai_world::exit_target(id,point).as_deref(),exit["target_map"].as_str());
                }
            }
        }
    }
    assert_eq!(WorldMap::default().map_id,"qingyun_trail");
    for id in ["qingyun_trail","ancient_ruins"]{
        let map=WorldMap::load(id).unwrap();assert!(map.route(map.spawn,ai_world::station(id)).is_some());
    }
    assert!(WorldMap::load("ai_215").is_none());
    for id in ["proposal_blood-altar","proposal_tiandiu-valley"]{assert!(WorldMap::load(id).is_none());}
    assert_eq!(ai_world::exit_target("ai_021",[4,27]),None);
    assert_eq!(ai_world::exit_target("ai_021",[28,27]),None);
    for point in [[19,3],[18,27]]{assert_eq!(ai_world::exit_target("ai_213",point),None);}
}

#[test]
fn ordered_goals_prerequisites_limits_and_single_claim(){
    let mut p=Progress::default();
    assert_eq!(p.accept("ai_001_q2","ai_001",60),Err("AI_PREREQUISITE"));
    assert_eq!(p.accept("ai_001_q1","ai_002",60),Err("AI_INVALID_TARGET"));
    assert_eq!(p.accept("ai_050_q1","ai_050",1),Err("AI_LEVEL_REQUIRED"));
    p.accept("ai_001_q1","ai_001",1).unwrap();
    assert!(!p.event("interact","ai_001_courier"));
    assert_eq!(p.claim("ai_001_q1"),Err("QUEST_NOT_READY"));
    assert!(p.event("interact","ai_001_survey"));
    assert!(!p.event("interact","ai_001_survey"));
    assert!(p.event("interact","ai_001_courier"));
    p.claim("ai_001_q1").unwrap();
    assert_eq!(p.claim("ai_001_q1"),Err("QUEST_NOT_READY"));
    p.accept("ai_001_q2","ai_001",1).unwrap();
    assert!(!p.event("kill","ai_002_mob"));
    p.event("kill","ai_001_mob");
    assert_eq!(p.claim("ai_001_q2"),Err("QUEST_NOT_READY"));
    p.event("kill","ai_001_mob");p.claim("ai_001_q2").unwrap();
    p.accept("ai_001_q3","ai_001",1).unwrap();
    p.accept("ai_002_q1","ai_002",60).unwrap();
    p.accept("ai_003_q1","ai_003",60).unwrap();
    assert_eq!(p.accept("ai_004_q1","ai_004",60),Err("AI_QUEST_LIMIT"));
    assert!(p.valid());
    let view=p.view("ai_002");
    assert_eq!(view["completed_count"],2);
    assert_eq!(view["completed"].as_array().unwrap().len(),0);
    assert!(serde_json::to_vec(&view).unwrap().len()<1024);
    p.active.insert("invented".into(),vec![999]);assert!(!p.valid());
}
