use vssjx_server::{attributes,builds,loot,shop,skills};
use serde_json::json;
use uuid::Uuid;
fn main(){
    let mut rows=vec![];let mut serial=1;
    for i in 0..6{for gender in 0..2{for (legend,count) in [(false,0),(false,2),(false,4),(true,0),(true,4)]{
        let d=&builds::DATA["items"][i];let job=d["job"].as_i64().unwrap() as i16;let build=d["id"].as_str().unwrap();
        let mut loot=loot::State::default();
        let mut add=|slot:&str,quality:&str|{let template=shop::ITEMS.iter().find(|d|d.equipment()&&d.slot==slot&&d.equip_error(job,gender).is_none()).unwrap();let id=Uuid::parse_str(&format!("22222222-2222-4222-8222-{serial:012}")).unwrap();serial+=1;let mut item=loot::roll_special(&template.id,60,quality,build,17,id).unwrap();item.equipped=true;item.bound=true;loot.items.push(item);};
        if legend{add(d["legend_slot"].as_str().unwrap(),"orange");}
        for slot in builds::DATA["set_slots"].as_array().unwrap().iter().take(count){add(slot.as_str().unwrap(),"green");}
        assert!(loot.valid(job,gender));let mut stats=attributes::balanced_stats(job,60,false,[0;5]);loot.apply_stats(&mut stats,job);
        let ids:&[&str]=match i{0=>&["sheet_012","sheet_010","sheet_010"],1=>&["sheet_025","sheet_025"],2=>&["sheet_003","sheet_003","sheet_004","sheet_004"],3=>&["sheet_052","sheet_051","sheet_051"],4=>&["sheet_039","sheet_017","sheet_017"],_=>&["sheet_047","sheet_018","sheet_018"]};
        let mut state=skills::State::new(job,3,60,60);let mut hp=stats.hp/2;let mut mp=stats.mp;let mut turns=vec![];
        for id in ids{state.reset_turn();state.activate(stats);state.balance.as_mut().unwrap().targets=5;
            let damage=state.cast(skills::item(id).unwrap(),stats,&mut hp,&mut mp,100,0);
            turns.push(json!({"skill":id,"damage":damage,"hp":hp,"mp":mp,"state":state}));
        }
        rows.push(json!({"index":i,"job":job,"gender":gender,"loot":loot,"stats":stats,"turns":turns}));
    }}}
    println!("{}",json!(rows));
}
