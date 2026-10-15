extends Node
var checks := 0
var failures := 0
var sent: Array = []
var notes: Array = []
var epoch := "10000000-0000-4000-8000-000000000001"
var sender := "10000000-0000-4000-8000-000000000002"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + message)

func ready_packet(history: int = 3, oldest: int = 1, latest: int = 0) -> Dictionary:
	return {"type": "chat.ready", "channel_epoch": epoch, "latest_seq": str(latest), "oldest_seq": str(oldest), "history_limit": history, "dedup_seconds": 300, "max_chars": 120, "max_bytes": 480}

func entry(seq: int, text: String = "[b]文字[/b]") -> Dictionary:
	return {"seq": str(seq), "message_id": "20000000-0000-4000-8000-%012d" % seq, "sender_character_id": sender, "display_name": "青云消息", "server_time_ms": "1792036800000", "channel": "public", "text": text}

func batch(values: Array) -> Dictionary:
	return {"type": "chat.batch", "channel_epoch": epoch, "messages": values}

func _ready() -> void:
	for raw in ["你好", " [b]literal[/b] ", "界".repeat(120), "😀".repeat(120), "[微笑][大笑][爱心][流泪][生气][惊讶][害羞][加油]"]: check(OnlinePublicChat.valid_text(raw), "Valid pure text and emote markers accepted")
	for raw in ["", "   ", "\u3000", "\u00a0", "\u2001", "a\n", "a\t", "a\u0085", "a\u202e", "a\u200b", "a\ufeff", "界".repeat(121)]: check(not OnlinePublicChat.valid_text(raw), "Invalid text rejected")
	var chat := OnlinePublicChat.new()
	chat.send_requested.connect(func(message: Dictionary) -> void: sent.append(message.duplicate(true)))
	chat.status_changed.connect(func(text: String) -> void: notes.append(text))
	check(not chat.submit("未认证"), "Unauthenticated channel cannot send")
	check(not chat.receive(batch([entry(1)])), "No history before authenticated chat.ready")
	check(chat.receive(ready_packet()), "Independent chat channel handshake")
	check(not chat.receive(ready_packet()), "Repeated channel handshake rejected")
	chat.enabled = true
	check(chat.submit("原始内容"), "One original message admitted")
	var original: Dictionary = chat.pending.duplicate(true)
	check(not chat.submit("不能换ID重发"), "Pending message prevents a new message ID")
	chat._last_send = -4000
	chat.tick()
	check(sent.size() == 2 and sent[0] == sent[1], "Retry preserves original ID and exact content")
	chat.disconnect_channel()
	check(chat.pending.client_message_id == original.client_message_id, "Disconnect preserves unknown result")
	check(chat.receive(ready_packet()), "Same process reconnect restarts channel cursor")
	chat.enabled = true
	check(chat.pending.client_message_id == original.client_message_id, "Same-epoch reconnect never replaces ID")
	var queued := {"type": "chat.result", "result": {"client_message_id": original.client_message_id, "status": "QUEUED"}}
	check(chat.receive(queued) and not chat.pending.is_empty(), "Queued is not final delivery confirmation")
	var result := {"type": "chat.result", "result": {"client_message_id": original.client_message_id, "status": "SENT", "message_id": entry(1).message_id}}
	check(chat.receive(result) and chat.pending.is_empty(), "Sent result resolves original pending message")
	check(chat.receive(batch([entry(1), entry(2)])), "Ordered batch installed")
	var bad := batch([entry(3), entry(5)])
	check(not chat.receive(bad) and chat.messages.size() == 2 and chat._cursor == 2, "Bad batch is atomic; no half-install")
	bad = batch([entry(3)])
	bad.messages[0].display_name = "伪造\n身份"
	check(not chat.receive(bad), "Invalid display name rejected")
	check(not chat.receive(batch([entry(2)])), "Duplicate sequence rejected")
	check(chat.receive(batch([entry(3), entry(4)])) and chat.messages.size() == 3 and chat.messages[0].seq == "2", "Client retains bounded history")
	check(chat.receive({"type": "chat.gap", "channel_epoch": epoch, "oldest_seq": "8"}), "History gap explicitly advances cursor")
	check(chat.receive(batch([entry(8)])) and chat.messages.size() == 3, "Channel continues after history gap")
	bad = batch([entry(9)])
	bad.channel_epoch = sender
	check(not chat.receive(bad), "Foreign channel epoch rejected")
	check(chat.submit("重启前未知"), "Unknown send staged before restart")
	chat.disconnect_channel()
	epoch = "30000000-0000-4000-8000-000000000001"
	check(chat.receive(ready_packet()) and chat.pending.is_empty() and chat.messages.is_empty(), "Restart clears history and will not replay old-epoch unknown send")
	check(String(notes[-1]).contains("结果未知"), "Unknown restart result is visible to user")
	chat.enabled = true
	check(chat.submit("超时未知"), "Timeout fixture stages message")
	chat.pending.at = Time.get_ticks_msec() - 301000
	chat.tick()
	check(chat.pending.is_empty() and String(notes[-1]).contains("结果未知"), "Expired dedup window never retries using a new ID")
	chat.clear()
	check(chat.messages.is_empty() and chat.pending.is_empty() and chat.epoch.is_empty() and not chat.enabled, "Leaving destroys all in-memory chat state")
	check(chat.receive(ready_packet(3, 4, 3)) and chat.messages.is_empty() and chat._cursor == 3, "Fresh character admission starts after all pre-online chat")
	check(not chat.receive(batch([entry(3, "上线以前")])) and chat.messages.is_empty(), "Pre-online history is outside the admitted sequence window")
	check(chat.receive(batch([entry(4, "上线以后[微笑]")])), "First message published after admission is accepted")
	chat.disconnect_channel()
	check(chat.receive(ready_packet(3, 4, 5)) and chat.receive(batch([entry(4, "上线以后[微笑]"), entry(5, "断线期间")])) and chat.messages.size() == 2, "Reconnect replays only messages from the retained character admission")
	chat.clear()
	check(chat.receive(ready_packet(3, 6, 5)) and chat.messages.is_empty() and chat._cursor == 5, "Leaving and re-entering starts a new empty chat window")
	print("PUBLIC CHAT PROTOCOL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
