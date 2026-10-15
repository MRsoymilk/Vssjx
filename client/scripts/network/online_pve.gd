class_name OnlinePve
extends RefCounted
## Memory-only retry outbox belongs to the authenticated account, never local saves.
signal changed
signal send_requested(packet: Dictionary)
signal message(text: String)
var state: Dictionary = {}
var ready := false
var character_id := ""
var realm := ""
var sent_at := 0.0
var last_action := ""
var last_code := ""

func bind_character(id: String, address: String) -> void:
	character_id = id
	realm = address
	state = {}
	ready = false
	var pending: Dictionary = OnlineAccount.pending_pve
	if not pending.is_empty() and (pending.character != id or pending.realm != address): OnlineAccount.pending_pve = {}

func disconnect_channel() -> void:
	ready = false
	sent_at = 0.0
	changed.emit()

func pending() -> bool:
	return not OnlineAccount.pending_pve.is_empty()

func active() -> bool:
	return state.get("battle") is Dictionary and state.battle.get("outcome") == "active"

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func uuid(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z").search(value) != null

static func decimal(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^(0|[1-9][0-9]{0,18})\\z").search(value) != null and (value.length() < 19 or value <= "9223372036854775807")

func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("rules_version") != "qingyun-pve-v1": return false
	if not OnlineAccount._valid_character(value.get("character")) or value.character.id != character_id or value.character.quest_stage > 3: return false
	if not integer(value.get("potions"), 0, 99): return false
	if not value.get("stats") is Dictionary: return false
	for key in ["hp", "mp", "attack", "defense"]:
		if not integer(value.stats.get(key), 1, 10000): return false
	if value.character.hp > value.stats.hp or value.character.mp > value.stats.mp: return false
	if value.has("attributes") and not valid_attributes(value.attributes, value): return false
	var progress: Variant = value.get("progress")
	if not progress is Dictionary or not integer(progress.get("kills"), 0, 3) or not progress.get("defeated") is Array or progress.defeated.size() > 4: return false
	var seen: Dictionary = {}
	var kills := 0
	for id in progress.defeated:
		if not id is String or not id in ["wolf_a", "wolf_b", "wolf_c", "spirit"] or seen.has(id): return false
		seen[id] = true
		if id != "spirit": kills += 1
	if kills != int(progress.kills): return false
	if not value.has("battle"): return false
	var battle: Variant = value.battle
	if battle == null: return true
	if not battle is Dictionary or not uuid(battle.get("id")) or not decimal(battle.get("revision")): return false
	if not battle.get("outcome") in ["active", "victory", "defeat", "fled"] or not integer(battle.get("round"), 0, 30): return false
	if not battle.get("enemy") is Dictionary: return false
	var enemy: Dictionary = battle.enemy
	if not enemy.get("id") in ["wolf_a", "wolf_b", "wolf_c", "spirit"] or not enemy.get("name") is String or enemy.name.length() > 24: return false
	if not enemy.get("art") in ["monster/langw", "monster/hs1"]: return false
	if not integer(enemy.get("hp"), 1, 10000) or not integer(enemy.get("level"), 1, 50): return false
	if not integer(battle.get("hp"), 0, int(value.stats.hp)) or not integer(battle.get("mp"), 0, int(value.stats.mp)) or not integer(battle.get("enemy_hp"), 0, int(enemy.hp)) or not integer(battle.get("potions"), 0, 99): return false
	return true

func receive(packet: Dictionary) -> bool:
	var kind: Variant = packet.get("type")
	if not kind in ["pve.state", "pve.result"] or not valid(packet.get("state")): return false
	if kind == "pve.result":
		if not uuid(packet.get("operation_id")) or not packet.get("ok") is bool or not packet.get("replayed") is bool or not packet.get("lines") is Array or packet.lines.size() > 12: return false
		for line in packet.lines:
			if not line is String or line.length() > 200: return false
		if not packet.ok and not packet.get("code") is String: return false
	# An old receipt can acknowledge the outbox, but cannot roll back current state.
	if state.is_empty() or int(packet.state.character.state_revision) >= int(state.character.state_revision):
		state = packet.state.duplicate(true)
		# JSON numbers arrive as floats; typed Rust point arrays require integer JSON.
		if state.has("attributes"):
			state.attributes.allocated = normalized_points(state.attributes.allocated)
			state.attributes.recommended = normalized_points(state.attributes.recommended)
		OnlineAccount.characters = [state.character.duplicate(true)]
	ready = true
	if kind == "pve.result":
		if pending() and OnlineAccount.pending_pve.command.operation_id == packet.operation_id:
			last_action = OnlineAccount.pending_pve.command.action
			OnlineAccount.pending_pve = {}
			last_code = "" if packet.ok else String(packet.code)
			if packet.ok: message.emit("\n".join(PackedStringArray(packet.lines)))
			else: message.emit(error_text(last_code))
	changed.emit()
	if kind == "pve.state" and pending(): retry()
	return true

func submit(action: String, target: String = "", points: Array = []) -> bool:
	if not ready or pending(): return false
	if action == "allocate":
		if active() or not state.has("attributes") or not valid_points(points): return false
		points = normalized_points(points)
		var spent := 0
		for i in 5:
			if int(points[i]) < int(state.attributes.allocated[i]): return false
			spent += int(points[i])
		if spent > int(state.character.level) * 5 or points == state.attributes.allocated: return false
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16: return false
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	var command := {"operation_id": "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)], "action": action}
	if action == "allocate":
		command.attributes = normalized_points(points)
		command.expected_revision = state.character.state_revision
	elif not target.is_empty(): command.target = target
	elif active():
		command.battle_id = state.battle.id
		command.expected_revision = state.battle.revision
	OnlineAccount.pending_pve = {"realm": realm, "character": character_id, "command": command}
	retry()
	changed.emit()
	return true

func retry() -> void:
	if not ready or not pending(): return
	sent_at = Time.get_unix_time_from_system()
	send_requested.emit({"type": "pve.command", "command": OnlineAccount.pending_pve.command.duplicate(true)})

func quest_text() -> String:
	if state.is_empty(): return "正在同步试炼进度……"
	var stage := int(state.character.quest_stage)
	if stage == 0: return "山林试炼\n前往桥边拜访清微道人，领受试炼。"
	if stage == 1: return "山林试炼\n击败山狼 %d / 3\n三只山狼各计一次，请留意小地图红点。" % int(state.progress.kills)
	if stage == 2: return "山林试炼\n山狼已清除，返回清微道人处领取奖励。\n奖励：60铜钱、35修为。"
	return "山林试炼 · 已完成\n清微道人仍可为你恢复生命与灵力。"

static func error_text(code: String) -> String:
	var attributes := {"STALE_ATTRIBUTES":"属性已更新，请重新加点。", "ATTRIBUTE_RESPEC_FORBIDDEN":"已保存的属性点不能减少。", "ATTRIBUTE_POINTS_EXCEEDED":"剩余属性点不足。", "NO_ATTRIBUTE_CHANGE":"请先分配属性点。", "INVALID_ATTRIBUTES":"属性点格式无效。"}
	if attributes.has(code): return attributes[code]
	return {"PLAYER_MOVING":"请停稳后再交互。", "RESIDENT_TOO_FAR":"距离过远，请靠近后再试。", "QUEST_REQUIRED":"请先向清微道人接取山林试炼。", "QUEST_NOT_READY":"试炼尚未完成或奖励已经领取。", "QUEST_ALREADY_ACCEPTED":"已经领受过此试炼。", "MONSTER_DEFEATED":"你已经击败过这只怪物。", "STALE_BATTLE":"回合已经更新，请重新选择行动。", "MP_INSUFFICIENT":"灵力不足，可凝神防御恢复灵力。", "NO_POTION":"回春散已经用完。", "HP_FULL":"当前生命已满。", "BATTLE_ACTIVE":"请先完成当前战斗。"}.get(code,"操作未完成：" + code)

static func valid_points(value: Variant) -> bool:
	if not value is Array or value.size() != 5: return false
	for point in value:
		if not integer(point, 0, 250): return false
	return true

static func normalized_points(points: Array) -> Array:
	return points.map(func(point: Variant) -> int: return int(point))

static func valid_attributes(profile: Variant, value: Dictionary) -> bool:
	if not profile is Dictionary or profile.get("version") != "attributes-v1": return false
	if not valid_points(profile.get("allocated")) or not valid_points(profile.get("recommended")): return false
	var spent := 0
	var recommended := 0
	for i in 5:
		spent += int(profile.allocated[i])
		recommended += int(profile.recommended[i])
		if profile.recommended[i] < profile.allocated[i]: return false
	var budget := int(value.character.level) * 5
	if not integer(profile.get("available"), 0, 250) or int(profile.available) != budget - spent or recommended != budget: return false
	if not profile.get("combat") is Dictionary: return false
	for key in ["hp", "mp", "physical_attack", "magic_attack", "physical_defense", "magic_defense", "physical_crit", "magic_crit", "physical_hit", "magic_hit", "physical_evasion", "magic_evasion", "damage_reduction"]:
		if not integer(profile.combat.get(key), 0, 10000): return false
	return profile.combat.hp == value.stats.hp and profile.combat.mp == value.stats.mp and profile.combat.physical_defense == value.stats.defense and profile.combat.magic_defense == value.stats.defense and profile.combat.get("magic_attack" if int(value.character.job) == 2 else "physical_attack") == value.stats.attack
