use vssjx_server::{loot,progression};use uuid::Uuid;use serde_json::json;
fn main(){
    let mut rewards=vec![];
    for job in 0..3{for gender in 0..2{for level in [1,60]{for focus in ["","weapon","armor","ring","necklace"]{for boss in [false,true]{for pity in [false,true]{
        let mut state=loot::State::default();state.focus=focus.into();if pity{state.kills=7;state.bosses=7;}
        let seed=17+job as u32*1717+gender as u32*7919+level as u32*19;
        let before=state.clone();state.reward(job,gender,level,boss,60,seed);
        rewards.push(json!({"job":job,"gender":gender,"level":level,"boss":boss,"seed":seed,"before":before,"after":state}));
    }}}}}}
    let mut crafts=vec![];
    for job in 0..3{let mut state=loot::State::default();state.scrap=10000;state.essence=100;let template=if job==2{"weapon_2"}else{"sword"};let item=loot::roll(template,60,"yellow",17,Uuid::new_v4()).unwrap();let id=item.id;state.items.push(item);let initial=state.clone();let mut gold=100000;let mut steps=vec![];
        for (action,index,seed) in [("gear_upgrade",None,1),("gear_reroll",Some(1),17),("gear_reroll",Some(1),29),("gear_upgrade",None,2),("gear_salvage",None,3)]{
            let quote=progression::quote(&state.items[0],action).ok();progression::craft(&mut state,id,action,index,&mut gold,seed).unwrap();steps.push(json!({"action":action,"index":index,"seed":seed,"quote":quote,"after":state,"gold":gold}));
        }
        crafts.push(json!({"job":job,"before":initial,"steps":steps}));
    }
    println!("{}",json!({"rewards":rewards,"crafts":crafts}));
}
