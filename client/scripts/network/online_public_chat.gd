class_name OnlinePublicChat
extends RefCounted
## Memory-only channel cache and one original-ID retry. No disk or Game state.
signal changed
signal status_changed(text: String)
signal confirmed
signal send_requested(message: Dictionary)
var connected := false
var enabled := false
var epoch := ""
var messages: Array = []
var pending: Dictionary = {}
var _cursor := 0
var _history_limit := 50
var _dedup_seconds := 300
var _last_send := 0

func disconnect_channel() -> void:
	connected = false
	enabled = false
	if not pending.is_empty(): status_changed.emit("连接中断，待确认消息会使用原ID重试。")

func clear() -> void:
	disconnect_channel()
	messages = []
	pending = {}
	epoch = ""
	changed.emit()

static func valid_text(raw: String) -> bool:
	if raw.is_empty() or raw.length() > 120 or raw.to_utf8_buffer().size() > 480 or raw.strip_edges().is_empty(): return false
	var meaningful := false
	for index in raw.length():
		var c := raw.unicode_at(index)
		if c < 32 or (c >= 127 and c <= 159) or (c >= 0x200b and c <= 0x200f) or (c >= 0x2028 and c <= 0x202e) or (c >= 0x2060 and c <= 0x206f) or c == 0xfeff: return false
		if c not in [32, 0xa0, 0x1680, 0x202f, 0x205f, 0x3000] and not (c >= 0x2000 and c <= 0x200a): meaningful = true
	return meaningful

func submit(raw: String) -> bool:
	if not enabled or not connected or not pending.is_empty(): return false
	if not valid_text(raw):
		status_changed.emit("请输入1～120字纯文本，不含换行或控制符。")
		return false
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16: return false
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	var id := "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
	pending = {"client_message_id": id, "text": raw, "epoch": epoch, "at": Time.get_ticks_msec(), "attempts": 0}
	_resend()
	return true

func _resend() -> void:
	_last_send = Time.get_ticks_msec()
	pending.attempts += 1
	send_requested.emit({"type": "chat.send", "client_message_id": pending.client_message_id, "channel": "public", "text": pending.text})
	status_changed.emit("正在确认发送……")

func tick() -> void:
	if pending.is_empty(): return
	var now := Time.get_ticks_msec()
	if now - int(pending.at) >= _dedup_seconds * 1000:
		pending = {}
		status_changed.emit("消息确认窗口已过，结果未知；不会自动再次发送。")
		return
	if enabled and connected and now - _last_send >= 3000 and int(pending.attempts) < 4: _resend()

func receive(data: Dictionary) -> bool:
	var kind: Variant = data.get("type")
	if kind == "chat.ready":
		if connected or not OnlineWorldClient._uuid(data.get("channel_epoch")) or not OnlineWorldClient._decimal(data.get("latest_seq")) or not OnlineWorldClient._decimal(data.get("oldest_seq")): return false
		if not OnlineWorldClient._integer(data.get("history_limit"), 1, 100) or not OnlineWorldClient._integer(data.get("dedup_seconds"), 30, 3600) or data.get("max_chars") != 120 or data.get("max_bytes") != 480: return false
		var oldest := int(data.oldest_seq)
		var latest := int(data.latest_seq)
		if oldest < 1 or oldest > latest + 1 or latest - oldest + 1 > int(data.history_limit): return false
		if not pending.is_empty() and pending.epoch != data.channel_epoch:
			pending = {}
			status_changed.emit("聊天服务已重启，原消息结果未知，不会自动重发。")
		epoch = data.channel_epoch
		_history_limit = int(data.history_limit)
		_dedup_seconds = int(data.dedup_seconds)
		_cursor = oldest - 1
		messages = []
		connected = true
		_last_send = 0
		changed.emit()
		return true
	if not connected: return false
	if kind == "chat.result":
		var result: Variant = data.get("result")
		if not result is Dictionary or not OnlineWorldClient._uuid(result.get("client_message_id")) or result.get("status") not in ["QUEUED", "SENT", "REJECTED"]: return false
		if result.status == "SENT" and not OnlineWorldClient._uuid(result.get("message_id")): return false
		if result.status == "REJECTED" and not result.get("code") is String: return false
		if not pending.is_empty() and pending.client_message_id == result.client_message_id:
			if result.status == "QUEUED": status_changed.emit("已排队，等待公共频道发送……")
			elif result.status == "SENT":
				pending = {}
				status_changed.emit("已发送")
				confirmed.emit()
			else:
				pending = {}
				var errors := {"CHAT_MUTED": "当前账号被禁言。", "CHAT_RATE_LIMITED": "发送过快，请稍后再试。", "CHAT_BUSY": "公共频道繁忙，请稍后再试。", "CHAT_INVALID_TEXT": "消息含控制符或超过长度限制。", "CHAT_PENDING": "上一条消息仍在排队。", "CHAT_ID_CONFLICT": "原消息ID内容不一致，未发送。"}
				status_changed.emit(String(errors.get(result.code, "发送失败：" + result.code)))
		return true
	if data.get("channel_epoch") != epoch: return false
	if kind == "chat.gap":
		if not OnlineWorldClient._decimal(data.get("oldest_seq")) or int(data.oldest_seq) <= _cursor + 1: return false
		_cursor = int(data.oldest_seq) - 1
		status_changed.emit("部分消息已超出历史窗口，仅显示最近记录。")
		return true
	if kind != "chat.batch" or not data.get("messages") is Array or data.messages.is_empty() or data.messages.size() > 16: return false
	var cursor := _cursor
	var ids: Dictionary = {}
	for message in messages: ids[message.message_id] = true
	for value in data.messages:
		if not value is Dictionary or not OnlineWorldClient._decimal(value.get("seq")) or int(value.seq) != cursor + 1 or not OnlineWorldClient._uuid(value.get("message_id")) or ids.has(value.message_id): return false
		if not OnlineWorldClient._uuid(value.get("sender_character_id")) or not value.get("display_name") is String or OnlineAccount.canonical_nickname(value.display_name).get("display_name") != value.display_name: return false
		if not OnlineWorldClient._decimal(value.get("server_time_ms")) or value.get("channel") != "public" or not value.get("text") is String or not valid_text(value.text): return false
		ids[value.message_id] = true
		cursor += 1
	_cursor = cursor
	messages.append_array(data.messages)
	while messages.size() > _history_limit: messages.pop_front()
	changed.emit()
	return true
