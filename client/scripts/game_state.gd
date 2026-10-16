extends Node
## Local rules are newly authored. Original server formulas were not recovered.

const JOBS := ["力士", "侠客", "隐者"]
const SCHOOLS := ["峨眉", "花涧", "昆仑"]
const SAVE_VERSION := 1
const START_CELL := Vector2i(10, 16)
const ENEMY_RESPAWN_SECONDS := 30.0 # Offline rule; not a recovered original server value.
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
		"ingots": 0, "guild_contribution": 0, "essence": 0
	}
	if String(player.name).is_empty():
		player.name = "青衫客"
	restore()
	player.weapon_owned = true
	player.bag_order = ["potion", "sword"]

func bag_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var order: Array = player.get("bag_order", ["potion", "sword"])
	for id in order:
		if id == "potion":
			var left := int(player.potions)
			while left > 0:
				items.append({"id": "potion", "name": "回春散", "count": mini(99, left), "level": 1, "icon": "res://assets/ui/bag_potion.png"})
				left -= 99
		elif id == "sword" and player.get("weapon_owned", true) and not player.equipped:
			items.append({"id": "sword", "name": "青锋剑", "count": 1, "level": 1, "icon": "res://assets/ui/bag_sword.png"})
	return items

func bag_buy_potion() -> bool:
	if int(player.gold) < 8: return false
	# An unequipped sword also occupies one of the sixty inventory slots.
	var sword_slots := 1 if player.get("weapon_owned", true) and not player.equipped else 0
	if int(player.potions) >= (60 - sword_slots) * 99: return false
	player.gold = int(player.gold) - 8
	player.potions = int(player.potions) + 1
	return true

func actor_key() -> String:
	var keys := ["mzs", "mck", "mfs"] if int(player.get("gender", 0)) == 0 else ["wzs", "wck", "wfs"]
	return "hero/" + keys[int(player.get("job", 0))]

func stats() -> Dictionary:
	var level := int(player.get("level", 1))
	var job := int(player.get("job", 1))
	return {
		"hp": [120, 95, 85][job] + (level - 1) * 18,
		"mp": [35, 45, 65][job] + (level - 1) * 8,
		"attack": [18, 23, 21][job] + (level - 1) * 4 + (5 if player.get("equipped", false) else 0),
		"defense": [7, 4, 3][job] + (level - 1) * 2
	}

func restore() -> void:
	var values := stats()
	player.hp = values.hp
	player.mp = values.mp

func add_rewards(gold: int, xp: int) -> bool:
	player.gold = int(player.gold) + gold
	player.xp = int(player.xp) + xp
	var leveled := false
	while int(player.xp) >= int(player.level) * 40 and int(player.level) < 50:
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
	var result := await _await_storage(Platform.context.storage.write(_operation_path, JSON.stringify(player, "\t")))
	if result.ok:
		if not result.value is Dictionary or result.value.get("written") != true or result.value.get("durability") not in ["native_file", "browser_sync"]:
			result = PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "SAVE_UNCONFIRMED", "存档持久化未确认，请重试；当前进度仍在内存中。")
		elif generation == _player_generation and _operation_path == save_path: last_save_receipt = result.value.duplicate(true)
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
	for key in ["version", "name", "job", "school", "level", "xp", "gold", "potions", "hp", "mp", "quest", "kills", "equipped", "zone", "cell", "defeated"]:
		if not data.has(key): return false
	if not data.name is String or data.name.length() > 24 or data.name.is_empty(): return false
	var gender: Variant = data.get("gender", 0)
	if not (gender is int or gender is float) or not is_finite(float(gender)): return false
	if float(gender) != floor(float(gender)) or gender < 0 or gender > 1: return false
	if not data.equipped is bool: return false
	if not data.get("weapon_owned", true) is bool: return false
	if data.equipped and not data.get("weapon_owned", true): return false
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
	if int(data.level) < 1 or int(data.level) > 50: return false
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
