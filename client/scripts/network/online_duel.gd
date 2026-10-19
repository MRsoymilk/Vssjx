class_name OnlineDuel
extends RefCounted
signal changed
signal message(text: String)
signal send_requested(packet: Dictionary)
var enabled := false
var connected := false
var character_id := ""
var state: Dictionary = {}
var request: Dictionary = {}
var sent_at := 0
var received_at := 0
var last_code := ""
var cooldowns: Dictionary = {}
var _last_notice := ""
const ERRORS := {"DUEL_REJECT_COOLDOWN":"对方已拒绝，请在5分钟冷却结束后再次邀请。", "DUEL_BUSY":"你或对方正忙，暂时不能决斗。", "DUEL_SELF":"不能邀请自己决斗。", "DUEL_PLAYER_OFFLINE":"对方已离线，或客户端尚未支持决斗。", "DUEL_DIFFERENT_MAP":"只能邀请同地图玩家。", "DUEL_INVITE_EXPIRED":"决斗邀请已失效。", "DUEL_NOT_YOUR_TURN":"请等待对方行动。", "DUEL_STALE_REVISION":"回合已更新，请重新选择行动。", "DUEL_FORBIDDEN":"不能处理其他玩家的邀请或决斗。", "DUEL_RATE_LIMITED":"操作过快，请稍后再试。", "DUEL_SILENCED":"受到禁言效果，暂时不能施展技能。", "MP_INSUFFICIENT":"灵力不足。", "DATABASE_UNAVAILABLE":"服务暂不可用，请稍后重试。"}

func bind_character(id: String) -> void:
	character_id = id
	state = {};request = {};cooldowns = {};connected = false;enabled = false;_last_notice = ""

func disconnect_channel() -> void:
	connected = false
	changed.emit()

func clear() -> void:
	state = {};request = {};connected = false
	changed.emit()

func active() -> bool:
	return state.get("battle") is Dictionary and state.battle.status == "active"

func my_turn() -> bool:
	return active() and state.battle.turn == character_id

func pending() -> bool: return not request.is_empty()

func cooldown_ms(id: String) -> int:
	return maxi(0, int(cooldowns.get(id, 0)) - Time.get_ticks_msec())

func submit(action: String, target: String = "") -> bool:
	if not enabled or not connected or pending(): return false
	var command := {"action": action}
	if action == "invite":
		if active() or not OnlineWorldClient._uuid(target) or target == character_id or cooldown_ms(target) > 0: return false
		command.target = target
	elif action in ["accept", "reject", "cancel"]:
		var offer: Variant = state.get("outgoing" if action == "cancel" else "incoming")
		if not offer is Dictionary: return false
		command.invite_id = offer.id
	elif action in ["attack", "skill", "guard", "flee"]:
		if not active() or (not my_turn() and action != "flee"): return false
		command.battle_id = state.battle.id
		command.expected_revision = state.battle.revision
		if action == "skill": command.skill = target
	else: return false
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16: return false
	bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	command.request_id = "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)]
	request = command
	last_code = ""
	retry()
	changed.emit()
	return true

func retry() -> void:
	if not connected or request.is_empty(): return
	sent_at = Time.get_ticks_msec()
	send_requested.emit({"type":"duel.command","command":request.duplicate(true)})

func tick() -> void:
	if connected and pending() and Time.get_ticks_msec() - sent_at >= 2500: retry()

func _offer(value: Variant, incoming: bool) -> bool:
	if value == null: return true
	return value is Dictionary and OnlineWorldClient._uuid(value.get("id")) and OnlineWorldClient._uuid(value.get("from")) and OnlineWorldClient._uuid(value.get("to")) and value.from != value.to and value.get("to" if incoming else "from") == character_id and OnlineAccount.valid_nickname(value.get("from_name", "")) and OnlineAccount.valid_nickname(value.get("to_name", "")) and OnlineWorldClient._integer(value.get("remaining_ms"), 0, 30000)

func _battle(value: Variant) -> bool:
	if value == null: return true
	if not value is Dictionary or not OnlineWorldClient._uuid(value.get("id")) or not OnlineWorldClient._decimal(value.get("revision")) or value.get("status") not in ["active", "finished"] or not value.get("fighters") is Array or value.fighters.size() != 2: return false
	var ids := []
	for fighter in value.fighters:
		if not fighter is Dictionary or not OnlineWorldClient._uuid(fighter.get("id")) or ids.has(fighter.id) or not OnlineAccount.valid_nickname(fighter.get("name", "")): return false
		ids.append(fighter.id)
		if not OnlineWorldClient._integer(fighter.get("job"), 0, 2) or not OnlineWorldClient._integer(fighter.get("gender"), 0, 1) or not OnlineWorldClient._integer(fighter.get("school"), 0, 3) or not OnlineWorldClient._integer(fighter.get("level"), 1, 60): return false
		if not fighter.get("stats") is Dictionary or not fighter.get("effects") is Dictionary or not fighter.get("appearance") is Array or fighter.appearance.size() != 3: return false
		if not SkillRules.valid_state(fighter.effects): return false
		for key in ["hp", "mp", "attack", "defense"]:
			if not OnlineWorldClient._integer(fighter.stats.get(key), 0 if key == "mp" else 1, 100000): return false
		if not OnlineWorldClient._integer(fighter.get("hp"), 0, int(fighter.stats.hp)) or not OnlineWorldClient._integer(fighter.get("mp"), 0, int(fighter.stats.mp)): return false
		for i in 3:
			if not OnlineWorldClient._integer(fighter.appearance[i], 0, ShopRules.APPEARANCE_LIMITS[i]): return false
	if not character_id in ids or value.get("turn") not in ids or (value.get("winner") != null and value.winner not in ids) or (value.get("last_actor") != null and value.last_actor not in ids): return false
	return value.get("lines") is Array and value.lines.size() <= 12 and value.lines.all(func(line: Variant)->bool:return line is String and line.length() <= 200) and value.get("last_action") is String and value.get("last_skill") is String and value.last_skill.length() <= 32 and OnlineWorldClient._integer(value.get("remaining_ms"), 0, 30000)

func receive(packet: Dictionary) -> bool:
	if packet.get("type") == "duel.result":
		if not OnlineWorldClient._uuid(packet.get("request_id")) or not packet.get("ok") is bool or not packet.get("code") is String or not OnlineWorldClient._integer(packet.get("retry_after_ms"), 0, 300000): return false
		if not pending() or request.request_id != packet.request_id: return true
		last_code = "" if packet.ok else packet.code
		if packet.code == "DUEL_REJECT_COOLDOWN" and request.action == "invite": cooldowns[request.target] = Time.get_ticks_msec() + int(packet.retry_after_ms)
		request = {}
		if not packet.ok: message.emit(ERRORS.get(packet.code, "决斗操作未完成：" + packet.code))
		changed.emit();return true
	if packet.get("type") != "duel.state" or not OnlineWorldClient._decimal(packet.get("revision")) or not _offer(packet.get("incoming"), true) or not _offer(packet.get("outgoing"), false) or not _battle(packet.get("battle")) or not packet.get("notice") is String or packet.notice.length() > 200: return false
	if connected and not state.is_empty() and int(packet.revision) < int(state.revision): return false
	state = packet.duplicate(true)
	received_at = Time.get_ticks_msec()
	var was_connected := connected
	connected = true
	if not state.notice.is_empty() and state.notice != _last_notice:
		_last_notice = state.notice;message.emit(state.notice)
	changed.emit()
	if not was_connected and pending(): retry()
	return true
