use std::collections::BTreeMap;
use uuid::Uuid;
use vssjx_server::{loot, shop};

#[test]
fn equipment_score_uses_real_stats_and_all_affix_units_without_changing_items() {
    let mut item = loot::roll("sword", 60, "white", 17, Uuid::new_v4()).unwrap();
    assert_eq!(item.score(), 64); // 128 attack, half a point per attack.
    item.upgrade = 6;
    assert_eq!(item.score(), 72); // Actual upgraded base is 143, rounded once.
    item.upgrade = 0;
    item.quality = "yellow".into();
    item.affixes = [("power", 50), ("crit", 20), ("damage", 800), ("penetration", 300)]
        .map(|(kind, value)| loot::Affix { kind: kind.into(), value }).into();
    assert!(item.valid(1, 0));
    assert_eq!(item.score(), 138);
    let before = serde_json::to_value(&item).unwrap();
    let _ = item.score();
    assert_eq!(serde_json::to_value(&item).unwrap(), before);
    assert!(before.get("score").is_none(), "Score is derived, never a saved or client-owned field");
    item.id = Uuid::new_v4(); item.bound = true; item.equipped = true;
    item.skin = Some("sword".into()); item.rerolls = 5; item.reroll_index = Some(0);
    assert_eq!(item.score(), 138, "Identity, binding, appearance and wash count do not create points");
    item.affixes[0].value = 30;
    assert_eq!(item.score(), 128, "The actual rerolled attribute determines the new score");
    let mut state = loot::State::default();
    state.sync_legacy(&BTreeMap::from([("sword".into(), true)]), 1, 0);
    assert_eq!(state.items[0].score(), 3, "Old fixed equipment uses its actual five attack");
}

#[test]
fn equipment_score_vectors_cover_every_slot_level_quality_and_upgrade_in_both_clients() {
    let mut vectors = vec![];
    for job in 0..3 {
        for gender in 0..2 {
            for slot in shop::SLOTS {
                let template = shop::ITEMS.iter().find(|d| d.slot == slot && d.equip_error(job, gender).is_none()).unwrap();
                for level in [1, 30, 60] {
                    for quality in ["white", "blue", "yellow"] {
                        for seed in [17, 29] {
                            let mut item = loot::roll(&template.id, level, quality, seed, Uuid::new_v4()).unwrap();
                            let original_score = item.score();
                            for upgrade in [0, 6] {
                                item.upgrade = upgrade;
                                assert!(item.valid(job, gender));
                                assert!(item.score() >= original_score);
                                vectors.push(serde_json::json!({"item":item,"score":item.score()}));
                            }
                        }
                    }
                }
            }
        }
    }
    if let Ok(path) = std::env::var("SSJX_SCORE_VECTORS") {
        std::fs::write(path, serde_json::to_vec(&vectors).unwrap()).unwrap();
    }
    assert_eq!(vectors.len(), 2160);
}
