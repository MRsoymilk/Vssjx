extends Node
## Local rules are newly authored. Original server formulas were not recovered.

const JOBS := ["力士", "侠客", "隐者"]
const SCHOOLS := ["峨眉", "花涧", "昆仑"]
const SAVE_VERSION := 1
const START_CELL := Vector2i(10, 16)
var save_path := "user://shushan_save.json"
var player: Dictionary = {}
var last_save_error := ""

func _ready() -> void:
	var override := OS.get_environment("SSJX_SAVE_PATH")
	if not override.is_empty():
		save_path = override

func new_player(nickname: String, job: int, school: int, gender: int = 0) -> void:
	player = {
		"version": SAVE_VERSION, "name": nickname.strip_edges().left(24), "gender": clampi(gender, 0, 1),
		"job": clampi(job, 0, 2), "school": clampi(school, 0, 2),
		"level": 1, "xp": 0, "gold": 30, "potions": 6,
		"hp": 0, "mp": 0, "quest": 0, "kills": 0,
		"equipped": false, "zone": 0, "cell": [START_CELL.x, START_CELL.y],
		"defeated": [], "signature": "", "title": "",
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

func finish_enemy(enemy: Dictionary) -> bool:
	var id := String(enemy.id)
	if not player.defeated.has(id):
		player.defeated.append(id)
	if int(player.quest) == 1 and String(enemy.kind) == "wolf":
		player.kills = mini(3, int(player.kills) + 1)
		if int(player.kills) >= 3:
			player.quest = 2
	if String(enemy.kind) == "boss" and int(player.quest) == 3:
		player.quest = 4
	return add_rewards(int(enemy.gold), int(enemy.xp))

func save_game() -> bool:
	if player.is_empty():
		return false
	last_save_error = ""
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_save_error = "无法写入本地存档"
		return false
	file.store_string(JSON.stringify(player, "\t"))
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(save_path + ".tmp", save_path)
	if error != OK:
		last_save_error = "保存失败（%d）" % error
		return false
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(save_path)) != OK:
		last_save_error = "存档格式不正确，原文件已保留"
		return false
	var data: Variant = parser.data
	if not valid_save(data):
		last_save_error = "存档格式不正确，原文件已保留"
		return false
	player = data
	if not player.has("gender"): player.gender = 0
	for key in ["signature", "title"]:
		if not player.has(key): player[key] = ""
	for key in ["ingots", "guild_contribution", "essence"]:
		if not player.has(key): player[key] = 0
	if not player.has("weapon_owned"): player.weapon_owned = true
	if not player.has("bag_order"): player.bag_order = ["potion", "sword"]
	return true

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
	var old := player
	player = data
	var values := stats()
	player = old
	return int(data.hp) <= int(values.hp) and int(data.mp) <= int(values.mp)
