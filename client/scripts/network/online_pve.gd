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
var validation_error := ""
var _server_clock_ms := 0
var _server_clock_tick := 0

func bind_character(id: String, address: String) -> void:
	character_id = id
	realm = address
	state = {}
	ready = false
	_server_clock_ms = 0
	_server_clock_tick = 0
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

func is_soul() -> bool:
	return state.get("character",{}).get("corpse") is Dictionary

func appearance()->Array:
	return state.loot.appearance.duplicate() if state.has("loot") else (ShopRules.appearance(state.shop) if state.has("shop") else [1,0,0])

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

static func uuid(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z").search(value) != null

static func decimal(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^(0|[1-9][0-9]{0,18})\\z").search(value) != null and (value.length() < 19 or value <= "9223372036854775807")

func valid(value: Variant) -> bool:
	validation_error = ""
	if not value is Dictionary or value.get("rules_version") != "qingyun-pve-v1": return false
	if not OnlineAccount._valid_character(value.get("character")) or value.character.id != character_id or value.character.quest_stage > 4: return false
	if not integer(value.get("potions"), 0, 99): return false
	if not value.get("stats") is Dictionary: return false
	if not CharacterAttributeRules.valid_balance(value.stats):return false
	for key in ["hp", "mp", "attack", "defense"]:
		if not integer(value.stats.get(key), 1, 10000): return false
	if value.character.hp > value.stats.hp or value.character.mp > value.stats.mp: return false
	if value.has("skills") and not SkillRules.valid_view(value.skills,value.character):return false
	if value.has("ai_world") and not AIWorld.valid_progress(value.ai_world, true):
		# Retain strict validation, but distinguish stale content from corrupt PVE.
		if value.ai_world is Dictionary and value.ai_world.get("version")=="ai-world-v1" and value.ai_world.get("catalog_sha256") is String and value.ai_world.catalog_sha256!=AIWorld.catalog_hash:
			validation_error="PVE_CATALOG_MISMATCH"
		return false
	if value.has("attributes") and not valid_attributes(value.attributes, value): return false
	if value.has("shop"):
		if value.shop is Dictionary and value.shop.get("version")=="shop-v2" and value.shop.get("catalog_sha256") is String and value.shop.catalog_sha256!=ShopRules.catalog_hash:
			validation_error="SHOP_CATALOG_MISMATCH"
			return false
		if not ShopRules.valid_gear(value.shop): return false
		if value.shop.version=="shop-v2" and value.shop.get("catalog_sha256")!=ShopRules.catalog_hash: return false
	if not GourdRules.valid(value.get("gourds",{}),value.get("shop",{})):return false
	if value.has("loot"):
		if not value.has("shop") or not LootRules.valid_view(value.loot,value.shop,int(value.character.job),int(value.character.gender)):return false
		for i in value.loot.state.items:
			if i.equipped and int(i.level)>int(value.character.level):return false
	if value.has("equipment"):
		var gear: Variant = value.equipment
		if not gear is Dictionary or gear.get("version") != "equipment-v1" or not gear.get("weapon_owned") is bool: return false
		if not gear.has("weapon") or (gear.weapon != null and gear.weapon != "sword"): return false
		if gear.weapon != null and not gear.weapon_owned: return false
	var progress: Variant = value.get("progress")
	if not progress is Dictionary or not integer(progress.get("kills"), 0, 3) or not progress.get("defeated") is Array or progress.defeated.size() > 6: return false
	var seen: Dictionary = {}
	var kills := 0
	for id in progress.defeated:
		if not id is String or not id in ["wolf_a", "wolf_b", "wolf_c", "spirit", "guardian", "boss"] or seen.has(id): return false
		seen[id] = true
		if id in ["wolf_a", "wolf_b", "wolf_c"]: kills += 1
	if kills != int(progress.kills): return false
	if progress.has("respawns") or value.has("server_time_ms"):
		if not integer(value.get("server_time_ms"), 1, 253402300799999): return false
		if not progress.get("respawns") is Dictionary or progress.respawns.size() > 6: return false
		for id in progress.respawns:
			if not seen.has(id) or not integer(progress.respawns[id], 0, mini(253402300799999, int(value.server_time_ms) + 86400000)): return false
	if value.has("hunt_pressure") and not MonsterCombat.pressure_valid(value.hunt_pressure):return false
	if value.has("endless"):
		if not EndlessRules.valid_view(value.endless):return false
		var running:bool=value.get("battle") is Dictionary and value.battle.has("endless") and value.battle.get("outcome")=="active"
		if value.endless.progress.in_progress!=running:return false
	if value.has("gathering") and not GatheringRules.valid(value.gathering):return false
	if not value.has("battle"): return false
	var battle: Variant = value.battle
	if battle == null: return true
	if not battle is Dictionary or not uuid(battle.get("id")) or not decimal(battle.get("revision")): return false
	if battle.has("skill_rules_version"):
		if not integer(battle.skill_rules_version,0,1):return false
		if int(battle.skill_rules_version)==1 and not SkillRules.valid_state(battle.get("skills")):return false
	if not battle.get("outcome") in ["active", "victory", "defeat", "fled"] or not integer(battle.get("round"), 0, 30): return false
	if not battle.get("enemy") is Dictionary: return false
	var enemy: Dictionary = battle.enemy
	if not enemy.get("id") is String: return false
	if not enemy.get("name") is String or enemy.name.length()>24:return false
	if battle.has("endless"):
		if not value.has("endless") or not battle.endless is Dictionary:return false
		var expected:=EndlessRules.monster(battle.endless)
		if expected.is_empty():return false
		if SkillBalance.revised(value.stats):expected=SkillBalance.monster(expected)
		for key in ["id","name","art","kind","hp","attack","defense","level","gold","xp","cell"]:
			if enemy.get(key)!=expected[key]:return false
		if battle.outcome=="active" and (battle.endless.stage!=value.endless.progress.stage or battle.endless.level!=value.endless.progress.level):return false
		if not battle.get("formation") is Dictionary or not battle.formation.get("enemies") is Array or battle.formation.enemies.size()!=1:return false
		if not battle.formation.enemies[0] is Dictionary or not battle.formation.enemies[0].get("definition") is Dictionary:return false
		for key in ["id","name","art","kind","hp","attack","defense","level","gold","xp"]:
			if battle.formation.enemies[0].definition.get(key)!=expected[key]:return false
	elif (not enemy.get("id") in ["wolf_a", "wolf_b", "wolf_c", "spirit", "guardian", "boss"] and AIWorld.resident(enemy.get("id", "")).is_empty()):return false
	elif not AIWorld.resident(enemy.id).is_empty():
		var definition := AIWorld.resident(enemy.id)
		if SkillBalance.revised(value.stats):definition=SkillBalance.monster(definition)
		if SkillBalance.revised(value.stats) and int(battle.get("loot_revision",0))>=1:definition=ProgressionRules.monster(definition)
		if battle.get("formation") is Dictionary and battle.formation.get("monster_revision")==2:definition=MonsterCombat.empower(definition,1)
		for key in ["art", "kind", "hp", "attack", "defense", "level", "gold", "xp"]:
			if enemy.get(key) != definition[key]: return false
		if not OriginalArt.has_actor(definition.art): return false
	elif not enemy.get("art") in ["monster/langw", "monster/hs1", "monster/xt1", "monster/nt1"]: return false
	if not integer(enemy.get("hp"), 1, 100000) or not integer(enemy.get("level"), 1, 60): return false
	if not integer(battle.get("hp"), 0, int(value.stats.hp)) or not integer(battle.get("mp"), 0, int(value.stats.mp)) or not integer(battle.get("enemy_hp"), 0, int(enemy.hp)) or not integer(battle.get("potions"), 0, 99): return false
	if battle.has("formation"):
		var group:Variant=battle.formation
		if not group is Dictionary or not OnlineTeamModel.valid_battle(group,character_id,{character_id:true}) or group.fighters.size()!=1 or group.enemies.size()>3:return false
		var fighter:Dictionary=group.fighters[0]
		if group.outcome!=battle.outcome or fighter.hp!=battle.hp or fighter.mp!=battle.mp or fighter.potions!=battle.potions or group.enemies[0].hp!=battle.enemy_hp:return false
		if group.enemies[0].definition.id!=battle.enemy.id:return false
		if group.outcome=="active" and (fighter.stats!=value.stats or fighter.job!=value.character.job or fighter.level!=value.character.level):return false
	return true

func receive(packet: Dictionary) -> bool:
	var kind: Variant = packet.get("type")
	if not kind in ["pve.state", "pve.result"] or not valid(packet.get("state")): return false
	if kind == "pve.result":
		if not uuid(packet.get("operation_id")) or not packet.get("ok") is bool or not packet.get("replayed") is bool or not packet.get("lines") is Array or packet.lines.size() > 64: return false
		for line in packet.lines:
			if not line is String or line.length() > 200: return false
		if not packet.ok and not packet.get("code") is String: return false
	# An old receipt can acknowledge the outbox, but cannot roll back current state.
	if state.is_empty() or int(packet.state.character.state_revision) >= int(state.character.state_revision):
		# A pre-upgrade receipt at the same revision cannot erase fresh cooldowns.
		var previous_progress: Dictionary = state.get("progress", {})
		var previous_shop: Dictionary = state.get("shop", {})
		var previous_skills:Dictionary=state.get("skills",{})
		var previous_ai: Dictionary = state.get("ai_world", {})
		var previous_loot:Dictionary=state.get("loot",{})
		var previous_endless:Dictionary=state.get("endless",{})
		var previous_gathering:Dictionary=state.get("gathering",{})
		var previous_gourds:Dictionary=state.get("gourds",{})
		var keep_gourds:bool=state.has("gourds") and not packet.state.has("gourds") and packet.state.character.state_revision==state.character.state_revision
		var keep_gathering:bool=state.has("gathering") and not packet.state.has("gathering") and packet.state.character.state_revision==state.character.state_revision
		var keep_endless:bool=state.has("endless") and not packet.state.has("endless") and packet.state.character.state_revision==state.character.state_revision
		var keep_loot:bool=state.has("loot") and not packet.state.has("loot") and packet.state.character.state_revision==state.character.state_revision
		var keep_ai: bool = state.has("ai_world") and not packet.state.has("ai_world") and packet.state.character.state_revision==state.character.state_revision
		var keep_skills:bool=state.has("skills") and not packet.state.has("skills") and packet.state.character.state_revision==state.character.state_revision
		var keep_shop: bool = state.has("shop") and not packet.state.has("shop") and packet.state.character.state_revision == state.character.state_revision
		var previous_equipment: Dictionary = state.get("equipment", {})
		var keep_equipment: bool = state.has("equipment") and not packet.state.has("equipment") and packet.state.character.state_revision == state.character.state_revision
		var keep_respawns: bool = state.has("server_time_ms") and not packet.state.has("server_time_ms") and packet.state.character.state_revision == state.character.state_revision
		var previous_time: int = int(state.get("server_time_ms", 0))
		state = packet.state.duplicate(true)
		if keep_gourds:state.gourds=previous_gourds.duplicate(true)
		if keep_gathering:state.gathering=previous_gathering.duplicate(true)
		if keep_ai: state.ai_world = previous_ai.duplicate(true)
		if keep_loot:state.loot=previous_loot.duplicate(true)
		if keep_endless:state.endless=previous_endless.duplicate(true)
		if keep_skills:state.skills=previous_skills.duplicate(true)
		if keep_shop: state.shop = previous_shop.duplicate(true)
		if keep_equipment: state.equipment = previous_equipment.duplicate(true)
		if keep_respawns:
			state.server_time_ms = previous_time
			state.progress.respawns = previous_progress.respawns.duplicate(true)
		if state.has("server_time_ms"):
			_server_clock_ms = maxi(server_time_ms(), int(state.server_time_ms))
			_server_clock_tick = Time.get_ticks_msec()
		# JSON numbers arrive as floats; typed Rust point arrays require integer JSON.
		if state.has("attributes"):
			state.attributes.allocated = normalized_points(state.attributes.allocated)
			state.attributes.recommended = normalized_points(state.attributes.recommended)
		var character: Dictionary = state.character.duplicate(true)
		if state.has("shop"): character.appearance_v2 = ShopRules.appearance(state.shop)
		if state.has("loot"):character.appearance_v2=state.loot.appearance.duplicate()
		var found := false
		for i in OnlineAccount.characters.size():
			if OnlineAccount.characters[i].id == character.id:
				OnlineAccount.characters[i] = character
				found = true
		if not found: OnlineAccount.characters.append(character)
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

func server_time_ms() -> int:
	return _server_clock_ms + maxi(0, Time.get_ticks_msec() - _server_clock_tick) if _server_clock_ms > 0 else 0

func unavailable_monsters() -> Array:
	var progress: Dictionary = state.get("progress", {})
	# Compatibility with a server that has not yet applied the respawn migration.
	if not progress.has("respawns"): return progress.get("defeated", []).duplicate()
	var hidden: Array = []
	for id in progress.respawns:
		if int(progress.respawns[id]) > server_time_ms(): hidden.append(id)
	for id in state.get("ai_world", {}).get("respawns", {}):
		if int(state.ai_world.respawns[id]) > server_time_ms(): hidden.append(id)
	return hidden

func submit(action: String, target: String = "", points: Array = [], count: int=1, enemy_slot:String="") -> bool:
	if not ready or pending(): return false
	if action in GourdRules.ACTIONS:
		if active() or is_soul() or not state.has("gourds") or count!=1 or not points.is_empty():return false
		var id:=GourdRules.refill_id(action)
		if id.is_empty():id=target
		# Character coordinates can lag movement; the server validates the live position.
		elif target!="qingwei" and (not target.ends_with("_guide") or AIWorld.resident(target).is_empty()):return false
		if not state.gourds.has(id):return false
	if action in ["gather_start","gather_finish","gather_cancel","gather_discard","gather_craft"]:
		if not state.has("gathering") or (count!=1 and action not in ["gather_discard","gather_craft"]) or not points.is_empty():return false
		if action!="gather_cancel" and (active() or is_soul()):return false
		if action=="gather_start" and not state.gathering.nodes.any(func(n:Dictionary)->bool:return n.id==target and int(n.available_at_ms)<=server_time_ms()):return false
		if action in ["gather_finish","gather_cancel"] and not uuid(target):return false
		if action=="gather_discard" and (not GatheringRules.MATERIALS.has(target) or count<1 or count>int(state.gathering.materials.get(target,0))):return false
		if action=="gather_craft":
			if state.gathering.get("recipes_sha256")!=GatheringRules.recipes_hash or not state.has("loot") or not state.has("shop"):return false
			var bag:=ShopRules.bag_slots(state.shop,int(state.potions))+LootRules.extra_bag(state.loot.state)
			if not GatheringRules.craft_error(target,count,state.gathering.materials,int(state.loot.state.scrap),int(state.potions),bag).is_empty():return false
	if not enemy_slot.is_empty() and (not active() or not state.battle.has("formation") or action not in ["attack","skill"] or not state.battle.formation.enemies.any(func(e:Dictionary)->bool:return e.slot==enemy_slot and int(e.hp)>0)):return false
	if is_soul() and action!="revive":return false
	if action=="revive" and (not is_soul() or target!=state.character.corpse.id):return false
	if action=="school_join" and (active() or int(state.character.school)!=SchoolRules.UNJOINED or SchoolRules.index(target)<0):return false
	if action=="scroll_travel":
		if active() or not state.has("shop") or state.shop.version!="shop-v2" or ShopRules.quantity(state.shop,ShopRules.TRAVEL_SCROLL)<1 or count!=1 or not points.is_empty():return false
		if not ShopRules.travel_error(target,String(state.character.map_id),int(state.character.quest_stage)).is_empty():return false
	if action=="endless" and (active() or not state.has("endless") or state.endless.progress.in_progress or target!=EndlessRules.rules.npc.id or state.character.map_id!=EndlessRules.rules.map_id or count!=1 or not points.is_empty()):return false
	if action in ["gear_focus","gear_salvage","gear_reroll","gear_upgrade"] and state.get("loot",{}).get("progression_sha256")!=ProgressionRules.catalog_hash:return false
	if action=="gear_focus" and (active() or not state.has("loot") or (target!="any" and target not in ShopRules.SLOTS) or count!=1 or not points.is_empty()):return false
	if action in ["gear_equip","gear_unequip","gear_claim","gear_salvage","gear_reroll","gear_upgrade"]:
		if active() or not state.has("loot") or not uuid(target) or (count!=1 and action!="gear_reroll") or not points.is_empty():return false
		if action=="gear_reroll" and (count<1 or count>4):return false
		var source:Array=state.loot.state.pending if action=="gear_claim" else state.loot.state.items
		if not source.any(func(i:Dictionary)->bool:return i.id==target):return false
	if action=="skill" and not target.is_empty():
		if not active() or not state.has("skills") or not target in state.skills.available:return false
		if not SkillRules.check(target,int(state.character.job),int(state.character.school),int(state.character.level)).is_empty():return false
	if action in ["buy", "equip", "unequip", "use", "discard"] and state.has("shop"):
		if active() or ShopRules.item(target).is_empty(): return false
		if action != "buy" and ShopRules.quantity(state.shop,target)<count: return false
		if action in ["use","discard"] and state.shop.version!="shop-v2": return false
		if count<1 or count>99: return false
	elif action in ["equip", "unequip"]:
		if active() or not state.has("equipment") or not state.equipment.weapon_owned or target != "sword": return false
		if (state.equipment.weapon == "sword") == (action == "equip"): return false
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
	elif action=="respec":
		if active() or not state.character.get("balance_respec_available",false):return false
		command.expected_revision=state.character.state_revision
	elif action in GourdRules.ACTIONS or action in ["gather_start","gather_finish","gather_cancel","gather_discard","gather_craft","buy", "equip", "unequip", "use", "discard","school_join","scroll_travel","revive","endless","gear_equip","gear_unequip","gear_claim","gear_salvage","gear_reroll","gear_upgrade","gear_focus"]:
		command.target = target
		if count!=1 or action=="gear_reroll": command.quantity=count
		command.expected_revision = state.character.state_revision
	elif action=="skill" and active():
		if not target.is_empty():command.target=target
		command.battle_id=state.battle.id
		command.expected_revision=state.battle.revision
	elif not target.is_empty(): command.target = target
	elif active():
		command.battle_id = state.battle.id
		command.expected_revision = state.battle.revision
	if action in ["challenge","endless"]:command.encounter_version=2
	if not enemy_slot.is_empty():command.enemy_slot=enemy_slot
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
	if state.has("ai_world") and not AIWorld.map_data(state.character.map_id).is_empty(): return AIWorld.quest_hint(state.character.map_id,state.ai_world,int(state.character.level))
	var stage := int(state.character.quest_stage)
	if stage == 0: return "山林试炼\n前往桥边拜访清微道人，领受试炼。"
	if stage == 1: return "山林试炼\n击败山狼 %d / 3\n三只山狼各计一次，请留意小地图红点。" % int(state.progress.kills)
	if stage == 2: return "山林试炼\n山狼已清除，返回清微道人处领取奖励。\n奖励：60铜钱、35修为。"
	if stage == 3: return "山林试炼 · 已完成\n穿过东侧灵门进入古剑遗迹，击败赤焰妖王。"
	return "古剑遗迹 · 已完成\n妖气已散，可返回青云山道恢复元气，或继续探索遗迹。"

static func error_text(code: String) -> String:
	var gourds:={"GOURD_NOT_OWNED":"请先在商城购买对应葫芦。","GOURD_FULL":"葫芦储量已满，无需补充。","GOURD_NPC_REQUIRED":"请到清微道人或本地图巡山人处补充葫芦。"}
	if gourds.has(code):return gourds[code]
	if code=="MAP_CLOSED":return "目标地图暂时禁止进入，请选择其他目的地；传送道具未消耗。"
	var gathering:={"INVALID_GATHER_COMMAND":"无效的采集或加工请求。","GATHER_NOT_FOUND":"当前地图没有这个可采集资源。","GATHER_TOO_FAR":"请先走到资源旁并停稳。","GATHER_COOLDOWN":"该资源正在刷新，请稍候。","GATHER_BUSY":"正在采集，请先完成或取消。","GATHER_NOT_READY":"采集尚未完成，请等待进度结束。","GATHER_INTERRUPTED":"操作已中断，请停稳后重新确认。","STALE_GATHERING":"角色状态已变化，请重新确认。","MATERIAL_BAG_FULL":"该材料已接近999份上限，请先整理材料袋。","INVALID_GATHER_STATE":"采集记录异常，请重新同步。","CRAFT_RESOURCE_FULL":"炼材已达容量上限，请先使用后再加工。"}
	if gathering.has(code):return gathering[code]
	if code=="TRAVEL_SCROLL_REQUIRED":return "神行符不足，请先到商店购买。"
	if code=="TRAVEL_DESTINATION_REQUIRED":return "请先选择神行符的传送目的地。"
	var endless:={"ENDLESS_NPC_REQUIRED":"请到主城灵空台，与守境人交谈开启无尽试炼。","ENDLESS_NOT_READY":"请先停稳，再进入试炼。","ENDLESS_SOLO_ONLY":"无尽试炼为单人模式，请先退出队伍。","ENDLESS_LIMIT":"已到达当前数值安全极限，最高纪录已保留。","INVALID_ENDLESS_STATE":"试炼记录异常，请重新同步后重试。","STALE_ENDLESS":"试炼记录已更新，请重新确认挑战。"}
	if endless.has(code):return endless[code]
	var crafting:={"LOOT_STORAGE_FULL":"装备暂存空间不足，请领取或分解后再战。","LEGACY_CRAFT_LOCKED":"原有固定装备保留原数值，不参与分解、洗炼或强化。","UPGRADE_LIMIT":"已达到+6强化上限。","NO_AFFIXES":"普通装备没有可洗炼的词条。","REROLL_LIMIT":"此装备已达到20次洗炼上限。","UNEQUIP_BEFORE_SALVAGE":"请先卸下装备，再确认分解。","MATERIALS_INSUFFICIENT":"所需材料不足，请先补充材料。","INVALID_AFFIX_INDEX":"请选择有效的词条。","REROLL_SLOT_LOCKED":"此装备已锁定另一条洗炼词条。"}
	if crafting.has(code):return crafting[code]
	var loot:={"INSTANCE_NOT_OWNED":"没有这件装备实例，请重新同步。","EQUIPMENT_LEVEL_REQUIRED":"等级不足，暂时不能装备。","NOT_EQUIPPED":"这件装备尚未穿戴。","INVALID_LOOT_COMMAND":"无效的装备操作。"}
	if loot.has(code):return loot[code]
	if code=="NO_ALLOCATED_ATTRIBUTES": return "尚未分配属性点，无需使用重生再造丹；道具未消耗。"
	if code=="CLIENT_UPDATE_REQUIRED":return "连续挑战已触发精英，请更新客户端后继续。"
	if code=="SKILL_COOLDOWN":return "技能尚在冷却，请选择其他指令。"
	var souls:={"SOUL_STATE":"灵魂状态下只能移动和寻回尸体，请先到自己的坟堆旁复活。","CORPSE_NOT_FOUND":"这不是你的尸体，或已经复活。","NO_CORPSE":"当前没有可寻回的尸体。","CORPSE_TOO_FAR":"请靠近自己的坟堆后复活。","STALE_CORPSE":"灵魂状态已更新，请重新同步后再试。"}
	if souls.has(code):return souls[code]
	var schools:={"INVALID_SCHOOL":"请选择有效门派。","SCHOOL_ALREADY_JOINED":"已正式入派，不能重复加入其他门派。","STALE_SCHOOL":"角色状态已变化，请重新与清微道人交谈。","INVALID_SCHOOL_NPC":"请在青云山道找清微道人办理入派。"}
	if schools.has(code):return schools[code]
	var ai := {"AI_INVALID_TARGET":"AI生成目标不属于当前地图。", "AI_QUEST_LIMIT":"最多同时接取三个AI生成任务。", "AI_LEVEL_REQUIRED":"等级不足，请先完成较低等级区域。", "AI_PREREQUISITE":"请先完成本地图的前章任务。", "AI_NO_OBJECTIVE":"先接取任务，并按目标顺序调查。", "AI_SAME_MAP":"已经在当前地图。"}
	if ai.has(code): return ai[code]
	var skills:={"INVALID_SKILL":"未知技能，请更新客户端。","SKILL_ROLE_MISMATCH":"此技能不属于当前职业。","SKILL_LEVEL_REQUIRED":"角色等级尚未达到技能要求。","PASSIVE_SKILL":"此心法自动生效，无需施展。"}
	if skills.has(code):return skills[code]
	var equipment := {"WRONG_JOB":"此装备不适合当前职业。", "WRONG_GENDER":"此装备不适合当前性别。", "INVALID_QUANTITY":"数量无效。", "ITEM_NOT_USABLE":"此物品不能直接使用。","GOLD_INSUFFICIENT":"铜钱不足。", "ITEM_ALREADY_OWNED":"已拥有此物品，每种限持一个。", "BAG_FULL":"背包或补给已满。","INVALID_EQUIPMENT":"此装备尚未开放。", "STALE_EQUIPMENT":"背包状态已更新，请重新选择。", "WEAPON_NOT_OWNED":"背包中没有这件装备。", "EQUIPMENT_UNCHANGED":"当前已是该装备状态。"}
	if equipment.has(code): return equipment[code]
	if code == "PORTAL_LOCKED": return "灵门未开，请完成山狼试炼并向清微道人复命。"
	if code == "PORTAL_TOO_FAR": return "请走近灵门后再传送。"
	if code == "MAP_CHANGED": return "地图已切换，请等待同步完成。"
	if code == "MONSTER_RESPAWNING": return "怪物正在刷新，请稍候再来。"
	var attributes := {"STALE_ATTRIBUTES":"属性已更新，请重新加点。", "ATTRIBUTE_RESPEC_FORBIDDEN":"已保存的属性点不能减少。", "ATTRIBUTE_POINTS_EXCEEDED":"剩余属性点不足。", "NO_ATTRIBUTE_CHANGE":"请先分配属性点。", "INVALID_ATTRIBUTES":"属性点格式无效。"}
	if attributes.has(code): return attributes[code]
	return {"PLAYER_MOVING":"请停稳后再交互。", "RESIDENT_TOO_FAR":"距离过远，请靠近后再试。", "QUEST_REQUIRED":"请先向清微道人接取山林试炼。", "QUEST_NOT_READY":"试炼尚未完成或奖励已经领取。", "QUEST_ALREADY_ACCEPTED":"已经领受过此试炼。", "MONSTER_DEFEATED":"你已经击败过这只怪物。", "STALE_BATTLE":"回合已经更新，请重新选择行动。", "MP_INSUFFICIENT":"灵力不足，可凝神防御恢复灵力。", "NO_POTION":"回春散已经用完。", "HP_FULL":"当前生命已满。", "BATTLE_ACTIVE":"请先完成当前战斗。"}.get(code,"操作未完成：" + code)

static func valid_points(value: Variant) -> bool:
	if not value is Array or value.size() != 5: return false
	for point in value:
		if not integer(point, 0, 300): return false
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
	if not integer(profile.get("available"), 0, 300) or int(profile.available) != budget - spent or recommended != budget: return false
	if not profile.get("combat") is Dictionary: return false
	for key in ["hp", "mp", "physical_attack", "magic_attack", "physical_defense", "magic_defense", "physical_crit", "magic_crit", "physical_hit", "magic_hit", "physical_evasion", "magic_evasion", "damage_reduction"]:
		if not integer(profile.combat.get(key), 0, 10000): return false
	var magic_defense:Variant=value.stats.get("balance",{}).get("magic_defense",value.stats.defense)
	return profile.combat.hp == value.stats.hp and profile.combat.mp == value.stats.mp and profile.combat.physical_defense == value.stats.defense and profile.combat.magic_defense == magic_defense and profile.combat.get("magic_attack" if int(value.character.job) == 2 else "physical_attack") == value.stats.attack
