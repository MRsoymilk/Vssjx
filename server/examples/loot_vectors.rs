use serde_json::json;
use uuid::Uuid;
use vssjx_server::{attributes,loot,shop};
fn main(){
    let mut rows=vec![];let mut index=1;
    for job in 0..3{for gender in 0..2{for slot in shop::SLOTS{for level in [1,30,60]{for quality in ["white","blue","yellow"]{
        let template=shop::ITEMS.iter().find(|d|d.slot==slot&&d.equip_error(job,gender).is_none()).unwrap();
        let seed=0x12345678_u32.wrapping_add(index*7919);let id=Uuid::parse_str(&format!("11111111-1111-4111-8111-{index:012}")).unwrap();
        let mut item=loot::roll(&template.id,level,quality,seed,id).unwrap();item.equipped=true;item.bound=true;
        let points=if job==2{[level,level*3,0,0,level]}else{[level,0,level*3,level,0]};
        let mut stats=attributes::balanced_stats(job,level,false,points);let mut state=loot::State::default();state.items.push(item.clone());state.skins.insert(template.id.clone());state.apply_stats(&mut stats,job);
        let mut effects=vssjx_server::skills::State::default();
        rows.push(json!({"job":job,"gender":gender,"seed":seed,"item":item,"points":points,"stats":stats,"profile":attributes::profile_for(stats,job,level,points),"damage":attributes::direct_damage(stats,240,16000,0),"dot":attributes::dot_damage(stats,240,3000),"incoming":attributes::incoming(400,level,stats,false,0),"critical":attributes::critical_at(stats,job==2,&mut effects,100,0),"hit":attributes::hit_chance(Some(stats),None,job==2)}));index+=1;
    }}}}}
    println!("{}",json!(rows));
}
