use serde_json::json;
use vssjx_server::{attributes,skills};
fn main(){
    let mut result=Vec::new();
    for s in skills::ITEMS.iter(){
        let stats=attributes::balanced_stats(s.job,60,false,[60,60,60,60,60]);
        let stats=attributes::for_attack(stats,s.job,s.job==2);
        for targets in [1,5]{
            let mut state=skills::State::new(s.job,3,60,60);state.activate(stats);state.balance.as_mut().unwrap().targets=targets;
            let mut hp=100;let mut mp=stats.mp;
            let damage=state.cast(s,stats,&mut hp,&mut mp,240,0);
            let immediate=state.after_player(&mut hp,stats.hp);
            let dot=state.end_balance_round(&mut hp,stats.hp);
            state.end_turn();
            result.push(json!({"id":s.id,"stats":stats,"targets":targets,"damage":damage,"immediate":immediate,"dot":dot,"hp":hp,"mp":mp,"state":state}));
        }
    }
    println!("{}",json!(result));
}
