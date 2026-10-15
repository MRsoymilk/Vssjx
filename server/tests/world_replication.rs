use sha2::{Digest, Sha256};
use uuid::Uuid;
use vssjx_server::{
    world::Entity,
    world_replication::{Publisher, encode_delta},
};

fn entity(net_id: u32) -> Entity {
    Entity {
        net_id,
        id: Uuid::new_v4(),
        display_name: "青云测试".into(),
        job: 2,
        gender: 0,
        cell: [10, 16],
        next_cell: None,
        segment_progress: 0,
        entity_revision: "0".into(),
        last_input_seq: "0".into(),
        world_epoch: "1".into(),
    }
}
#[test]
fn delta_records_are_compact_and_include_digest_and_lifecycle() {
    let epoch = Uuid::new_v4();
    let first = entity(1);
    let entered = encode_delta(epoch, 1, &[], std::slice::from_ref(&first));
    assert_eq!(&entered[..4], b"VWD2");
    assert_eq!(&entered[4..20], epoch.as_bytes());
    let json_size = u32::from_be_bytes(entered[28..32].try_into().unwrap()) as usize;
    let records: serde_json::Value = serde_json::from_slice(&entered[36..36 + json_size]).unwrap();
    assert_eq!(records[0]["net_id"], 1);
    assert_eq!(records[0]["id"], first.id.to_string());
    assert_eq!(
        &entered[entered.len() - 32..],
        Sha256::digest(&entered[..entered.len() - 32]).as_slice()
    );
    let mut moving = first.clone();
    moving.next_cell = Some([11, 16]);
    moving.segment_progress = 450;
    moving.entity_revision = "1".into();
    moving.last_input_seq = "8".into();
    let update = encode_delta(epoch, 2, std::slice::from_ref(&first), &[moving]);
    assert_eq!(update.len(), 70 + 26);
    assert_eq!(&update[36..38], b"[]");
    assert_eq!(u16::from_be_bytes(update[34..36].try_into().unwrap()), 1);
    assert_eq!(u32::from_be_bytes(update[38..42].try_into().unwrap()), 1);
    assert_eq!(u64::from_be_bytes(update[56..64].try_into().unwrap()), 8);
    let left = encode_delta(epoch, 3, &[first], &[]);
    assert_eq!(left.len(), 74);
    assert_eq!(u16::from_be_bytes(left[32..34].try_into().unwrap()), 1);
}
#[test]
fn quiet_ticks_still_have_a_contiguous_frontier_without_repeating_entities() {
    let epoch = Uuid::new_v4();
    let entities: Vec<_> = (1..=1000).map(entity).collect();
    let packet = encode_delta(epoch, 9, &entities, &entities);
    assert_eq!(packet.len(), 70);
    let mut moved = entities.clone();
    for entity in &mut moved {
        entity.next_cell = Some([11, 16]);
        entity.segment_progress = 450;
        entity.entity_revision = "1".into();
    }
    assert_eq!(encode_delta(epoch, 10, &entities, &moved).len(), 26070);
}

#[test]
fn binary_layout_matches_cross_language_golden_vectors() {
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../../shared/protocol/world-sync-v2.json")).unwrap();
    let epoch = Uuid::parse_str(fixture["golden_epoch"].as_str().unwrap()).unwrap();
    let hex = |bytes: &[u8]| {
        bytes
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    };
    assert_eq!(
        hex(&encode_delta(epoch, 7, &[], &[])),
        fixture["golden_quiet_seq7_hex"].as_str().unwrap()
    );
    let first = entity(1);
    let mut moving = first.clone();
    moving.next_cell = Some([11, 16]);
    moving.segment_progress = 450;
    moving.entity_revision = "1".into();
    moving.last_input_seq = "7".into();
    assert_eq!(
        hex(&encode_delta(epoch, 8, &[first], &[moving])),
        fixture["golden_motion_seq8_hex"].as_str().unwrap()
    );
}
#[tokio::test]
async fn baseline_is_immutable_encoding_is_shared_and_lag_is_explicit() {
    let publisher = Publisher::default();
    let actor = entity(1);
    publisher.publish(1, vec![actor.clone()]);
    let (baseline, mut updates) = publisher.subscribe();
    assert_eq!(baseline.seq, 1);
    assert_eq!(baseline.source_revision, 1);
    assert!(std::ptr::eq(
        baseline.snapshot_chunks(),
        baseline.snapshot_chunks()
    ));
    publisher.publish(2, Vec::new());
    let next = updates.recv().await.unwrap();
    assert_eq!(next.seq, 2);
    assert_eq!(baseline.entities.len(), 1);
    assert!(next.entities.is_empty());
    for revision in 3..=40 {
        publisher.publish(revision, vec![actor.clone()]);
    }
    assert!(matches!(
        updates.recv().await,
        Err(tokio::sync::broadcast::error::RecvError::Lagged(_))
    ));
    let (fresh, mut receiver) = publisher.subscribe();
    assert_eq!(fresh.seq, 40);
    publisher.publish(41, vec![actor]);
    assert_eq!(receiver.recv().await.unwrap().seq, 41);
}
