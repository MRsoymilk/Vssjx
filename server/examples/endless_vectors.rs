use vssjx_server::endless::{Progress,Run};use serde_json::json;
fn main(){let mut rows=vec![];for level in [1,15,30,60]{for stage in [1,2,5,10,50,100]{let run=Run{stage,level};rows.push(json!({"run":run,"enemy":run.monster().unwrap()}));}}
    let mut progress=Progress::default();let mut steps=vec![];for victory in [true,true,false,true]{let run=progress.begin(15).unwrap();let started=progress.clone();progress.finish(run,victory).unwrap();steps.push(json!({"run":run,"started":started,"victory":victory,"finished":progress}));}
    println!("{}",json!({"monsters":rows,"progress":steps}));
}
