extends RefCounted
## Read-only adapters over the same definitions used by the game. Never load saves.

const STATE := preload("res://scripts/game_state.gd")
const WORLD := preload("res://scripts/world.gd")
const INVENTORY := preload("res://scripts/inventory.gd")
const ART := preload("res://scripts/art.gd")
const APPEARANCE := preload("res://scripts/admin/equipment_appearance.gd")
const ONLINE_MAP := "res://assets/data/qingyun-v1.json"
const ORIGINAL_ITEMS := "res://assets/data/original_items.json"
const ORIGINAL_WORLD := "res://assets/data/original_world.json"
const ORIGINAL_MONSTERS := "res://assets/admin/monsters/catalog.json"
const MONSTER_AUDIT := "res://assets/admin/monsters/animation_audit.json"
const ORIGINAL_EFFECTS := "res://assets/admin/effects/catalog.json"
const RESOURCE_ARCHIVE := "res://assets/admin/archive/catalog.json"
const CATEGORIES := [
	["weapons", "武器"], ["equipment", "人物装备"], ["appearance", "装备外观"], ["items", "物品"],
	["characters", "人物"], ["quests", "任务 / 线索"], ["maps", "地图"],
	["enemies", "怪物"], ["skills", "技能 / 升级阶段"], ["effects", "特效"], ["audio", "音频"], ["art", "素材 / 动画"], ["archive", "原包归档"]
]
var entries: Array[Dictionary] = []
var errors: Array[String] = []
var original_map_names := 0
var original_distinct_map_names := 0
var original_overview: Dictionary = {}

func reload() -> void:
	entries.clear()
	errors.clear()
	original_map_names = 0
	original_distinct_map_names = 0
	original_overview = {}
	# An unattached state instance evaluates pure rules; the Game autoload is untouched.
	var state := STATE.new()
	state.player = {"potions": 1, "equipped": false, "weapon_owned": true}
	for item in state.bag_items():
		var data: Dictionary = item.duplicate(true)
		data.erase("count")
		data["堆叠上限"] = 99 if item.id == "potion" else 1
		data["类型"] = "消耗品" if item.id == "potion" else "武器"
		if item.id == "sword":
			state.player = {"job": 1, "level": 1, "equipped": false}
			var base: Dictionary = state.stats()
			state.player.equipped = true
			data["攻击加成"] = state.stats().attack - base.attack
		_add("items", item.id, item.name, data["类型"], "已接入", "res://scripts/game_state.gd", data, {"kind": "icon", "path": item.icon})
		if item.id == "sword":
			_add("weapons", item.id, item.name, "攻击 +%s" % data["攻击加成"], "已接入", "res://scripts/game_state.gd", data, {"kind": "icon", "path": item.icon})
	for entry in ShopRules.catalog.items:
		if entry.id in ["potion","sword"]: continue
		var category: String = "weapons" if entry.slot == "weapon" else ("equipment" if ShopRules.is_equipment(entry) else "items")
		var record: Dictionary = entry.duplicate(true)
		record["规则来源"] = ShopRules.catalog.provenance
		record["部件说明"] = entry.get("appearance_basis","武器按职业替换 e{zs,ck,fs} 部件；衣服与头饰对应为可调整重建规则。") if ShopRules.is_equipment(entry) else "非换装物品"
		var icon := {"kind":"icon","path":entry.icon}
		var record_id:String="shop/"+entry.id if String(entry.id).begins_with("original/") else entry.id
		var status := "AI生成" if entry.get("art_source") == "AI生成" else "重建商店"
		_add("items",record_id,entry.name,ShopRules.description(entry.id),status,"res://assets/data/shop-v2.json",record,icon)
		if category!="items":_add(category,record_id,entry.name,ShopRules.description(entry.id),status,"res://assets/data/shop-v2.json",record,icon)
	_load_original_items()
	for index in INVENTORY.EQUIPMENT.size():
		var slot: String = INVENTORY.EQUIPMENT[index]
		var ids: Array = ShopRules.catalog.items.filter(func(item:Dictionary)->bool:return item.slot==ShopRules.SLOTS[index]).map(func(item:Dictionary)->String:return item.id)
		var data := {"槽位序号":index,"槽位":slot,"可装备物品":ids,"说明":"各槽提供重建属性；武器、衣服、帽子参与换装，部分对应仍为重建规则" if not ids.is_empty() else "界面预留槽位，尚无物品及属性规则"}
		_add("equipment","slot_%d" % index,slot," / ".join(PackedStringArray(ids)) if not ids.is_empty() else "尚无装备定义","已接入" if not ids.is_empty() else "预留","res://scripts/inventory.gd",data)
	for entry in ShopRules.catalog.items:
		if not ShopRules.is_equipment(entry): continue
		var mapping := APPEARANCE.describe(entry)
		_add("appearance", entry.id, entry.name, APPEARANCE.changes(entry), "AI生成" if entry.get("art_source") == "AI生成" else "已接入", "res://assets/data/shop-v2.json", mapping, {"kind":"icon", "path":entry.icon, "equipment_id":entry.id})
		for record in entries:
			if record.category in ["weapons", "equipment", "items"] and (record.id == entry.id or record.id == "shop/"+entry.id):
				record.data["外观对应"] = mapping
				record.preview["equipment_id"] = entry.id
	var hero_keys := [["mzs", "mck", "mfs"], ["wzs", "wck", "wfs"]]
	for gender in 2:
		for job in STATE.JOBS.size():
			state.player = {"job": job, "gender": gender, "level": 1, "equipped": false}
			var key: String = "hero/" + hero_keys[gender][job]
			var data := {"职业": STATE.JOBS[job], "性别": "男" if gender == 0 else "女", "可选门派": STATE.SCHOOLS, "一级基础属性（未装备）": state.stats(), "动画资源": key}
			state.player.level = 2
			data["二级基础属性（未装备）"] = state.stats()
			_add("characters", hero_keys[gender][job], "%s · %s" % [STATE.JOBS[job], data["性别"]], "一级气血 %s / 攻击 %s" % [data["一级基础属性（未装备）"].hp, data["一级基础属性（未装备）"].attack], "已接入", "res://scripts/game_state.gd", data, {"kind": "actor", "art": key})
	for stage in 5:
		state.player = {"quest": stage, "kills": 0}
		var text: String = state.quest_text()
		var data := {"类型": "重建任务阶段", "任务链": "蜀山初行", "阶段": stage, "目标文本（零进度）": text, "下一阶段": stage + 1 if stage < 4 else null, "说明": "一条重建任务链的五个状态之一，不是原版独立任务定义，也不代表当前玩家进度"}
		if stage == 1:
			state.player.kills = 3
			data["目标文本（完成计数）"] = state.quest_text()
		_add("quests", "shushan_%d" % stage, "蜀山初行 · 阶段 %d" % stage, text, "重建阶段", "res://scripts/game_state.gd", data)
	state.free()
	for enemy in WORLD.ENEMIES:
		var data: Dictionary = enemy.duplicate(true)
		data["区域"] = "古剑遗迹" if enemy.id in ["guardian", "boss"] else "青云山道"
		_add("enemies", enemy.id, enemy.name, "气血 %s / 攻击 %s / %s" % [enemy.hp, enemy.attack, data["区域"]], "已接入", "res://scripts/world.gd", data, {"kind": "actor", "art": enemy.art})
	_load_original_monsters()
	_load_original_effects()
	_load_skills()
	_load_audio()
	_load_resource_archive()
	_load_maps()
	_load_original_world()
	_load_ai_world()
	for key in ART.actor_keys():
		var info := ART.actor_info(key)
		if info.is_empty(): continue
		_add("art", key, key, "Godot场景 · %s 帧 · %s × %s" % [info.get("count", 0), info.get("width", 0), info.get("height", 0)], "资源", ART.scene_path(key), info, {"kind": "actor", "art": key})

func _skill_usages() -> Dictionary:
	var usages:Dictionary={}
	for skill in SkillRules.catalog.items:
		var binding:=BattleEffects.binding(skill.id)
		var groups:Array=[{"level":1,"layers":binding.get("layers",[])}]+binding.get("stages",[])
		for group in groups:
			var rank:=int(group.level)
			for layer in group.layers:
				var key:String=layer.art
				if not usages.has(key):usages[key]=[]
				usages[key].append({"技能":skill.name,"技能ID":skill.id,"职业":STATE.JOBS[int(skill.job)],"阶段":SkillProficiency.stage(rank),"技能等级":rank,"附着":layer.anchor})
	return usages

func _load_skills() -> void:
	for skill in SkillRules.catalog.items:
		var binding:=BattleEffects.binding(skill.id)
		var groups:Array=[{"level":1,"layers":binding.get("layers",[])}]+binding.get("stages",[])
		for group in groups:
			var rank:=int(group.level)
			var stage:=SkillProficiency.stage(rank)
			var label:String="基础 · 1～5级" if stage==0 and groups.size()>1 else "基础 · 沿用" if stage==0 else "阶段%d · %d%s"%[stage,rank,"级" if rank==15 else "～9级" if rank==6 else "～14级"]
			var resources:Array=[]
			for layer in group.layers:resources.append(String(layer.art).trim_prefix("effect/"))
			var data:Dictionary=skill.duplicate(true)
			data["阶段"]=stage;data["阶段起始技能等级"]=rank
			data["最大技能等级"]=15;data["每级熟练度"]=int(SkillProficiency.rules.casts_per_level)
			data["原包资源"]=resources;data["特效图层"]=group.layers.duplicate(true)
			data["对应依据"]=binding.get("stage_basis",binding.get("basis",""))
			var preview:Dictionary={"kind":"actor","art":group.layers[0].art} if not group.layers.is_empty() else {}
			_add("skills",String(skill.id)+"/stage_"+str(stage),skill.name+" · "+label,"%s · 角色%d级解锁 · %s"%[STATE.JOBS[int(skill.job)],int(skill.unlock_level)," → ".join(PackedStringArray(resources))],"已接入","res://assets/data/skill-effects-v1.json",data,preview)

func _load_audio() -> void:
	for entry in GameAudio.catalog.items:
		var stream:=GameAudio.stream(entry.id)
		var data:Dictionary=entry.duplicate(true)
		data["时长（秒）"]=stream.get_length() if stream!=null else 0
		data["文件大小（字节）"]=FileAccess.get_file_as_bytes(entry.path).size()
		if stream is AudioStreamWAV:
			data["采样率"]=stream.mix_rate
			data["声道"]="双声道" if stream.stereo else "单声道"
			data["WAV编码"]="16位PCM" if stream.format==AudioStreamWAV.FORMAT_16_BITS else ("8位PCM" if stream.format==AudioStreamWAV.FORMAT_8_BITS else "压缩WAV")
		elif stream is AudioStreamOggVorbis:
			data["编码"]="Ogg Vorbis"
			data["试听循环"]=stream.loop
		var binding:String="背景音乐 · 游戏内循环" if entry.trigger=="game_background" else "%s · %s"%[entry.skill_id,entry.trigger]
		_add("audio",entry.id,entry.name,"%.2f秒 · %s"%[data["时长（秒）"],binding],"已接入",entry.path,data,{"kind":"audio","audio_id":entry.id})

func _load_ai_world() -> void:
	AIWorld.prepare()
	for id in AIWorld.maps:
		var m: Dictionary = AIWorld.maps[id]
		_add("maps",id,m.name + " · #%03d" % int(m.original_map_id),"%s · %d～%d级 · 3个任务" % [m.layout_name,int(m.level_min),int(m.level_max)],"AI生成",AIWorld.PATH,m,{"kind":"map"})
		for q in m.quests: _add("quests",q.id,q.name,q.description,"AI生成",AIWorld.PATH,q)
		for r in m.residents: _add("characters" if r.kind=="npc" else "enemies",r.id,r.name,m.name + " · AI生成布置","AI生成",AIWorld.PATH,r,{"kind":"actor","art":r.art})

func _load_original_monsters() -> void:
	var manifest := _read_json(ORIGINAL_MONSTERS)
	if manifest.get("format_version") != 1 or manifest.get("source_package") != "ssjx/monster.mrp" or not manifest.get("monsters") is Array:
		errors.append("原包怪物目录身份或格式不正确")
		return
	if manifest.monsters.size() != int(manifest.get("animation_count", -1)):
		errors.append("原包怪物动画数量不匹配")
		return
	var audit := _read_json(MONSTER_AUDIT)
	var audits: Dictionary = {}
	if audit.get("format_version") == 1 and audit.get("source_package") == manifest.source_package and audit.get("source_sha256") == manifest.source_sha256 and audit.get("monsters") is Array:
		for row in audit.monsters:
			audits[row.resource_id] = row
	if audits.size() != manifest.monsters.size():
		errors.append("怪物动画检查报告缺失或与原包不匹配")
	for record in manifest.monsters:
		var info: Dictionary = record.animation
		if not FileAccess.file_exists(info.texture):
			errors.append("原包怪物图集缺失：" + record.resource_id)
			continue
		var data := {
			"资源编号": record.resource_id, "原版名称": null, "原版怪物ID": null,
			"原版等级": null, "原版属性": null,
			"恢复范围": "原包怪物目录中的动画素材；不等于已恢复怪物定义，名称与数值未知",
			"动画说明": "source_N 对应原始序列编号；未推断待机、行走或攻击语义",
			"来源资源": record.duplicate(true), "原包SHA256": manifest.source_sha256
		}
		if audits.has(record.resource_id):
			var review: Dictionary = audits[record.resource_id]
			data["动画检查"] = {
				"结构检查": "通过" if review.structural_errors.is_empty() else review.structural_errors,
				"接入状态": "运行时已修正：循环动作清除战斗特效，攻击与受击使用独立帧" if review.runtime_status == "corrected" else "已检查原始资源；动作语义未确认，尚未接入游戏",
				"受击方式": "原客户端状态6及对应原始受击序列（已按倒序表解释）" if review.runtime_status == "corrected" else "未指定",
				"含星形层的原始帧": review.impact_layer_frames,
				"含方向变化的原始序列": review.mixed_landmark_sequences,
				"含横向位移的原始序列": review.root_travel_sequences,
				"说明": "以上是原始图层观测，不等于异常或动作结论；攻击弹道、刀光等保留。source_N 预览保持原包数据。",
				"逐序列检查": review.sequences,
				"报告": MONSTER_AUDIT,
			}
		else:
			errors.append("怪物动画检查条目缺失：" + record.resource_id)
		_add("enemies", record.id, record.display_name,
			"%d 帧 · %d 组原始序列 · 名称 / 数值未恢复" % [int(info.count), info.sequences.size()],
			"原包资源", ORIGINAL_MONSTERS, data, {"kind": "original_animation", "animation": info})

func _load_resource_archive() -> void:
	var manifest := _read_json(RESOURCE_ARCHIVE)
	if manifest.get("format_version") != 1 or not manifest.get("records") is Array or manifest.records.size() != int(manifest.get("record_count", -1)):
		errors.append("原包归档格式或数量不正确")
		return
	for record in manifest.records:
		var preview: Dictionary = record.preview.duplicate(true)
		if preview.kind == "unavailable":
			preview["message"] = record.status + "\n\n" + record.reason + "\n\n原始条目已归档，可查看来源、大小、SHA256与原始字节摘要"
		var data := {
			"原始资源路径": record.resource_path, "解析状态": record.status, "说明": record.reason,
			"原始大小（字节）": int(record.size) if record.size != null else null, "SHA256": record.sha256,
			"原始文件": record.source_file, "来源包": record.source_package,
			"原始目录记录": record.member, "原始前128字节（十六进制）": record.hex_prefix,
			"解析数据": record.parsed
		}
		var excerpts: Array[String] = []
		for group in record.parsed.get("text_groups", []):
			for text in group: excerpts.append(String(text))
		for fragment in record.parsed.get("text_fragments", []): excerpts.append(String(fragment.text))
		if not excerpts.is_empty(): data["文本摘录"] = excerpts
		var bytes_text := str(int(record.size)) if record.size != null else "缺失"
		_add("archive", record.id, record.resource_path, "%s · %s 字节 · %s" % [record.status, bytes_text, record.reason], record.status, RESOURCE_ARCHIVE, data, preview)

func _load_original_effects() -> void:
	var usages:=_skill_usages()
	var manifest := _read_json(ORIGINAL_EFFECTS)
	if manifest.get("format_version") != 1 or manifest.get("source_package") != "ssjx/effect.mrp" or not manifest.get("effects") is Array:
		errors.append("原包特效目录身份或格式不正确")
		return
	if manifest.effects.size() != int(manifest.get("animation_count", -1)):
		errors.append("原包特效动画数量不匹配")
		return
	for record in manifest.effects:
		var info: Dictionary = record.animation
		if not ResourceLoader.exists(info.texture,"Texture2D"):
			errors.append("原包特效图集缺失：" + record.resource_id)
			continue
		var data := {
			"资源编号": record.resource_id, "原版名称": null, "原版特效ID": null, "原服技能对应关系": null,
			"当前项目技能对应关系":usages.get("effect/"+String(record.resource_id),[]),
			"恢复范围": "原包特效动画素材；名称、技能对应关系与业务规则尚未恢复",
			"动画说明": "source_N 对应原始序列编号；原始帧索引与时长完整保留",
			"来源资源": record.duplicate(true), "原包SHA256": manifest.source_sha256
		}
		_add("effects", record.id, record.display_name,
			"%d 帧 · %d 组原始序列 · 项目技能对应%d处" % [int(info.count), info.sequences.size(),usages.get("effect/"+String(record.resource_id),[]).size()],
			"原包资源", ORIGINAL_EFFECTS, data, {"kind": "original_animation", "animation": info})

func _load_original_world() -> void:
	var manifest := _read_json(ORIGINAL_WORLD)
	if manifest.get("format_version") != 1 or manifest.get("source_package", {}).get("appid") != 403084:
		errors.append("原包世界目录身份或格式不正确")
		return
	var maps: Dictionary = manifest.get("maps", {})
	var records: Array = maps.get("records", [])
	if records.size() != int(maps.get("record_count", -1)):
		errors.append("原包地图目录数量不匹配")
		return
	original_map_names = records.size()
	original_distinct_map_names = int(maps.get("distinct_name_count", 0))
	original_overview = maps.get("world_overview", {})
	for record in records:
		var position_text := "原包隐藏位置" if record.world_position == null else "坐标 [%d, %d]" % [int(record.world_position[0]), int(record.world_position[1])]
		var data := {
			"目录编号": record.directory_number, "原包地图名称": record.name,
			"原包地图编号": record.original_map_id, "世界总图坐标（列x、行y）": record.world_position,
			"地点类型": record.location_type, "等级下限": record.level_min, "等级上限": record.level_max,
			"恢复范围": "世界总图已恢复；单张场景地形缺少对应.map文件",
			"服务器地图ID": null, "场景地形": null, "NPC与任务配置": null,
			"原始记录": record.duplicate(true),
			"来源成员": maps.source_member, "成员SHA256": maps.source_sha256,
			"来源身份": manifest.source_package
		}
		_add("maps", "original/map_%03d" % int(record.directory_number), record.name,
			"%s · 等级 %d～%d · %s\n世界总图已恢复，场景地形缺失" % [record.location_type, int(record.level_min), int(record.level_max), position_text],
			"原包目录", ORIGINAL_WORLD, data,
			{"kind": "world_overview", "world": original_overview, "selected_map_id": record.original_map_id})
	for evidence in manifest.get("quests", {}).get("evidence", []):
		var is_ui: bool = evidence.kind == "ui"
		var excerpts: Array[String] = []
		for group in evidence.get("text_groups", []):
			for value in group: excerpts.append(String(value))
		for fragment in evidence.get("text_fragments", []): excerpts.append(String(fragment.text))
		var data := {
			"类型": "任务界面文案" if is_ui else "引导文案 / 文本线索",
			"恢复范围": "原包文本证据，不能作为完整任务定义",
			"原版任务总数": null, "完整任务定义": false,
			"文本摘录": excerpts,
			"原始资料": evidence.duplicate(true), "来源身份": manifest.source_package
		}
		_add("quests", "original/" + String(evidence.source_member), evidence.title,
			"原版任务总数未知 · 此项为%s" % ("界面文案" if is_ui else "引导线索"),
			"原包文案" if is_ui else "原包线索", ORIGINAL_WORLD, data,
			{"kind": "unavailable", "message": "原包%s\n\n查看下方「文本摘录」\n完整任务定义尚未恢复" % ("任务界面文案" if is_ui else "游戏引导线索")})

func _load_original_items() -> void:
	var manifest := _read_json(ORIGINAL_ITEMS)
	if manifest.get("format_version") != 1 or not manifest.get("items") is Array:
		errors.append("原包物品索引格式不正确")
		return
	for item in manifest.items:
		if not item is Dictionary or not item.get("icon") is String or not FileAccess.file_exists(item.icon):
			errors.append("原包物品图标缺失")
			continue
		var data := {
			"原始资源编号": item.resource_id,
			"原版物品ID": null, "原版名称": null, "原版等级": null,
			"原版属性": null, "装备槽位对应": null,
			"说明": "已恢复原始图标，名称、等级、属性与物品ID映射尚未恢复",
			"分类依据": item.classification_basis,
			"资源记录": item.duplicate(true)
		}
		var summary := "%d × %d 像素 · 原版名称 / 数值未恢复" % [int(item.width), int(item.height)]
		var preview := {"kind": "icon", "path": item.icon}
		var product := ShopRules.item(item.id)
		var confirmation: Dictionary = product.get("original_confirmation", {})
		if not confirmation.is_empty():
			data["原版名称"] = confirmation.name
			var recovery: Dictionary = {}
			var parts: Array[String] = []
			for field in ["restore_hp", "restore_mp"]:
				if confirmation.has(field):
					var label := "气血" if field=="restore_hp" else "灵力"
					recovery["恢复"+label] = int(confirmation[field])
					parts.append("恢复%d点%s" % [int(confirmation[field]), label])
			data["原版属性"] = recovery
			data["确认依据"] = confirmation.source
			data["说明"] = "名称与恢复量由用户确认；原版等级、业务物品ID及其余属性未知"
			if confirmation.has("level"):
				data["原版等级"] = int(confirmation.level)
				data["说明"] = "名称、等级与恢复量由用户截图确认；原版业务物品ID及其余属性未知"
			summary = "%d × %d 像素 · 用户确认原版名称与%s" % [int(item.width), int(item.height), " / ".join(parts)]
		data["商城接入"] = "未接入" if product.is_empty() else "已接入"
		if not product.is_empty():
			var sections: Array = ShopRules.catalog.tabs.filter(func(tab: Array) -> bool: return product.sections.has(tab[0])).map(func(tab: Array) -> String: return tab[1])
			data["当前商城商品"] = {
				"物品ID": product.id, "名称": product.name, "分类": product.category,
				"槽位": product.slot, "售价（铜钱）": product.price, "页签": sections,
				"属性说明": ShopRules.description(product.id), "规则来源": product.rules_basis,
				"数据文件": "res://assets/data/shop-v2.json"
			}
			summary = "已接入商城 · %s · %s\n%s" % [product.name, product.category, summary]
		_add("items", item.id, item.display_name if confirmation.is_empty() else String(confirmation.name)+" · "+String(item.resource_id), summary, "原包资源", ORIGINAL_ITEMS, data, preview)
		if item.group in ["weapons", "equipment"]:
			_add(item.group, item.id, item.display_name, summary, "原包资源", ORIGINAL_ITEMS, data, preview)

func _load_maps() -> void:
	for zone in 2:
		# _build_map has no player/network side effects; do not add this world to a SceneTree.
		var world := WORLD.new()
		world.zone = zone
		world._build_map()
		var tiles: Array[int] = []
		var blocked: Array[bool] = []
		for y in WORLD.MAP_SIZE:
			for x in WORLD.MAP_SIZE:
				var point := Vector2i(x, y)
				var atlas := world.terrain.get_cell_atlas_coords(point)
				tiles.append(atlas.y * 32 + atlas.x)
				blocked.append(world.astar.is_point_solid(point))
		var data := {"zone": zone, "width": WORLD.MAP_SIZE, "height": WORLD.MAP_SIZE, "cell_size": WORLD.CELL, "tiles": tiles, "blocked": blocked, "阻挡说明": "地形阻挡，不包含运行时树木与交互对象", "数据来源": "运行时同一生成函数，未进入游戏场景"}
		_add("maps", "offline_%d" % zone, "青云山道" if zone == 0 else "古剑遗迹", "离线 · %d × %d 格" % [WORLD.MAP_SIZE, WORLD.MAP_SIZE], "已接入", "res://scripts/world.gd", data, {"kind": "map"})
		world.free()
	var online := _read_json(ONLINE_MAP)
	if not online.is_empty():
		_add("maps", online.get("map_id", "online"), "青云山道 · 联机", "联机 · %d × %d 格" % [int(online.get("width", 0)), int(online.get("height", 0))], "已接入", ONLINE_MAP, online, {"kind": "map"})

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("缺少数据文件：" + path)
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		errors.append("无法解析数据文件：" + path)
		return {}
	return parser.data

func _add(category: String, id: String, title: String, summary: String, status: String, source: String, data: Dictionary, preview: Dictionary = {}) -> void:
	entries.append({"category": category, "id": id, "name": title, "summary": summary, "status": status, "source": source, "data": data, "preview": preview})

func equipment_slot(entry: Dictionary) -> String:
	# Original evidence keeps its unknown fields; classify using the current shop mapping.
	var data: Dictionary = entry.get("data", {})
	if data.has("槽位序号"):
		var index := int(data["槽位序号"])
		return ShopRules.SLOTS[index] if index >= 0 and index < ShopRules.SLOTS.size() else ""
	var item := ShopRules.item(entry.get("preview", {}).get("equipment_id", ""))
	var slot: String = item.get("slot", data.get("slot", ""))
	return slot if slot in ShopRules.SLOTS else ""

func find(category: String, query: String = "", status: String = "全部", slot: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var words := query.strip_edges().to_lower().split(" ", false)
	for entry in entries:
		if entry.category != category or (status != "全部" and entry.status != status): continue
		if not slot.is_empty() and equipment_slot(entry) != slot: continue
		if words.is_empty():
			result.append(entry)
			continue
		var haystack: String = (String(entry.id) + " " + String(entry.name) + " " + String(entry.summary) + " " + JSON.stringify(entry.data)).to_lower()
		var matches := true
		for word in words:
			if not haystack.contains(word):
				matches = false
				break
		if matches: result.append(entry)
	return result
