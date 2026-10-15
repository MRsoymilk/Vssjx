use std::time::{Duration, Instant};
use uuid::Uuid;
use vssjx_server::chat::{ChatConfig, ChatHub, text};

#[test]
fn public_text_is_bounded_and_does_not_interpret_markup() {
    assert_eq!(
        text("  [url=https://invalid]你好[/url]  ").unwrap(),
        "[url=https://invalid]你好[/url]"
    );
    assert!(text(&"界".repeat(120)).is_ok());
    assert!(text(&"😀".repeat(120)).is_ok());
    for raw in [
        "",
        "   ",
        "\u{3000}",
        "hello\nworld",
        "\t",
        "\0",
        "\u{0085}",
        "hi\u{202e}abc",
        "hi\u{200b}",
        "hi\u{feff}",
        &"界".repeat(121),
        &"a".repeat(481),
    ] {
        assert!(text(raw).is_err(), "{raw:?}");
    }
}

#[test]
fn dedup_precedes_limits_and_survives_sender_disconnect() {
    let config = ChatConfig {
        personal_burst: 1,
        ..ChatConfig::default()
    };
    let mut chat = ChatHub::new(config);
    let now = Instant::now();
    let character = Uuid::new_v4();
    let id = Uuid::new_v4();
    assert_eq!(
        chat.submit((character, "甲乙"), id, "public", "  原消息  ", false, now)
            .status,
        "QUEUED"
    );
    assert_eq!(
        chat.submit((character, "甲乙"), id, "public", "原消息", true, now)
            .status,
        "QUEUED"
    );
    assert_eq!(
        chat.submit((character, "甲乙"), id, "public", "已修改", false, now)
            .code,
        Some("CHAT_ID_CONFLICT")
    );
    chat.drain(now + Duration::from_secs(1));
    let receipt = chat.submit(
        (character, "甲乙"),
        id,
        "public",
        "原消息",
        true,
        now + Duration::from_secs(2),
    );
    assert_eq!(receipt.status, "SENT");
    assert_eq!(receipt.message_id, Some(chat.batch(0)[0].message_id));
    assert_eq!(chat.batch(0).len(), 1);
    assert_eq!(
        chat.submit(
            (character, "甲乙"),
            Uuid::new_v4(),
            "public",
            "新消息",
            false,
            now + Duration::from_secs(2)
        )
        .code,
        Some("CHAT_RATE_LIMITED")
    );
    // No socket or actor ownership is stored in ChatHub: receipts remain after leave.
    assert!(chat.result(character, id).is_some());
    assert_eq!(
        chat.submit(
            (character, "甲乙"),
            Uuid::new_v4(),
            "public",
            "新消息",
            true,
            now + Duration::from_secs(2)
        )
        .code,
        Some("CHAT_MUTED")
    );
    assert_eq!(
        chat.submit(
            (character, "甲乙"),
            Uuid::nil(),
            "public",
            "新消息",
            false,
            now + Duration::from_secs(2)
        )
        .code,
        Some("CHAT_INVALID_ID")
    );
}

#[test]
fn fair_drain_history_limits_and_no_eviction_of_live_receipts() {
    let config = ChatConfig {
        global_per_second: 1,
        history: 2,
        max_pending: 2,
        max_receipts: 2,
        ..ChatConfig::default()
    };
    let mut chat = ChatHub::new(config);
    let now = Instant::now();
    let a = Uuid::new_v4();
    let b = Uuid::new_v4();
    let first = Uuid::new_v4();
    chat.submit((a, "甲乙"), first, "public", "甲1", false, now);
    assert_eq!(
        chat.submit((a, "甲乙"), Uuid::new_v4(), "public", "甲2", false, now)
            .code,
        Some("CHAT_PENDING")
    );
    chat.submit((b, "丙丁"), Uuid::new_v4(), "public", "乙1", false, now);
    assert_eq!(
        chat.submit(
            (Uuid::new_v4(), "戊己"),
            Uuid::new_v4(),
            "public",
            "丙1",
            false,
            now
        )
        .code,
        Some("CHAT_BUSY")
    );
    chat.drain(now + Duration::from_secs(1));
    assert_eq!(chat.batch(0).len(), 1);
    assert_eq!(chat.batch(0)[0].sender_character_id, a);
    chat.drain(now + Duration::from_secs(2));
    assert_eq!(chat.batch(0)[1].sender_character_id, b);
    // Bounded receipt table rejects instead of evicting unexpired dedup keys.
    assert_eq!(
        chat.submit(
            (a, "甲乙"),
            Uuid::new_v4(),
            "public",
            "甲3",
            false,
            now + Duration::from_secs(10)
        )
        .code,
        Some("CHAT_BUSY")
    );
    let expired = now + Duration::from_secs(303);
    chat.drain(expired);
    assert!(chat.result(a, first).is_none());
    assert_eq!(
        chat.submit((a, "甲乙"), Uuid::new_v4(), "public", "甲4", false, expired)
            .status,
        "QUEUED"
    );
    chat.drain(expired + Duration::from_secs(1));
    assert_eq!(chat.batch(0).len(), 2);
    assert_eq!(chat.oldest(), 2);
    assert_eq!(chat.batch(1)[0].seq, "2");
    assert_eq!(chat.batch(2)[0].seq, "3");
}

#[test]
fn idle_time_cannot_turn_into_unbounded_channel_burst() {
    let mut chat = ChatHub::new(ChatConfig {
        global_per_second: 2,
        ..ChatConfig::default()
    });
    let now = Instant::now();
    for _ in 0..5 {
        chat.submit(
            (Uuid::new_v4(), "甲乙"),
            Uuid::new_v4(),
            "public",
            "测试",
            false,
            now,
        );
    }
    chat.drain(now + Duration::from_secs(600));
    assert_eq!(chat.batch(0).len(), 2);
    chat.drain(now + Duration::from_secs(600));
    assert_eq!(chat.batch(0).len(), 2);
    chat.drain(now + Duration::from_millis(600500));
    assert_eq!(chat.batch(0).len(), 3);
}

#[test]
fn client_chat_cannot_supply_sender_or_inject_extra_fields() {
    use vssjx_server::world::ClientMessage;
    let id = Uuid::new_v4();
    let valid = format!(
        r#"{{"type":"chat.send","client_message_id":"{id}","channel":"public","text":"hello"}}"#
    );
    assert!(serde_json::from_str::<ClientMessage>(&valid).is_ok());
    let spoof = valid.replace("\"text\":", "\"display_name\":\"管理员\",\"text\":");
    assert!(serde_json::from_str::<ClientMessage>(&spoof).is_err());
}

#[test]
fn admission_window_skips_old_chat_and_keeps_messages_during_sync() {
    let mut chat = ChatHub::new(ChatConfig::default());
    let now = Instant::now();
    chat.submit(
        (Uuid::new_v4(), "甲乙"),
        Uuid::new_v4(),
        "public",
        "上线以前",
        false,
        now,
    );
    chat.drain(now + Duration::from_secs(1));
    let admitted = chat.latest();
    let (ready, cursor) = chat.ready_since(admitted);
    assert_eq!(ready["oldest_seq"], "2");
    assert_eq!(ready["latest_seq"], "1");
    assert!(chat.batch(cursor).is_empty());

    // Admission precedes the world baseline: do not skip messages while syncing.
    chat.submit(
        (Uuid::new_v4(), "丙丁"),
        Uuid::new_v4(),
        "public",
        "上线以后[微笑]",
        false,
        now + Duration::from_secs(1),
    );
    chat.drain(now + Duration::from_secs(2));
    let (ready, cursor) = chat.ready_since(admitted);
    assert_eq!(ready["oldest_seq"], "2");
    assert_eq!(ready["latest_seq"], "2");
    assert_eq!(chat.batch(cursor).len(), 1);
    assert_eq!(chat.batch(cursor)[0].text, "上线以后[微笑]");

    // A retained game session reconnects using its original admission cursor.
    assert_eq!(chat.batch(chat.ready_since(admitted).1)[0].seq, "2");
    // A new admission starts afresh without deleting other players' history.
    assert!(chat.batch(chat.ready_since(chat.latest()).1).is_empty());
    assert_eq!(chat.batch(0).len(), 2);
}

#[test]
fn admission_window_is_bounded_by_history_and_resets_with_channel() {
    let mut chat = ChatHub::new(ChatConfig {
        history: 2,
        ..ChatConfig::default()
    });
    let now = Instant::now();
    for index in 0..4 {
        let at = now + Duration::from_secs(index);
        chat.submit(
            (Uuid::new_v4(), "甲乙"),
            Uuid::new_v4(),
            "public",
            &format!("消息{index}"),
            false,
            at,
        );
        chat.drain(at + Duration::from_secs(1));
    }
    let (ready, cursor) = chat.ready_since(1);
    assert_eq!(ready["oldest_seq"], "3");
    assert_eq!(ready["latest_seq"], "4");
    assert_eq!(cursor, 2);
    assert_eq!(
        chat.batch(cursor)
            .iter()
            .map(|message| message.seq.as_str())
            .collect::<Vec<_>>(),
        ["3", "4"]
    );
    let fresh = ChatHub::new(ChatConfig::default());
    let (ready, cursor) = fresh.ready_since(4);
    assert_eq!(cursor, 0);
    assert_eq!(ready["oldest_seq"], "1");
    assert_eq!(ready["latest_seq"], "0");
}
