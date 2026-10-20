//! Emit authoritative candidate-kernel results for the real Godot parity test.
use serde_json::json;
use sha2::{Digest, Sha256};
use vssjx_server::combat_balance::{self as balance, Hit};

fn main() {
    let mut vectors = Vec::new();
    for level in [1, 15, 30, 45, 60] {
        for attack in [1, 30, 300, 1_000_000] {
            for defense in [0, 7, 280, 1_000_000] {
                for critical in [false, true] {
                    for guarding in [false, true] {
                        for coefficient in [0, 10_000, 16_000, 30_000] {
                            let input = json!({"attack":attack,"defense":defense,"level":level,
                                "critical":critical,"guarding":guarding,"coefficient_bp":coefficient,
                                "increased_bp":2300,"extra_reduction_bp":1200,"legendary_bp":12000,
                                "penetration_bp":1500,"flat_penetration":5});
                            let hit: Hit = serde_json::from_value(input.clone()).unwrap();
                            vectors.push(json!({"input":input,"expected":balance::damage(&hit).unwrap()}));
                        }
                    }
                }
            }
        }
    }
    let bytes = include_bytes!("../../shared/data/balance-v1.json");
    println!("{}",json!({"version":balance::RULES.version,"rules_sha256":format!("{:x}",Sha256::digest(bytes)),"damage":vectors}));
}
