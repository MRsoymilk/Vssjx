extends Node
## Local rules are newly authored. Original server formulas were not recovered.

const JOBS := ["力士", "侠客", "隐者"]
const SCHOOLS := ["峨眉", "花涧", "昆仑", "闲云野鹤"]
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
var local_gather:Dictionary={}

func begin_gathering(id:String,cell:Vector2i,map_id:String)->String:
	if storage_busy or not local_gather.is_empty():return "GATHER_BUSY"
	if is_soul():return "SOUL_STATE"
	if local_battle_active():return "BATTLE_ACTIVE"
	var node:=GatheringRules.definition(id)
	if node.is_empty() or node.map_id!=map_id or AIWorld.local_map_id()!=map_id:return "GATHER_NOT_FOUND"
	if absi(cell.x-int(node.cell[0]))+absi(cell.y-int(node.cell[1]))>1:return "GATHER_TOO_FAR"
	var data:Dictionary=player.get("gathering",{"materials":{},"respawns":{}})
	if int(data.respawns.get(id,0))>int(Time.get_unix_time_from_system()*1000):return "GATHER_COOLDOWN"
	if int(data.materials.get(node.material,0))+int(node.max_quantity)>999:return "MATERIAL_BAG_FULL"
	local_gather={"node":node.duplicate(true),"cell":cell,"map":map_id,"started":Time.get_ticks_msec(),"generation":_player_generation,"path":save_path,"quantity":randi_range(int(node.min_quantity),int(node.max_quantity))}
	return ""

func finish_gathering(cell:Vector2i,map_id:String)->PlatformResult:
	if storage_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	var pending:=local_gather.duplicate(true)
	if pending.is_empty() or pending.cell!=cell or pending.map!=map_id or AIWorld.local_map_id()!=map_id or pending.generation!=_player_generation or pending.path!=save_path or is_soul() or local_battle_active():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"GATHER_INTERRUPTED",OnlinePve.error_text("GATHER_INTERRUPTED"))
	if Time.get_ticks_msec()-int(pending.started)<int(pending.node.duration_ms):return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"GATHER_NOT_READY",OnlinePve.error_text("GATHER_NOT_READY"))
	var before:=player.duplicate(true)
	var data:Dictionary=player.get("gathering",{"materials":{},"respawns":{}}).duplicate(true)
	var material:String=pending.node.material
	if int(data.materials.get(material,0))+int(pending.quantity)>999:return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"MATERIAL_BAG_FULL",OnlinePve.error_text("MATERIAL_BAG_FULL"))
	data.materials[material]=int(data.materials.get(material,0))+int(pending.quantity)
	data.respawns[pending.node.id]=int(Time.get_unix_time_from_system()*1000)+int(pending.node.respawn_ms)
	player.gathering=data
	var result:=await save_game()
	if not result.ok:
		if pending.generation==_player_generation and pending.path==save_path:player=before
		return result
	local_gather={};return PlatformResult.success({"material":material,"quantity":pending.quantity})

func discard_gathering(material:String,quantity:int)->PlatformResult:
	if storage_busy or not GatheringRules.MATERIALS.has(material) or quantity<1 or quantity>int(player.get("gathering",{}).get("materials",{}).get(material,0)):return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"MATERIALS_INSUFFICIENT","材料数量不足或正在保存。")
	var before:=player.duplicate(true);var generation:=_player_generation;var path:=save_path
	player.gathering.materials[material]=int(player.gathering.materials[material])-quantity
	if int(player.gathering.materials[material])==0:player.gathering.materials.erase(material)
	var result:=await save_game()
	if not result.ok and generation==_player_generation and path==save_path:player=before
	return result

func craft_gathering(recipe:String,batches:int=1)->PlatformResult:
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
	if local_battle_active():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"BATTLE_ACTIVE",OnlinePve.error_text("BATTLE_ACTIVE"))
	var before:=player.duplicate(true);var generation:=_player_generation;var path:=save_path
	var error:=GatheringRules.craft_local(player,recipe,batches)
	if not error.is_empty():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,error,OnlinePve.error_text(error))
	var result:=await save_game()
	if generation!=_player_generation or path!=save_path:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STALE_PLAYER","角色已切换。")
	if not result.ok:player=before
	else:local_gather={}
	return result

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
	new_player(nickname, job, SchoolRules.UNJOINED, gender)
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
			var maxima:=stats()
			player.hp=mini(int(player.hp),int(maxima.hp))
			player.mp=mini(int(player.mp),int(maxima.mp))
			player.attribute_rules_revision=3
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

func delete_local_character(id: String, expected_name: String) -> PlatformResult:
	if _local_roster_busy or storage_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "STORAGE_BUSY", "正在处理存档，请稍候。")
	_local_roster_busy = true
	var result := await load_game()
	if not result.ok:
		_local_roster_busy = false
		return result
	var before := player.duplicate(true)
	var entries := local_character_entries()
	var index := -1
	for i in entries.size():
		if entries[i].id == id and entries[i].data.name == expected_name: index = i
	if index < 0:
		_local_roster_busy = false
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "CHARACTER_NOT_FOUND", "角色已更新，请重新选择。")
	entries.remove_at(index)
	var active := active_local_character_id()
	if entries.is_empty():
		# Keep an explicit empty roster, so legacy migration cannot restore the deleted role.
		new_player("无角色", 0, SchoolRules.UNJOINED)
		active = ""
	elif active == id:
		var next: Dictionary = entries[mini(index, entries.size() - 1)]
		player = next.data.duplicate(true)
		active = next.id
	player.local_characters = {"version": 1, "active_id": active, "characters": entries}
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
	local_gather={}
	_player_generation += 1
	last_save_receipt = {}
	player = {
		"version": SAVE_VERSION, "name": nickname.strip_edges().left(24), "gender": clampi(gender, 0, 1),
		"job": clampi(job, 0, 2), "school": clampi(school, 0, SchoolRules.UNJOINED), "school_membership_version": 1,
		"level": 1, "xp": 0, "gold": 30, "potions": 6,
		"hp": 0, "mp": 0, "quest": 0, "kills": 0,
		"equipped": false, "zone": 0, "cell": [START_CELL.x, START_CELL.y],
		"defeated": [], "enemy_respawns": {}, "signature": "", "title": "",
		"ingots": 0, "guild_contribution": 0, "essence": 0,
		"allocated_attributes": [0,0,0,0,0], "attribute_rules_revision": 3,
		"corpse":null,
		"endless_state":EndlessRules.empty(),
		"balance_revision":1,"balance_respec_available":true
	}
	if String(player.name).is_empty():
		player.name = "青衫客"
	restore()
	player.weapon_owned = true
	player.bag_order = ["potion", "sword"]
	LootRules.sync_legacy(player)

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
	for i in player.get("loot_state",{}).get("items",[]):
		if not i.legacy and not i.equipped:items.append(LootRules.bag_item(i))
	return items

func bag_buy_potion() -> bool:
	if is_soul():return false
	if int(player.gold) < 8: return false
	var gear := ShopRules.local_state(player)
	var used:=ShopRules.bag_slots(gear,int(player.potions))+LootRules.extra_bag(player.get("loot_state",{}))
	if int(player.potions)%99==0 and used>=60:return false
	player.gold = int(player.gold) - 8
	player.potions = int(player.potions) + 1
	return true

func actor_key() -> String:
	var keys := ["mzs", "mck", "mfs"] if int(player.get("gender", 0)) == 0 else ["wzs", "wck", "wfs"]
	return "hero/" + keys[int(player.get("job", 0))]

func stats() -> Dictionary:
	return ATTRIBUTE_RULES.local_stats(player)

func allocated_attributes() -> Array:
	var points: Array = player.get("allocated_attributes", [0,0,0,0,0]).duplicate()
	for i in points.size(): points[i] = int(points[i])
	return points

func attribute_profile() -> Dictionary:
	if player.get("balance_revision",0)==1:return ATTRIBUTE_RULES.profile_for(stats(),int(player.job),int(player.level),allocated_attributes())
	var value: Dictionary = ATTRIBUTE_RULES.profile(int(player.get("job",1)),int(player.get("level",1)),bool(player.get("equipped",false)),allocated_attributes())
	var gear_bonus := ShopRules.bonus(ShopRules.local_state(player))
	for key in ["physical_attack","magic_attack"]: value.combat[key] += gear_bonus.x - (5 if player.get("equipped",false) else 0)
	for key in ["physical_defense","magic_defense"]: value.combat[key] += gear_bonus.y
	return value

func appearance_key() -> String:
	return ShopRules.actor_key(int(player.get("job",0)),int(player.get("gender",0)),LootRules.look(player.get("loot_state",{}),ShopRules.appearance(ShopRules.local_state(player))))

func shop_command(action: String, id: String, count: int=1) -> PlatformResult:
	if local_battle_active():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"BATTLE_ACTIVE",OnlinePve.error_text("BATTLE_ACTIVE"))
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
	if storage_busy or _local_roster_busy: return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候")
	var before := player.duplicate(true)
	var generation := _player_generation
	var path := save_path
	var code := ShopRules.apply_local(player,action,id,count,stats())
	if not code.is_empty(): return PlatformResult.new(PlatformResult.Status.INVALID_DATA,code,OnlinePve.error_text(code))
	if action=="equip":
		for i in player.get("loot_state",{}).get("items",[]):
			if ShopRules.item(i.template).slot==ShopRules.item(id).slot:i.equipped=false
	LootRules.sync_legacy(player)
	var limits:=stats();player.hp=mini(int(player.hp),int(limits.hp));player.mp=mini(int(player.mp),int(limits.mp))
	var result := await save_game()
	if not result.ok and generation == _player_generation and path == save_path: player = before
	return result

func loot_command(action:String,id:String,count:int=1)->PlatformResult:
	if local_battle_active():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"BATTLE_ACTIVE",OnlinePve.error_text("BATTLE_ACTIVE"))
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候")
	if player.is_empty():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"EMPTY_PLAYER","没有离线角色")
	var before:=player.duplicate(true);var generation:=_player_generation;var path:=save_path
	var code:=LootRules.apply_local(player,action,id,count)
	if not code.is_empty():
		player=before
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,code,OnlinePve.error_text(code))
	var limits:=stats();player.hp=mini(int(player.hp),int(limits.hp));player.mp=mini(int(player.mp),int(limits.mp))
	var result:=await save_game()
	if not result.ok and generation==_player_generation and path==save_path:player=before
	return result

func _migrate_loot(data:Dictionary)->void:
	LootRules.sync_legacy(data)
	for entry in data.get("local_characters",{}).get("characters",[]):
		if entry.id==data.local_characters.active_id:entry.data.loot_state=data.loot_state.duplicate(true)
		else:LootRules.sync_legacy(entry.data)

var local_combat:WeakRef
func local_battle_active()->bool:
	var owner:Variant=local_combat.get_ref() if local_combat!=null else null
	if owner==null:return false
	return owner.active() if owner.has_method("active") else not owner.finished

func award_loot(enemies:Array,seed:int)->String:
	var boss:=false;var item_level:=1
	for enemy in enemies:
		boss=boss or enemy.get("kind")=="boss" or enemy.get("id")=="boss";item_level=maxi(item_level,int(enemy.get("level",1)))
	var gained:=ProgressionRules.reward(player,mini(int(player.level),item_level),boss,seed)
	return "获得%d件装备与%d炼材%s；满包自动暂存。"%[gained.size(),int(ProgressionRules.rules.boss_scrap if boss else ProgressionRules.rules.victory_scrap),"、1精华" if boss else ""]

func start_endless()->PlatformResult:
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	if player.is_empty():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"EMPTY_PLAYER","没有本地角色。")
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
	if local_battle_active():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"BATTLE_ACTIVE",OnlinePve.error_text("BATTLE_ACTIVE"))
	var point:Array=EndlessRules.rules.npc.cell
	if AIWorld.local_map_id()!=EndlessRules.rules.map_id or absi(int(player.cell[0])-int(point[0]))+absi(int(player.cell[1])-int(point[1]))>2:return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"ENDLESS_NPC_REQUIRED",OnlinePve.error_text("ENDLESS_NPC_REQUIRED"))
	if not ProgressionRules.can_fight(player.get("loot_state",{})):return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"LOOT_STORAGE_FULL",OnlinePve.error_text("LOOT_STORAGE_FULL"))
	var before:=player.duplicate(true);var generation:=_player_generation;var path:=save_path
	player.endless_state=EndlessRules.progress(player).duplicate(true)
	var started:=EndlessRules.begin(player.endless_state,int(player.level))
	if started.has("error"):player=before;return PlatformResult.new(PlatformResult.Status.INVALID_DATA,started.error,OnlinePve.error_text(started.error))
	var result:=await save_game()
	if generation!=_player_generation or path!=save_path:return PlatformResult.new(PlatformResult.Status.CANCELLED,"STALE_LOAD","角色已切换。")
	if not result.ok:player=before;return result
	return PlatformResult.success(started)


func allocate_attributes(points: Array) -> PlatformResult:
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
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
	if is_soul():return
	var values := stats()
	player.hp = values.hp
	player.mp = values.mp

func is_soul() -> bool:
	return player.get("corpse") is Dictionary

func become_soul() -> void:
	if is_soul():return
	var map_id:=AIWorld.local_map_id()
	player.corpse=SoulRules.create(map_id,Vector2i(player.cell[0],player.cell[1]))
	player.hp=0;player.mp=0
	var spawn:=SoulRules.resurrection_point(map_id)
	player.cell=[spawn.x,spawn.y]

func recover_corpse(id: String, cell: Vector2i) -> PlatformResult:
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	if not is_soul() or player.corpse.id!=id:return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"CORPSE_NOT_FOUND",OnlinePve.error_text("CORPSE_NOT_FOUND"))
	if cell!=Vector2i(player.cell[0],player.cell[1]) or not SoulRules.nearby(player.corpse,AIWorld.local_map_id(),cell):return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"CORPSE_TOO_FAR",OnlinePve.error_text("CORPSE_TOO_FAR"))
	var before:=player.duplicate(true)
	var generation:=_player_generation
	var path:=save_path
	player.corpse=null
	restore()
	var result:=await save_game()
	if not result.ok and generation==_player_generation and path==save_path:player=before
	return result

func join_local_school(school: int) -> PlatformResult:
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	if school<0 or school>2:return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_SCHOOL","请选择有效门派。")
	if int(player.get("school",SchoolRules.UNJOINED))!=SchoolRules.UNJOINED:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SCHOOL_ALREADY_JOINED","已加入门派，不能重复入派。")
	var destination:=SharedWorldMap.load_data(SchoolRules.map_id(school))
	if destination.is_empty():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_SCHOOL","门派地图暂不可用，请重试。")
	var before:=player.duplicate(true)
	var generation:=_player_generation
	var path:=save_path
	player.school=school;player.school_membership_version=1
	player.ai_map=SchoolRules.map_id(school);player.zone=0;player.cell=destination.spawn.duplicate();player.hunt_pressure={}
	var result:=await save_game()
	if not result.ok and generation==_player_generation and path==save_path:player=before
	return result

func _migrate_school_membership(data: Dictionary) -> void:
	if not data.has("school_membership_version"):
		data.school=SchoolRules.UNJOINED
		data.school_membership_version=1
	for entry in data.get("local_characters",{}).get("characters",[]):
		_migrate_school_membership(entry.data)

func _migrate_balance(data:Dictionary)->void:
	if data.get("balance_revision",0)==0:
		var a:Array=data.get("allocated_attributes",[0,0,0,0,0])
		var old:=ATTRIBUTE_RULES.stats(int(data.job),int(data.level),bool(data.equipped),a)
		var next:=ATTRIBUTE_RULES.balanced_stats(int(data.job),int(data.level),bool(data.equipped),a)
		var bonus:=ShopRules.bonus(ShopRules.local_state(data))
		ATTRIBUTE_RULES.gear_bonus(old,bonus.x-(5 if data.equipped else 0),bonus.y)
		ATTRIBUTE_RULES.gear_bonus(next,bonus.x-(5 if data.equipped else 0),bonus.y)
		if data.get("corpse")==null:data.hp=clampi(int(data.hp)*int(next.hp)/int(old.hp),1,int(next.hp))
		data.mp=clampi(int(data.mp)*int(next.mp)/int(old.mp),0,int(next.mp))
		data.balance_revision=1;data.balance_respec_available=true
	for entry in data.get("local_characters",{}).get("characters",[]):_migrate_balance(entry.data)

func respec_attributes()->PlatformResult:
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存")
	if is_soul() or not player.get("balance_respec_available",false):return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"RESPEC_USED","灵魂状态不能重置，或免费次数已用完。")
	var before:=player.duplicate(true);var previous:=stats();var generation:=_player_generation;var path:=save_path
	player.allocated_attributes=[0,0,0,0,0];player.balance_respec_available=false
	var next:=stats()
	player.hp=clampi(int(player.hp)*int(next.hp)/int(previous.hp),1,int(next.hp));player.mp=clampi(int(player.mp)*int(next.mp)/int(previous.mp),0,int(next.mp))
	var result:=await save_game()
	if not result.ok and generation==_player_generation and path==save_path:player=before
	return result

## Persist before entering an actual local encounter; a failed write cannot count a fight.
func record_local_hunt(map_id:String,species:String)->PlatformResult:
	if storage_busy or _local_roster_busy:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	var before:=player.duplicate(true)
	var generation:=_player_generation
	var path:=save_path
	player.hunt_pressure=MonsterCombat.note_pressure(player.get("hunt_pressure",{}),map_id,species)
	var elite:=int(player.hunt_pressure.count)==int(MonsterCombat.rules.hunt_threshold)
	var result:=await save_game()
	if not result.ok:
		if generation==_player_generation and path==save_path:player=before
		return result
	if generation!=_player_generation or path!=save_path:return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STALE_PLAYER","角色已切换。")
	return PlatformResult.success({"elite":elite})

## Offline test helper. Only LocalWorldChat exposes this; no network protocol hook.
func set_local_test_level(level: int) -> PlatformResult:
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
	if storage_busy or _local_roster_busy:
		return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	if player.is_empty() or level < 1 or level > 60:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_TEST_LEVEL","本地测试等级范围为1～60。")
	var before := player.duplicate(true)
	var high:Array=player.get("loot_state",{}).get("items",[]).filter(func(i:Dictionary)->bool:return i.equipped and int(i.level)>level)
	if ShopRules.bag_slots(ShopRules.local_state(player),int(player.potions))+LootRules.extra_bag(player.get("loot_state",{}))+high.size()>60:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"BAG_FULL","降级需先卸下高物等装备，请清理背包后重试。")
	for i in high:i.equipped=false
	var generation := _player_generation
	var path := save_path
	player.level = level
	player.xp = 0
	var reset_points := not ATTRIBUTE_RULES.valid_points(allocated_attributes(),level)
	if reset_points: player.allocated_attributes = [0,0,0,0,0]
	restore()
	var result := await save_game()
	if not result.ok:
		if generation == _player_generation and path == save_path: player = before
		return result
	return PlatformResult.success({"level":level,"reset_attributes":reset_points})

## Local-only debug controls: HP is absolute; money is an additive positive amount.
func set_local_test_value(kind: String, value: int) -> PlatformResult:
	if storage_busy or _local_roster_busy:
		return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"STORAGE_BUSY","正在保存，请稍候。")
	if player.is_empty() or kind not in ["hp","money"]:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_LOCAL_CONTROL","没有可修改的本地角色。")
	if is_soul():return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"SOUL_STATE",OnlinePve.error_text("SOUL_STATE"))
	if kind=="hp" and (value<1 or value>int(stats().hp)):
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_TEST_HP","血量必须为1～%d。"%int(stats().hp))
	if kind=="money" and (value<1 or value>1000000000 or int(player.gold)>1000000000-value):
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA,"INVALID_TEST_MONEY","增加的铜币必须为正整数，增加后总额不能超过1000000000。")
	var before:=player.duplicate(true)
	var generation:=_player_generation
	var path:=save_path
	if kind=="hp":player.hp=value
	else:player.gold=int(player.gold)+value
	var result:=await save_game()
	if not result.ok and generation==_player_generation and path==save_path:player=before
	return result

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
	if is_soul():return SoulRules.hint(player.corpse)
	if not AIWorld.map_data(AIWorld.local_map_id()).is_empty(): return AIWorld.quest_hint(AIWorld.local_map_id(),AIWorld.progress(),int(player.level))
	match int(player.get("quest", 0)):
		0: return "拜访石桥旁的清微道人"
		1: return "山林试炼：击败山狼 %d / 3" % int(player.kills)
		2: return "试炼完成，返回清微道人处"
		3: return "穿过东侧灵门，击败遗迹妖王"
		_: return "蜀山初行已完成 · 自由探索"

func enemy_respawn_remaining(id: String, now: float = -1.0) -> float:
	if now < 0.0: now = Time.get_unix_time_from_system()
	if not AIWorld.resident(id).is_empty(): return maxf(0.0, float(AIWorld.progress().respawns.get(id, 0)) / 1000.0 - now)
	return maxf(0.0, float(player.get("enemy_respawns", {}).get(id, 0.0)) - now)

func enemy_available(id: String, now: float = -1.0) -> bool:
	# Defeated is quest history, not the current world population. Missing
	# deadlines in legacy saves allow those monsters to return immediately.
	return enemy_respawn_remaining(id, now) <= 0.0

func finish_enemy(enemy: Dictionary) -> bool:
	var id := String(enemy.id)
	if not AIWorld.resident(id).is_empty():
		var state := AIWorld.progress()
		for previous in state.respawns.keys():
			if float(state.respawns[previous]) <= Time.get_unix_time_from_system()*1000: state.respawns.erase(previous)
		state.respawns[id] = int((Time.get_unix_time_from_system() + ENEMY_RESPAWN_SECONDS) * 1000)
		AIWorld.event("kill", id)
		return add_rewards(int(enemy.gold), int(enemy.xp))
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
	LootRules.sync_legacy(player)
	var supply_before:={"hp":player.hp,"mp":player.mp,"gourds":player.get("gourds",{}).duplicate(true)}
	var supplied:=GourdRules.supply(player,stats(),local_battle_active())
	var payload := _save_payload()
	var result := await _await_storage(Platform.context.storage.write(_operation_path, JSON.stringify(payload, "\t")))
	if result.ok:
		if not result.value is Dictionary or result.value.get("written") != true or result.value.get("durability") not in ["native_file", "browser_sync"]:
			result = PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "SAVE_UNCONFIRMED", "存档持久化未确认，请重试；当前进度仍在内存中。")
		elif generation == _player_generation and _operation_path == save_path:
			last_save_receipt = result.value.duplicate(true)
			if payload.has("local_characters"): player.local_characters = payload.local_characters
	if not result.ok and supplied and generation==_player_generation and _operation_path==save_path:
		player.hp=supply_before.hp;player.mp=supply_before.mp;player.gourds=supply_before.gourds
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
	_migrate_school_membership(data)
	_migrate_balance(data)
	var interrupted_endless:=EndlessRules.recover_local(data)
	var supplied:=GourdRules.supply(data,ATTRIBUTE_RULES.local_stats(data),false)
	var loot_migration:bool=supplied or interrupted_endless or not data.has("loot_state") or data.get("local_characters",{}).get("characters",[]).any(func(e:Dictionary)->bool:return not e.data.has("loot_state"))
	if loot_migration:
		_migrate_loot(data)
		if supplied and data.has("local_characters"):
			var current:Dictionary=data.duplicate(true);current.erase("local_characters")
			for entry in data.local_characters.characters:
				if entry.id==data.local_characters.active_id:entry.data=current
		var migrated:=await _await_storage(Platform.context.storage.write(_operation_path,JSON.stringify(data,"\t")))
		if not migrated.ok:return _finish_storage(migrated,generation)
		if not migrated.value is Dictionary or migrated.value.get("written")!=true or migrated.value.get("durability") not in ["native_file","browser_sync"]:
			return _finish_storage(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SAVE_UNCONFIRMED","试炼中断记录尚未确认保存，请重试。" if interrupted_endless else "装备迁移尚未确认保存，请重试。"),generation)
		if generation!=_player_generation or epoch!=_load_epoch or _operation_path!=save_path:return _finish_storage(PlatformResult.new(PlatformResult.Status.CANCELLED,"STALE_LOAD","角色已切换。"),generation)
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
	var maxima:=stats()
	player.hp=mini(int(player.hp),int(maxima.hp))
	player.mp=mini(int(player.mp),int(maxima.mp))
	player.attribute_rules_revision=3
	_player_generation += 1
	result = _finish_storage(PlatformResult.success(), _player_generation)
	return result

func _invalid_save() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_SAVE", "存档格式不正确，原文件已保留")

func valid_save(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if not ShopRules._integer(data.get("balance_revision",0),0,1) or not data.get("balance_respec_available",true) is bool:return false
	if data.has("endless_state") and not EndlessRules.valid(data.endless_state):return false
	if data.has("gathering") and not GatheringRules.valid_local(data.gathering):return false
	if data.has("ai_map") and (not data.ai_map is String or (not data.ai_map.is_empty() and AIWorld.map_data(data.ai_map).is_empty())): return false
	if data.has("ai_progress") and not AIWorld.valid_progress(data.ai_progress): return false
	if data.get("corpse")!=null:
		if not SoulRules.valid_corpse(data.corpse) or data.get("hp")!=0:return false
		var current_map:String=data.get("ai_map","")
		if current_map.is_empty():current_map="qingyun_trail" if data.get("zone")==0 else "ancient_ruins"
		if data.corpse.map_id!=current_map:return false
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
	if not GourdRules.valid(data.get("gourds",{}),ShopRules.local_state(data)):return false
	if data.has("shop_owned") and (not data.shop_owned is Array or data.shop_owned.has("sword")): return false
	if data.has("shop_weapon") and bool(data.equipped) != (data.shop_weapon != null): return false
	var local_gear := ShopRules.local_state(data)
	for slot in ["weapon","armor"]:
		if data.get("shop_slots",{}).has(slot) and data.shop_slots[slot]!=local_gear[slot]: return false
	for id in data.get("shop_quantities",{}):
		if not local_gear.owned.has(id) or not ShopRules._integer(data.shop_quantities[id],1,1 if ShopRules.unique(ShopRules.item(id)) else 99): return false
	for slot in ShopRules.SLOTS:
		var id: Variant = ShopRules.equipped_id(local_gear,slot)
		if id!=null and not ShopRules.equipment_error(ShopRules.item(id),int(data.job),int(data.get("gender",0))).is_empty(): return false
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
	if int(data.job) > 2 or int(data.school) > SchoolRules.UNJOINED or int(data.zone) > 1: return false
	if data.has("school_membership_version") and data.school_membership_version!=1:return false
	if int(data.quest) > 4 or int(data.kills) > 3: return false
	if int(data.level) < 1 or int(data.level) > 60: return false
	if not ATTRIBUTE_RULES.valid_points(data.get("allocated_attributes",[0,0,0,0,0]),int(data.level)): return false
	if data.has("loot_state"):
		if not LootRules.valid(data.loot_state,int(data.job),int(gender)) or not LootRules.consistent(data.loot_state,local_gear,int(data.job),int(gender)):return false
		for i in data.loot_state.items:
			if i.equipped and int(i.level)>int(data.level):return false
	if not data.cell is Array or data.cell.size() != 2: return false
	for value in data.cell:
		if not (value is float or value is int) or not is_finite(float(value)): return false
		if float(value) != floor(float(value)) or value < 1 or value > 30: return false
	if not data.defeated is Array or data.defeated.size() > 20: return false
	for value in data.defeated:
		if not value is String: return false
	if not MonsterCombat.pressure_valid(data.get("hunt_pressure",{})):return false
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
	var revision:Variant=data.get("attribute_rules_revision",1)
	if not (revision is int or revision is float) or not is_finite(float(revision)) or float(revision)!=floor(float(revision)) or revision<1 or revision>3:return false
	var max_hp:=int(values.hp);var max_mp:=int(values.mp)
	if revision==1:
		var a:Array=data.get("allocated_attributes",[0,0,0,0,0])
		max_hp=maxi(max_hp,max_hp+2*int(a[2]))
		max_mp=maxi(max_mp,max_mp-int(a[0])-int(a[2])+2*int(a[4]))
	return int(data.hp)<=max_hp and int(data.mp)<=max_mp

func _valid_local_roster(data: Dictionary) -> bool:
	var roster: Variant = data.local_characters
	if not roster is Dictionary or roster.get("version") != 1 or not roster.get("active_id") is String or not roster.get("characters") is Array: return false
	if roster.characters.size() > MAX_LOCAL_CHARACTERS: return false
	if roster.characters.is_empty(): return roster.active_id.is_empty()
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
