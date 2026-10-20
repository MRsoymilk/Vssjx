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
var _locked_battle := ""
var _locked_revision := ""
const ERRORS := {"DUEL_ALREADY_SUBMITTED":"本回合指令已锁定，等待对方选择。","DUEL_RESOLVING":"双方指令已锁定，正在结算。","DUEL_DECISION_EXPIRED":"选择时间已到，未提交的指令将默认防御。","DUEL_REJECT_COOLDOWN":"对方已拒绝，请在5分钟冷却结束后再次邀请。", "DUEL_BUSY":"你或对方正忙，暂时不能决斗。", "DUEL_SELF":"不能邀请自己决斗。", "DUEL_PLAYER_OFFLINE":"对方已离线，或客户端尚未支持决斗。", "DUEL_DIFFERENT_MAP":"只能邀请同地图玩家。", "DUEL_INVITE_EXPIRED":"决斗邀请已失效。", "DUEL_NOT_YOUR_TURN":"请等待对方行动。", "DUEL_STALE_REVISION":"回合已更新，请重新选择行动。", "DUEL_FORBIDDEN":"不能处理其他玩家的邀请或决斗。", "DUEL_RATE_LIMITED":"操作过快，请稍后再试。", "DUEL_SILENCED":"受到禁言效果，暂时不能施展技能。", "MP_INSUFFICIENT":"灵力不足。", "DATABASE_UNAVAILABLE":"服务暂不可用，请稍后重试。"}

func bind_character(id: String) -> void:
	character_id = id
	state = {};request = {};cooldowns = {};connected = false;enabled = false;_last_notice = "";_locked_battle="";_locked_revision=""

func disconnect_channel() -> void:
	connected = false
	changed.emit()

func clear() -> void:
	state = {};request = {};connected = false;_locked_battle="";_locked_revision=""
	changed.emit()

func active() -> bool:
	return state.get("battle") is Dictionary and state.battle.status == "active"

func can_decide()->bool:
	if not active() or not connected or state.battle.phase!="planning":return false
	var b:Dictionary=state.battle
	var me:=0 if b.fighters[0].id==character_id else 1
	return not b.submitted[me] and not (b.id==_locked_battle and b.decision_revision==_locked_revision) and int(b.remaining_ms)>Time.get_ticks_msec()-received_at

func my_turn() -> bool:return can_decide()

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
		command.expected_revision = state.battle.decision_revision
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

func _fighter(fighter:Variant)->bool:
	if not fighter is Dictionary or not OnlineWorldClient._uuid(fighter.get("id")) or not OnlineAccount.valid_nickname(fighter.get("name","")):return false
	if not OnlineWorldClient._integer(fighter.get("job"),0,2) or not OnlineWorldClient._integer(fighter.get("gender"),0,1) or not OnlineWorldClient._integer(fighter.get("school"),0,3) or not OnlineWorldClient._integer(fighter.get("level"),1,60) or not OnlineWorldClient._integer(fighter.get("speed"),100,400):return false
	if not fighter.get("stats") is Dictionary or not fighter.get("effects") is Dictionary or not fighter.get("appearance") is Array or fighter.appearance.size()!=3 or not fighter.get("guarding") is bool:return false
	if not CharacterAttributeRules.valid_balance(fighter.stats):return false
	if not SkillRules.valid_state(fighter.effects):return false
	for key in ["hp","mp","attack","defense"]:
		if not OnlineWorldClient._integer(fighter.stats.get(key),0 if key=="mp" else 1,100000):return false
	if not OnlineWorldClient._integer(fighter.get("hp"),0,int(fighter.stats.hp)) or not OnlineWorldClient._integer(fighter.get("mp"),0,int(fighter.stats.mp)):return false
	return ShopRules.valid_appearance(fighter.appearance)

func _battle(value: Variant) -> bool:
	if value==null:return true
	if not value is Dictionary or not OnlineWorldClient._uuid(value.get("id")) or not OnlineWorldClient._decimal(value.get("revision")) or not OnlineWorldClient._decimal(value.get("decision_revision")) or value.get("status") not in ["active","finished"] or not value.get("fighters") is Array or value.fighters.size()!=2:return false
	var ids:Array=[]
	for f in value.fighters:
		if not _fighter(f) or ids.has(f.id):return false
		ids.append(f.id)
	if not character_id in ids or value.get("winner")!=null and value.winner not in ids:return false
	if value.has("choices") or value.has("turn") or not OnlineWorldClient._integer(value.get("round"),1,50) or int(value.decision_revision)!=int(value.round)-1 or not OnlineWorldClient._integer(value.get("resolved_round"),0,int(value.round)):return false
	if value.get("phase") not in ["planning","resolving","finished"] or (value.status=="finished")!=(value.phase=="finished"):return false
	if not value.get("submitted") is Array or value.submitted.size()!=2 or not value.submitted.all(func(v:Variant)->bool:return v is bool):return false
	if value.phase=="resolving" and not value.submitted.all(func(v:bool)->bool:return v):return false
	var me:=ids.find(character_id)
	var choice:Variant=value.get("your_choice")
	if (choice!=null)!=bool(value.submitted[me]):return false
	if choice!=null and (not choice is Dictionary or choice.get("action") not in ["attack","skill","guard"] or (choice.action=="skill" and (not choice.get("skill") is String or SkillRules.item(choice.skill).is_empty()))):return false
	if not value.get("events") is Array or value.events.size()>2:return false
	for e in value.events:
		if e is Dictionary and e.has("critical") and not e.critical is bool:return false
		if not e is Dictionary or e.get("actor") not in ids or e.get("action") not in ["attack","skill","guard","sleep","fizzle","dot"] or not e.get("skill") is String or e.skill.length()>32 or (e.action=="skill" and SkillRules.item(e.skill).is_empty()):return false
		if not OnlineWorldClient._integer(e.get("damage"),0,100000) or not OnlineWorldClient._integer(e.get("reflected"),0,100000) or not e.get("fighters") is Array or e.fighters.size()!=2:return false
		for i in 2:
			if not _fighter(e.fighters[i]) or e.fighters[i].id!=ids[i]:return false
	return value.get("lines") is Array and value.lines.size()<=12 and value.lines.all(func(line:Variant)->bool:return line is String and line.length()<=200) and OnlineWorldClient._integer(value.get("remaining_ms"),0,30000)

func receive(packet: Dictionary) -> bool:
	if packet.get("type") == "duel.result":
		if not OnlineWorldClient._uuid(packet.get("request_id")) or not packet.get("ok") is bool or not packet.get("code") is String or not OnlineWorldClient._integer(packet.get("retry_after_ms"), 0, 300000): return false
		if not pending() or request.request_id != packet.request_id: return true
		last_code = "" if packet.ok else packet.code
		if packet.code == "DUEL_REJECT_COOLDOWN" and request.action == "invite": cooldowns[request.target] = Time.get_ticks_msec() + int(packet.retry_after_ms)
		if (packet.ok or packet.code=="DUEL_ALREADY_SUBMITTED") and request.action in ["attack","skill","guard"]:
			_locked_battle=request.battle_id;_locked_revision=request.expected_revision
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
