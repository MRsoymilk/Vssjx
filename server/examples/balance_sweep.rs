//! Seeded baseline fights using the live revised skill, mitigation and status adapters.
//! Fixed existing gear (+14 attack/+27 defense); not a six-build or loot-economy claim.
use rand::{Rng,SeedableRng,rngs::StdRng};
use serde_json::json;
use vssjx_server::{attributes,skills,skill_balance,population::ResidentDefinition};
fn main(){
    let mut rows=Vec::new();
    for level in [1,15,30,45,60]{for job in 0..3{for boss in [false,true]{
        let a=attributes::balanced_recommended(job,level,[0;5]);let mut stats=attributes::balanced_stats(job,level,false,a);attributes::gear_bonus(&mut stats,14,27);
        let enemy=skill_balance::monster(ResidentDefinition{id:if boss{"boss"}else{"baseline"}.into(),name:"基准妖物".into(),kind:if boss{"boss"}else{"wolf"}.into(),art:"monster/langw".into(),cell:[1,1],level,hp:45+20*level,attack:8+3*level,defense:1+level,gold:0,xp:0});
        let skill=skills::item(&format!("legacy_{job}")).unwrap();let power=attributes::for_attack(stats,job,job==2);
        let mut rng=StdRng::seed_from_u64(17+job as u64*100+level as u64*1000+u64::from(boss));
        let mut wins=0;let mut rounds=0;let mut health=0;
        for _ in 0..1000{
            let mut state=skills::State::new(job,3,level,level);state.activate(stats);
            let mut hp=stats.hp;let mut mp=stats.mp;let mut target=enemy.hp;
            for round in 1..=30{
                state.reset_turn();
                let damage=if mp>=skill_balance::cost(skill,stats)&&state.remaining(&skill.id)==0{state.cast(skill,power,&mut hp,&mut mp,enemy.defense,99)}else{mp=(mp+skill_balance::recovery(stats,"basic_restore_bp",0)).min(stats.mp);attributes::direct_damage(power,enemy.defense,10000,0)};
                let damage=attributes::critical_at(stats,job==2,&mut state,damage,rng.gen_range(0..10000));
                if rng.gen_range(0..10000)<attributes::hit_chance(Some(stats),None,job==2){target=(target-damage).max(0);}
                if target>0&&rng.gen_range(0..10000)<attributes::hit_chance(None,Some(stats),false){hp=(hp-attributes::incoming(enemy.attack,level,stats,false,0)).max(0);}
                let dot=state.end_balance_round(&mut hp,stats.hp);target=(target-dot).max(0);state.end_turn();
                if hp==0||target==0||round==30{if target==0&&hp>0{wins+=1;}rounds+=round;health+=hp;break;}
            }
        }
        let mean=rounds as f64/1000.0;
        assert_eq!(wins,1000,"Same-level baseline with completed fixed gear must be survivable");
        assert!(if boss{if level==1{(4.0..=7.0).contains(&mean)}else{(6.0..=10.0).contains(&mean)}}else{(1.5..=4.0).contains(&mean)},"Baseline pacing drift: job {job}, level {level}, boss {boss}, rounds {mean}");
        rows.push(json!({"level":level,"job":job,"boss":boss,"trials":1000,"wins":wins,"mean_rounds":mean,"mean_hp_percent":health as f64/(1000.0*stats.hp as f64)*100.0}));
    }}}
    println!("{}",json!({"basis":"live-v1 adapters, recommended points, existing +14/+27 fixed gear, single-target baseline; no loot effects", "seeded":true,"total_trials":30000,"results":rows}));
}
