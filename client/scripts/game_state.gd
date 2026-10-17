extends Node
## Local rules are newly authored. Original server formulas were not recovered.

const JOBS := ["力士", "侠客", "隐者"]
const SCHOOLS := ["峨眉", "花涧", "昆仑"]
const SAVE_VERSION := 1
const MAX_LOCAL_CHARACTERS := 5
const START_CELL := Vector2i(10, 16)
const ENEMY_RESPAWN_SECONDS := 30.0 # Offline rule; not a recovered original server value.
const ATTRIBUTE_RULES = preload("res://scripts/character_attribute_rules.gd")
var save_path := "user://shushan_save.json"
var player: Dictionary = {}
var last_save_error := ""
var _initialization_result: PlatformResult
signal storage_changed(active: bool)
var storage_busy := false
var last_save_receipt: Dictionary = {}
var _player_generation := 0
var _load_epoch := 0
var _operation_path := ""
var _storage_announced := false
var _local_roster_busy := false

func _local_snapshot() -> Dictionary:
	var snapshot := player.duplicate(true)
	snapshot.erase("local_characters")
	return snapshot

func local_character_entries() -> Array:
	if player.is_empty(): return []
	var entries: Array = player.get("local_characters", {}).get("characters", [{"id": "legacy", "data": _local_snapshot()}]).duplicate(true)
	for entry in entries:
		if entry.id == active_local_character_id(): entry.data = _local_snapshot()
	return entries

func active_local_character_id() -> String:
	return String(player.get("local_characters", {}).get("active_id", "legacy"))

func local_characters() -> Array:
	var characters: Array = []
	for entry in local_character_entries():
		var character: Dictionary = entry.data.duplicate(true)
		character.id = entry.id
		characters.append(character)
	return characters

func _save_payload() -> Dictionary:
	var data := player.duplicate(true)
	if data.has("local_characters"): data.local_characters.characters = local_character_entries()
	return data

func create_local_character(nickname: String, job: int, school: int, gender: int) -> PlatformResult:
	if _local_roster_busy or storage_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "STORAGE_BUSY", "正在处理存档，请稍候。")
	_local_roster_busy = true
	var before := player.duplicate(true)
	var path := save_path
	var probe := await probe_save()
	var result: PlatformResult = probe
	var entries: Array = []
	if probe.ok and probe.value:
		result = await load_game()
		if result.ok: entries = local_character_entries()
	if not result.ok:
		_local_roster_busy = false
		return result
	if entries.size() >= MAX_LOCAL_CHARACTERS:
		_local_roster_busy = false
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "CHARACTER_LIMIT_REACHED", "本地角色已满（5/5）。")
	for entry in entries:
		if String(entry.data.name) == nickname.strip_edges().left(24):
			_local_roster_busy = false
			return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "NAME_TAKEN", "已有同名本地角色，请修改昵称或返回选择。")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	new_player(nickname, job, school, gender)
	entries.append({"id": id, "data": _local_snapshot()})
	player.local_characters = {"version": 1, "active_id": id, "characters": entries}
	var generation := _player_generation
	result = await save_game()
	if not result.ok and generation == _player_generation and path == save_path:
		player = before
		_player_generation += 1
	_local_roster_busy = false
	return result

func select_local_character(id: String) -> PlatformResult:
	if _local_roster_busy or storage_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "STORAGE_BUSY", "正在处理存档，请稍候。")
	_local_roster_busy = true
	var result := await load_game()
	if not result.ok:
		_local_roster_busy = false
		return result
	if id == active_local_character_id():
		_local_roster_busy = false
		return result
	var before := player.duplicate(true)
	var entries := local_character_entries()
	var found := false
	for entry in entries:
		if entry.id == id:
			player = entry.data.duplicate(true)
			found = true
	if not found:
		_local_roster_busy = false
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "CHARACTER_NOT_FOUND", "角色不存在，请重新读取存档。")
	player.local_characters = {"version": 1, "active_id": id, "characters": entries}
	_player_generation += 1
	var generation := _player_generation
	var path := save_path
	result = await save_game()
	if not result.ok and generation == _player_generation and path == save_path:
		player = before
		_player_generation += 1
	_local_roster_busy = false
	return result

func invalidate_load() -> void:
	_load_epoch += 1

func _ready() -> void:
	await when_ready()

func when_ready() -> PlatformResult:
	if _initialization_result != null: return _initialization_result
	var result := await Platform.when_ready()
	if not result.ok:
		last_save_error = result.message
		return result
	if _initialization_result != null: return _initialization_result
	var path := Platform.context.runtime_config.local_path("save")
	if path.ok: save_path = path.value
	else: last_save_error = path.message
	_initialization_result = path
	return path

func new_player(nickname: String, job: int, school: int, gender: int = 0) -> void:
	_player_generation += 1
	last_save_receipt = {}
	player = {
		"version": SAVE_VERSION, "name": nickname.strip_edges().left(24), "gender": clampi(gender, 0, 1),
		"job": clampi(job, 0, 2), "school": clampi(school, 0, 2),
		"level": 1, "xp": 0, "gold": 30, "potions": 6,
		"hp": 0, "mp": 0, "quest": 0, "kills": 0,
		"equipped": false, "zone": 0, "cell": [START_CELL.x, START_CELL.y],
		"defeated": [], "enemy_respawns": {}, "signature": "", "title": "",
		"ingots": 0, "guild_contribution": 0, "essence": 0,
		"allocated_attributes": [0,0,0,0,0]
	}
	if String(player.name).is_empty():
		player.name = "青衫客"
	restore()
	player.weapon_owned = true
	player.bag_order = ["potion", "sword"]

func bag_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var gear := ShopRules.local_state(player)
	var order: Array = player.get("bag_order", ["potion", "sword"])
	for id in order:
		if id == "potion":
			var left := int(player.potions)
			while left > 0:
				var dose := ShopRules.bag_item("potion")
				dose.count=mini(99,left)
				items.append(dose)
				left -= 99
		elif id == "sword" and gear.owned.has("sword") and gear.weapon != "sword":
			items.append(ShopRules.bag_item("sword"))
	for id in gear.owned:
		if id=="sword": continue
		var on := false
		for slot in ShopRules.SLOTS:
			if ShopRules.equipped_id(gear,slot)==id: on=true
		if not on:
			var entry := ShopRules.bag_item(id,int(player.job))
			entry.count=ShopRules.quantity(gear,id)
			items.append(entry)
	return items

func bag_buy_potion() -> bool:
	if int(player.gold) < 8: return false
	# An unequipped sword also occupies one of the sixty inventory slots.
	var gear := ShopRules.local_state(player)
	var gear_slots: int = gear.owned.filter(func(id: String) -> bool: return gear.weapon != id and gear.armor != id).size()
	if int(player.potions) >= (60 - gear_slots) * 99: return false
	player.gold = int(player.gold) - 8
	player.potions = int(player.potions) + 1
	return true

func actor_key() -> String:
	var keys := ["mzs", "mck", "mfs"] if int(player.get("gender", 0)) == 0 else ["wzs", "wck", "wfs"]
	return "hero/" + keys[int(player.get("job", 0))]

func stats() -> Dictionary:
	var value: Dictionary = ATTRIBUTE_RULES.stats(int(player.get("job",1)),int(player.get("level",1)),bool(player.get("equipped",false)),allocated_attributes())
	var gear_bonus := ShopRules.bonus(ShopRules.local_state(player))
	value.attack += gear_bonus.x - (5 if player.get("equipped",false) else 0)
	value.defense += gear_bonus.y
	return value

func allocated_attributes() -> Array:
	var points: Array = player.get("allocated_attributes", [0,0,0,0,0]).duplicate()
	for i in points.size(): points[i] = int(points[i])
	return points

func attribute_profile() -> Dictionary:
	var value: Dictionary = ATTRIBUTE_RULES.profile(int(player.get("job",1)),int(player.get("level",1)),bool(player.get("equipped",false)),allocated_attributes())
	var gear_bonus := ShopRules.bonus(ShopRules.local_state(player))
	for key in ["physical_attack","magic_attack"]: value.combat[key] += gear_bonus.x - (5 if player.get("equipped",false) else 0)
	for key in ["physical_defense","magic_defense"]: value.combat[key] += gear_bonus.y
	return value

func appearance_key() -> String:
	return ShopRules.actor_key(int(player.get("job",0)),int(player.get("gender",0)),ShopRules.appearance(ShopRules.local_state(player)))

func shop_command(action: String, id: String, count: int=1) -> PlatformResult:
	if storage_busy or _local_roster_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候")
	var before := player.duplicate(true)
	var generation := _player_generation
	var path := save_path
	var code := ShopRules.apply_local(player,action,id,count,stats())
	if not code.is_empty(): return PlatformResult.new(PlatformResult.Status.INVALID_DATA,code,OnlinePve.error_text(code))
	var result := await save_game()
	if not result.ok and generation == _player_generation and path == save_path: player = before
	return result


func allocate_attributes(points: Array) -> PlatformResult:
	if storage_busy or _local_roster_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候")
	if player.is_empty() or not ATTRIBUTE_RULES.valid_points(points,int(player.get("level",1)),allocated_attributes()):
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_ATTRIBUTES","属性点格式或剩余点数无效，已保存的点数不能减少。")
	if points == allocated_attributes(): return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"NO_ATTRIBUTE_CHANGE","请先分配属性点。")
	var before := player.duplicate(true)
	var previous_stats := stats()
	var generation := _player_generation
	var path := save_path
	player.allocated_attributes = points.duplicate()
	for i in 5: player.allocated_attributes[i] = int(player.allocated_attributes[i])
	var next_stats := stats()
	player.hp = int(player.hp) + int(next_stats.hp) - int(previous_stats.hp)
	player.mp = int(player.mp) + int(next_stats.mp) - int(previous_stats.mp)
	var result := await save_game()
	if not result.ok and generation == _player_generation and path == save_path: player = before
	return result

func restore() -> void:
	var values := stats()
	player.hp = values.hp
	player.mp = values.mp

func add_rewards(gold: int, xp: int) -> bool:
	player.gold = int(player.gold) + gold
	player.xp = int(player.xp) + xp
	var leveled := false
	while int(player.xp) >= int(player.level) * 40 and int(player.level) < 60:
		player.xp = int(player.xp) - int(player.level) * 40
		player.level = int(player.level) + 1
		leveled = true
	if leveled:
		restore()
	return leveled

func quest_text() -> String:
	match int(player.get("quest", 0)):
		0: return "拜访石桥旁的清微道人"
		1: return "山林试炼：击败山狼 %d / 3" % int(player.kills)
		2: return "试炼完成，返回清微道人处"
		3: return "穿过东侧灵门，击败遗迹妖王"
		_: return "蜀山初行已完成 · 自由探索"

func enemy_respawn_remaining(id: String, now: float = -1.0) -> float:
	if now < 0.0: now = Time.get_unix_time_from_system()
	return maxf(0.0, float(player.get("enemy_respawns", {}).get(id, 0.0)) - now)

func enemy_available(id: String, now: float = -1.0) -> bool:
	# Defeated is quest history, not the current world population. Missing
	# deadlines in legacy saves allow those monsters to return immediately.
	return enemy_respawn_remaining(id, now) <= 0.0

func finish_enemy(enemy: Dictionary) -> bool:
	var id := String(enemy.id)
	if not player.defeated.has(id):
		player.defeated.append(id)
	if not player.has("enemy_respawns"): player.enemy_respawns = {}
	# Persist wall-clock deadlines so changing maps or restarting the game
	# neither restarts the cooldown nor loses time spent outside the world.
	player.enemy_respawns[id] = Time.get_unix_time_from_system() + ENEMY_RESPAWN_SECONDS
	if int(player.quest) == 1 and String(enemy.kind) == "wolf":
		player.kills = mini(3, int(player.kills) + 1)
		if int(player.kills) >= 3:
			player.quest = 2
	if String(enemy.kind) == "boss" and int(player.quest) == 3:
		player.quest = 4
	return add_rewards(int(enemy.gold), int(enemy.xp))

func _begin_storage() -> PlatformResult:
	if storage_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "STORAGE_BUSY", "存档操作尚未完成，请稍后重试。")
	if not Platform.is_available():
		last_save_error = "平台尚未就绪，无法读写存档。"
		return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "PLATFORM_NOT_READY", last_save_error)
	last_save_error = ""
	storage_busy = true
	_operation_path = save_path
	_storage_announced = false
	return PlatformResult.success()

func _await_storage(request: PlatformStorageRequest) -> PlatformResult:
	if request == null:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_STORAGE_REQUEST", "无法创建有效的存档操作。")
	# Immediate native IO must not pause animations, clear movement markers or
	# flash a loading overlay. Announce only an actual asynchronous barrier.
	if request.result == null:
		_storage_announced = true
		storage_changed.emit(true)
	return await request.wait()

func _finish_storage(result: PlatformResult, generation: int) -> PlatformResult:
	if generation != _player_generation or _operation_path != save_path:
		result = PlatformResult.new(PlatformResult.Status.CANCELLED, "STALE_SAVE_OPERATION", "角色或存档路径已变化，旧存档操作结果未应用。")
	elif result.status != PlatformResult.Status.CANCELLED:
		last_save_error = result.message if not result.ok and result.code != "NOT_FOUND" else ""
	storage_busy = false
	var announced := _storage_announced
	_storage_announced = false
	if announced: storage_changed.emit(false)
	return result

func wait_for_storage() -> void:
	while storage_busy: await storage_changed

func save_game() -> PlatformResult:
	var admitted := _begin_storage()
	if not admitted.ok: return admitted
	var generation := _player_generation
	last_save_receipt = {}
	if player.is_empty():
		return _finish_storage(PlatformResult.new(PlatformResult.Status.INVALID_DATA, "EMPTY_PLAYER", "没有可保存的离线角色。"), generation)
	# Serialize now: delayed IO must not observe subsequent dictionary mutations.
	var payload := _save_payload()
	var result := await _await_storage(Platform.context.storage.write(_operation_path, JSON.stringify(payload, "\t")))
	if result.ok:
		if not result.value is Dictionary or result.value.get("written") != true or result.value.get("durability") not in ["native_file", "browser_sync"]:
			result = PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "SAVE_UNCONFIRMED", "存档持久化未确认，请重试；当前进度仍在内存中。")
		elif generation == _player_generation and _operation_path == save_path:
			last_save_receipt = result.value.duplicate(true)
			if payload.has("local_characters"): player.local_characters = payload.local_characters
	return _finish_storage(result, generation)

func probe_save() -> PlatformResult:
	var admitted := _begin_storage()
	if not admitted.ok: return admitted
	var generation := _player_generation
	var epoch := _load_epoch
	var result := await _await_storage(Platform.context.storage.probe(_operation_path))
	if epoch != _load_epoch:
		result = PlatformResult.new(PlatformResult.Status.CANCELLED, "STALE_LOAD", "旧页面的存档检查结果未应用。")
	if result.ok and not result.value is bool:
		result = PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_STORAGE_RESULT", "无法确认存档是否存在，请重试。")
	return _finish_storage(result, generation)

func load_game() -> PlatformResult:
	var admitted := _begin_storage()
	if not admitted.ok: return admitted
	var generation := _player_generation
	var epoch := _load_epoch
	var result := await _await_storage(Platform.context.storage.read(_operation_path))
	if epoch != _load_epoch:
		result = PlatformResult.new(PlatformResult.Status.CANCELLED, "STALE_LOAD", "旧页面的读取结果未应用。")
	if not result.ok or generation != _player_generation or _operation_path != save_path: return _finish_storage(result, generation)
	var parser := JSON.new()
	if not result.value is String or parser.parse(result.value) != OK:
		return _finish_storage(_invalid_save(), generation)
	var data: Variant = parser.data
	if not valid_save(data):
		return _finish_storage(_invalid_save(), generation)
	player = data
	last_save_receipt = {}
	if not player.has("gender"): player.gender = 0
	for key in ["signature", "title"]:
		if not player.has(key): player[key] = ""
	for key in ["ingots", "guild_contribution", "essence"]:
		if not player.has(key): player[key] = 0
	if not player.has("weapon_owned"): player.weapon_owned = true
	if not player.has("bag_order"): player.bag_order = ["potion", "sword"]
	if not player.has("enemy_respawns"): player.enemy_respawns = {}
	_player_generation += 1
	result = _finish_storage(PlatformResult.success(), _player_generation)
	return result

func _invalid_save() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_SAVE", "存档格式不正确，原文件已保留")

func valid_save(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.has("local_characters") and not _valid_local_roster(data): return false
	for key in ["version", "name", "job", "school", "level", "xp", "gold", "potions", "hp", "mp", "quest", "kills", "equipped", "zone", "cell", "defeated"]:
		if not data.has(key): return false
	if not data.name is String or data.name.length() > 24 or data.name.is_empty(): return false
	var gender: Variant = data.get("gender", 0)
	if not (gender is int or gender is float) or not is_finite(float(gender)): return false
	if float(gender) != floor(float(gender)) or gender < 0 or gender > 1: return false
	if not data.equipped is bool: return false
	if not data.get("weapon_owned", true) is bool: return false
	if data.equipped and not data.get("weapon_owned", true) and not data.has("shop_weapon"): return false
	if not data.get("shop_owned",[]) is Array or not data.get("shop_slots",{}) is Dictionary or not data.get("shop_quantities",{}) is Dictionary: return false
	if not ShopRules.valid_gear(ShopRules.local_state(data)): return false
	if data.has("shop_owned") and (not data.shop_owned is Array or data.shop_owned.has("sword")): return false
	if data.has("shop_weapon") and bool(data.equipped) != (data.shop_weapon != null): return false
	var local_gear := ShopRules.local_state(data)
	for slot in ["weapon","armor"]:
		if data.get("shop_slots",{}).has(slot) and data.shop_slots[slot]!=local_gear[slot]: return false
	for id in data.get("shop_quantities",{}):
		if not local_gear.owned.has(id) or not ShopRules._integer(data.shop_quantities[id],1,1 if ShopRules.is_equipment(ShopRules.item(id)) else 99): return false
	for slot in ShopRules.SLOTS:
		var id: Variant = ShopRules.equipped_id(local_gear,slot)
		if id!=null and int(ShopRules.item(id).job)>=0 and int(ShopRules.item(id).job)!=int(data.job): return false
	var order: Variant = data.get("bag_order", ["potion", "sword"])
	if not order is Array or order.size() != 2 or not order.has("potion") or not order.has("sword"): return false
	for key in ["signature", "title"]:
		var value: Variant = data.get(key, "")
		if not value is String or value.length() > (40 if key == "signature" else 24): return false
	for key in ["ingots", "guild_contribution", "essence"]:
		var value: Variant = data.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)): return false
		if float(value) != floor(float(value)) or value < 0 or value > 1000000000: return false
	for key in ["version", "job", "school", "level", "xp", "gold", "potions", "hp", "mp", "quest", "kills", "zone"]:
		if not (data[key] is int or data[key] is float): return false
		if not is_finite(float(data[key])) or float(data[key]) != floor(float(data[key])): return false
		if data[key] < 0 or data[key] > 1000000: return false
	if int(data.version) != SAVE_VERSION: return false
	if int(data.job) > 2 or int(data.school) > 2 or int(data.zone) > 1: return false
	if int(data.quest) > 4 or int(data.kills) > 3: return false
	if int(data.level) < 1 or int(data.level) > 60: return false
	if not ATTRIBUTE_RULES.valid_points(data.get("allocated_attributes",[0,0,0,0,0]),int(data.level)): return false
	if not data.cell is Array or data.cell.size() != 2: return false
	for value in data.cell:
		if not (value is float or value is int) or not is_finite(float(value)): return false
		if float(value) != floor(float(value)) or value < 1 or value > 30: return false
	if not data.defeated is Array or data.defeated.size() > 20: return false
	for value in data.defeated:
		if not value is String: return false
	var respawns: Variant = data.get("enemy_respawns", {})
	if not respawns is Dictionary or respawns.size() > 20: return false
	for id in respawns:
		if not id is String or id.is_empty() or id.length() > 64: return false
		var deadline: Variant = respawns[id]
		if not (deadline is int or deadline is float) or not is_finite(float(deadline)): return false
		if deadline < 0 or deadline > 253402300799.0: return false
	var old := player
	player = data
	var values := stats()
	player = old
	return int(data.hp) <= int(values.hp) and int(data.mp) <= int(values.mp)

func _valid_local_roster(data: Dictionary) -> bool:
	var roster: Variant = data.local_characters
	if not roster is Dictionary or roster.get("version") != 1 or not roster.get("active_id") is String or not roster.get("characters") is Array: return false
	if roster.characters.is_empty() or roster.characters.size() > MAX_LOCAL_CHARACTERS: return false
	var ids := {}
	var active_found := false
	var current := data.duplicate(true)
	current.erase("local_characters")
	for entry in roster.characters:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("data") is Dictionary: return false
		if entry.id != "legacy" and RegEx.create_from_string("^[0-9a-f]{32}\\z").search(entry.id) == null: return false
		if ids.has(entry.id) or entry.data.has("local_characters") or not valid_save(entry.data): return false
		ids[entry.id] = true
		if entry.id == roster.active_id:
			if entry.data != current: return false
			active_found = true
	return active_found
