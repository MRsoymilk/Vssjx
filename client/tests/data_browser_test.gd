extends Node

const CATALOG := preload("res://scripts/admin/data_catalog.gd")
const BROWSER := preload("res://scenes/admin/data_browser.tscn")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func capture_image(path: String) -> bool:
	# Do not wait forever for frame_post_draw when Windows occludes a test window.
	RenderingServer.force_draw()
	return get_viewport().get_texture().get_image().save_png(path) == OK

func _ready() -> void:
	var original_player := Game.player.duplicate(true)
	var original_save_path: String = Game.save_path
	var save_hash := FileAccess.get_sha256(Game.save_path) if FileAccess.file_exists(Game.save_path) else ""
	var catalog := CATALOG.new()
	catalog.reload()
	check(catalog.errors.is_empty(), "All JSON sources load")
	var counts := {"weapons": 140, "equipment": 390, "items": 667, "characters": 1145, "quests": 658, "maps": 431, "enemies": 577, "skills":106, "effects": 159, "art": 277, "archive": 1917}
	for category in counts:
		check(catalog.find(category).size() == counts[category], "Expected current definitions for " + category)
	var keys: Dictionary = {}
	for entry in catalog.entries:
		var key: String = entry.category + ":" + entry.id
		check(not keys.has(key), "Unique category/id: " + key)
		keys[key] = true
		check(FileAccess.file_exists(entry.source), "Source exists: " + key)
	check(catalog.find("equipment", "", "预留").is_empty(), "All ten equipment slots have actual definitions")
	check(catalog.find("items", "", "重建商店").size()==336,"Full runtime rules remain separate from raw resource evidence")
	check(catalog.find("items", "", "原包资源").size() == 208, "Every decoded item is included, regardless of gameplay integration")
	check(catalog.find("weapons", "", "原包资源").size() == 56, "All 56 original weapon icons")
	check(catalog.find("equipment", "", "原包资源").size() == 81, "All 81 original equipment icons")
	check(catalog.find("items", "iw56", "原包资源").size() == 1, "Original filename search")
	for entry in catalog.find("items", "", "原包资源"):
		if entry.id=="original/ix10":
			check(entry.data["原版名称"]=="生骨融血草" and entry.data["原版属性"]=={"恢复气血":8000},"User-confirmed herb name and recovery are explicit")
		elif entry.id=="original/ix14":
			check(entry.data["原版名称"]=="极品人参" and entry.data["原版属性"]=={"恢复灵力":4000},"User-confirmed ginseng name and mana recovery are explicit")
		elif entry.id=="original/ix26":
			check(entry.data["原版名称"]=="荷叶烧鸡" and entry.data["原版等级"]==1 and entry.data["原版属性"]=={"恢复气血":6000},"Screenshot-confirmed chicken name, level and healing are explicit")
		else:
			check(entry.data["原版名称"] == null and entry.data["原版属性"] == null, "Unknown original names and stats remain unknown: " + entry.id)
		var product:=ShopRules.item(entry.id)
		var linked:Dictionary=entry.data.get("当前商城商品",{})
		check(entry.data.get("商城接入")=="已接入" and linked.get("物品ID")==entry.id and linked.get("名称")==product.name and linked.get("售价（铜钱）")==product.price,"Every original resource links to its actual shop product: "+entry.id)
		check(entry.summary.contains("已接入商城") and entry.summary.contains(product.name) and linked.get("规则来源")==product.rules_basis,"Shop availability and reconstructed rules are explicit: "+entry.id)
		if ShopRules.is_equipment(product):
			check(catalog.equipment_slot(entry)==product.slot and entry.preview.get("equipment_id")==entry.id,"Original equipment keeps slot filtering and actual appearance preview: "+entry.id)
	var hats:=catalog.find("equipment","","原包资源","hat")
	check(hats.size()==9,"All nine requested original hats are discoverable by slot")
	for number in [1,10,20,29,39,48,57,66,75]:
		check(hats.any(func(entry:Dictionary)->bool:return entry.id=="original/if%d"%number),"Requested hat has a linked original record: if%d"%number)
	check(catalog.find("items", "", "已接入").size() == 2, "Original icons are distinct from authored runtime rules")
	check(catalog.find("items", "青锋", "已接入").size() == 1 and catalog.find("items", "青锋", "重建商店").size()>=1, "Chinese search distinguishes legacy and reconstructed names")
	check(catalog.find("enemies", "WOLF_A").size() == 1, "Case-insensitive ID search")
	check(catalog.find("enemies", "", "已接入").size() == 6, "Six authored enemy definitions remain separate")
	check(catalog.find("enemies", "", "原包资源").size() == 117, "All original monster animations are included")
	check(catalog.find("enemies", "zbjl2", "原包资源").size() == 1, "Original monster resource IDs are searchable")
	check(catalog.find("effects", "", "原包资源").size() == 159, "Every original effect animation is indexed")
	for entry in catalog.find("effects"):
		check(entry.data["原版名称"] == null and entry.data["原版特效ID"] == null and entry.data["原服技能对应关系"] == null, "Original evidence remains distinct from project skill mappings: " + entry.id)
	check(catalog.find("skills","雷霆一击").size()==4,"Base and all three upgrade stages are independently indexed")
	check(catalog.find("skills","石破天惊").size()==4,"Added skill includes all stages in resource manager")
	check(catalog.find("effects","雷霆一击").size()==4,"Effect resources link back to their actual skill stages")
	var stage_record:Dictionary=catalog.find("skills","雷霆一击 阶段3")[0]
	check(stage_record.preview.art=="effect/t174" and stage_record.data["阶段起始技能等级"]==15,"Manager preview uses corrected final-stage resource")
	check(catalog.find("archive", "", "未解析").size() == 9 and catalog.find("archive", "", "部分解析").size() == 321, "Unsupported and partially parsed members remain archived")
	check(catalog.find("archive", "archive/ssjx.mrp/sfc.bin").size() == 1, "Unsupported binary is searchable by original archive path")
	for entry in catalog.find("enemies", "", "原包资源"):
		check(entry.data["原版名称"] == null and entry.data["原版属性"] == null and entry.data["原版等级"] == null and entry.data["原版怪物ID"] == null, "Unknown monster identity and rules remain unknown: " + entry.id)
	check(catalog.find("weapons", "青锋 5", "已接入").size() == 1, "Multiple words search across name and actual stat fields")
	check(catalog.find("items", "不存在的道具").is_empty(), "No fabricated fallback items")
	var sword: Dictionary = catalog.find("weapons")[0]
	check(sword.data["攻击加成"] == 5 and sword.data.icon.ends_with("bag_sword.png"), "Weapon properties derive from runtime stats and bag definitions")
	check(catalog.find("maps", "", "原包目录").size() == 214 and catalog.original_distinct_map_names == 157, "All original map directory records, including duplicate names")
	check(catalog.find("maps", "莫言山", "原包目录").size() > 1, "Same-name original directory records remain separate")
	check(catalog.find("quests", "", "重建阶段").size() == 5, "Rebuilt chain states are explicitly classified")
	check(catalog.find("quests", "", "原包文案").size() == 1 and catalog.find("quests", "", "原包线索").size() == 10, "Quest UI and guide evidence are not counted as recovered quests")
	for entry in catalog.find("maps", "", "原包目录"):
		check(not entry.data.has("tiles") and entry.preview.kind == "world_overview" and entry.data["服务器地图ID"] == null and entry.data["场景地形"] == null, "Only verified overview, no fabricated scene for " + entry.id)
	check(catalog.original_overview.nodes.size() == 79 and catalog.original_overview.routes.size() == 78, "Recovered original world overview")
	for entry in catalog.find("maps", "", "已接入"):
		check(entry.data.tiles.size() == entry.data.width * entry.data.height, "Complete tile matrix: " + entry.id)
		check(entry.data.blocked.size() == entry.data.tiles.size(), "Complete collision matrix: " + entry.id)
		for tile in entry.data.tiles:
			if tile < 0 or tile >= 756:
				check(false, "Tile outside imported atlas: " + entry.id)
	var offline: Dictionary = catalog.find("maps", "offline_0")[0].data
	check(offline.blocked[5 * 32 + 5] and not offline.blocked[16 * 32 + 5], "River blocked, bridge passable")
	var count := catalog.entries.size()
	catalog.reload()
	check(catalog.entries.size() == count, "Refresh replaces entries without duplicates")
	check(Game.player == original_player and Game.save_path == original_save_path, "Catalog loading does not mutate Game")
	var browser := BROWSER.instantiate()
	add_child(browser)
	await get_tree().process_frame
	await get_tree().process_frame
	check(browser.catalog.errors.is_empty() and browser.visible_entries.size() == counts.weapons, "Standalone browser opens with all original weapons and runtime rules")
	check(catalog.find("characters", "", "已接入").size()==6,"All six playable character definitions remain available")
	for entry in catalog.find("characters", "", "已接入"):
		browser._show_entry(entry)
		var chooser: OptionButton = browser.get_node("%Animations")
		var preview: Control = browser.get_node("%Preview")
		var info := OriginalArt.actor_info(entry.preview.art)
		check(chooser.item_count == info.playback.size() and chooser.get_item_text(0) == "待机", "Characters default to named Chinese runtime actions: " + entry.id)
		check(chooser.get_item_metadata(chooser.selected) == "idle", "Visible action matches the actual idle preview: " + entry.id)
		browser.get_node("%RawAnimations").button_pressed = true
		var previous_source := -1
		for index in chooser.item_count:
			var id: String = chooser.get_item_metadata(index)
			check(not chooser.get_item_text(index).begins_with("source_"), "User-facing actions have descriptive labels: " + id)
			if not id.begins_with("source_"): continue
			var source_index := int(id.trim_prefix("source_"))
			check(source_index > previous_source, "Raw sequence IDs use numerical ordering")
			previous_source = source_index
			chooser.select(index)
			chooser.item_selected.emit(index)
			check(preview.sprite.animation == id, "Chinese labels still play the correct raw sequence: " + id)
			check(browser.get_node("%AnimationHelp").text.contains(id), "Sequence evidence remains visible: " + id)
			if source_index == (7 if entry.preview.art.ends_with("fs") else 12):
				check(chooser.get_item_text(index).contains("普通攻击来源"), "An exact runtime attack mapping explains the source sequence")
			if source_index == 0:
				check(chooser.get_item_text(index).contains("用途未确认"), "Unverified original actions are not guessed")
		var replay_id: String = chooser.get_item_metadata(chooser.selected)
		preview.sprite.pause()
		browser.get_node("%Replay").pressed.emit()
		check(preview.sprite.animation == replay_id and preview.sprite.is_playing(), "Replay uses the stable ID instead of the translated label")
		browser.get_node("%RawAnimations").button_pressed = false
		check(chooser.item_count == info.playback.size() and preview.sprite.animation == "idle", "Closing raw sequences returns to a valid named action")
	for entry in catalog.find("enemies", "", "已接入"):
		browser._show_entry(entry)
		var chooser: OptionButton = browser.get_node("%Animations")
		check(chooser.item_count == 4, "Every active monster exposes idle/walk/attack/hurt")
		browser.get_node("%RawAnimations").button_pressed = true
		var raw_count := 0
		var attack_source := false
		for index in chooser.item_count:
			var id: String = chooser.get_item_metadata(index)
			if not id.begins_with("source_"): continue
			raw_count += 1
			check(not OriginalArt.actor_info(entry.preview.art).sequences[int(id.trim_prefix("source_"))].is_empty(), "Empty source sequences are not offered")
			if chooser.get_item_text(index).contains("普通攻击来源"):
				attack_source = true
				if entry.preview.art == "monster/langw":
					check(chooser.get_popup().get_item_tooltip(index).contains("映射相同"), "Wolf uses native attack frames, not impact-stripped substitutes")
		check(raw_count > 0 and attack_source, "Monster attacks remain traceable to original sequences")
	var scenery := catalog.find("art", "map/m1")[0]
	browser._show_entry(scenery)
	check(not browser.get_node("%RawAnimations").visible and browser.get_node("%Animations").get_item_metadata(0).begins_with("source_"), "Unmapped scenery is not given the renderer's fallback attack/walk labels")
	browser.select_category("items")
	browser.get_node("%StatusFilter").select(4)
	browser._fill_list()
	check(browser.visible_entries.size() == 208, "UI original-resource filter shows the whole item archive")
	browser.get_node("%Search").text = "iw56"
	browser._fill_list()
	check(browser.visible_entries.size() == 1 and browser.current.id == "original/iw56", "UI can find last original weapon")
	browser.select_category("equipment")
	browser.get_node("%StatusFilter").select(2)
	browser._fill_list()
	check(browser.visible_entries.is_empty(), "No reserved equipment after connecting all ten slots")
	browser.get_node("%StatusFilter").select(4)
	browser.get_node("%EquipmentSlotFilter").select(10)
	browser._fill_list()
	check(browser.visible_entries.size()==9,"Original-resource and hat filters expose all nine requested hats in the UI")
	for entry in hats:
		browser._show_entry(entry)
		check(browser.get_node("%Summary").text.contains("已接入商城") and browser.get_node("%Raw").text.contains(ShopRules.item(entry.id).name),"Original hat inspector shows current shop integration: "+entry.id)
		check(browser.get_node("%AppearanceComparison").visible,"Original hat inspector offers actual equipment preview: "+entry.id)
	browser.select_category("enemies")
	check(browser.visible_entries.size() == counts.enemies and browser.get_node("%Context").text.contains("117"), "Monster category explains definitions versus all original resources")
	browser.get_node("%StatusFilter").select(4)
	browser._fill_list()
	check(browser.visible_entries.size() == 117 and browser.get_node("%AnimationBar").visible, "Original monster filter exposes playable previews")
	browser.get_node("%Search").text = "zbjl2"
	browser._fill_list()
	check(browser.visible_entries.size() == 1 and browser.current.id == "original/monster/zbjl2", "UI finds a previously missing monster animation")
	browser.select_category("effects")
	check(browser.visible_entries.size() == 159 and browser.get_node("%Context").text.contains("技能对应关系"), "Complete effect category explains its recovery boundary")
	browser.get_node("%Search").text = "original/effect/t180"
	browser._fill_list()
	check(browser.visible_entries.size() == 1 and browser.current.id == "original/effect/t180" and browser.get_node("%AnimationBar").visible, "UI can find and play a previously missing effect")
	browser.select_category("archive")
	browser.get_node("%StatusFilter").select(11)
	browser._fill_list()
	check(browser.visible_entries.size() == 9 and browser.get_node("%PreviewMessage").visible, "Unparsed filter never hides unsupported members")
	browser.get_node("%Search").text = "archive/ssjx.mrp/sfc.bin"
	browser._fill_list()
	check(browser.visible_entries.size() == 1 and browser.current.data["SHA256"] != null and browser.current.data["原始前128字节（十六进制）"] != "", "Unparsed member exposes source evidence and binary prefix")
	browser.get_node("%StatusFilter").select(12)
	browser._fill_list()
	check(browser.visible_entries.is_empty() and browser.get_node("%Empty").visible, "Failed-parse filter supports empty results without inventing failures")
	browser.select_category("items")
	browser.get_node("%StatusFilter").select(1)
	browser.get_node("%Search").text = "回春"
	browser._fill_list()
	check(browser.visible_entries.size() == 1 and browser.current.id == "potion", "Search selects matching real item")
	browser.get_node("%Search").text = "___missing___"
	browser._fill_list()
	check(browser.current.is_empty() and browser.get_node("%Empty").visible and browser.get_node("%Copy").disabled, "Empty result clears details, preview and copy action")
	check(browser.get_node("%Raw").text.is_empty(), "No stale raw data in empty result")
	browser.select_category("maps")
	browser.get_node("%Records").get_root().get_child(2).select(0)
	browser.reload_data()
	check(browser.current.id == "qingyun_trail", "Refresh preserves selected item")
	browser.get_node("%Collision").button_pressed = true
	check(browser.get_node("%Preview").show_blocked, "Collision overlay toggle")
	browser.get_node("%StatusFilter").select(5)
	browser._fill_list()
	check(browser.visible_entries.size() == 214 and browser.get_node("%Context").text.contains("157"), "Map directory filter and contextual counts")
	check(not browser.get_node("%PreviewMessage").visible and not browser.get_node("%Collision").visible, "World overview preview is separate from scene collision")
	await get_tree().process_frame
	var world_preview: Control = browser.get_node("%Preview")
	var first_node: Dictionary = catalog.original_overview.nodes[0]
	var position: Array = first_node.world_position
	var point: Vector2 = world_preview.overview_transform() * Vector2(position[0], position[1])
	check(world_preview.overview_node_at(point).original_map_id == first_node.original_map_id, "Overview hover matches original row/column coordinates")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	world_preview._gui_input(motion)
	check(world_preview.tooltip_text.contains(first_node.name) and world_preview.tooltip_text.contains("等级"), "Overview exposes verified name and levels")
	check(world_preview.overview_icons.size() == 3 and world_preview.overview_icons[0] != null, "Original world node icons load")
	browser.select_category("quests")
	browser.get_node("%StatusFilter").select(6)
	browser._fill_list()
	check(browser.current.id == "original/mission.str" and browser.current.data["原版任务总数"] == null and browser.get_node("%Summary").text.contains("原版任务总数未知"), "Quest UI evidence is visibly separate from a quest definition")
	check(browser.get_node("%Texts").text.contains("任务目标") and not browser.get_node("%Texts").bbcode_enabled, "Original text is readable inert content")
	check(browser.get_node("%Texts").get_parent().current_tab == 2, "Text evidence automatically opens the excerpt tab")
	browser.select_category("maps")
	browser.get_node("%StatusFilter").select(5)
	browser._fill_list()
	check(browser.get_node("%Texts").get_parent().current_tab == 0, "Leaving text evidence restores readable fields instead of an implicitly selected raw tab")
	for category in counts:
		browser.select_category(category)
		check(browser.visible_entries.size() == counts[category], "UI category switches: " + category)
		var preview_entries: Array = browser.visible_entries
		if category == "archive":
			# All members are checked above; exercise each parser/preview type here.
			preview_entries = []
			for path in ["archive/ssjx.mrp/bag.str", "archive/ssjx.mrp/fm1.img", "archive/ssjx.mrp/bigscroll.imgs", "archive/ssjx/effect.mrp/t180.ani", "archive/ssjx/hero.mrp/mck.ani", "archive/ssjx/map.mrp/m0.ani", "archive/ssjx/map.mrp/m1.ani", "archive/ssjx.mrp/start.mr"]:
				var matches := catalog.find("archive", path)
				check(matches.size() == 1, "Archive member is accessible: " + path)
				if matches.size() == 1: preview_entries.append(matches[0])
		for entry in preview_entries:
			browser._show_entry(entry)
			if entry.id.begins_with("original/monster/"):
				check(entry.data.has("动画检查"), "Every original monster exposes its animation audit: " + entry.id)
				if entry.data.has("动画检查"):
					check(entry.data["动画检查"]["结构检查"] == "通过", "Monster archive passes structural checks: " + entry.id)
			if entry.preview.get("kind") == "icon":
				if entry.preview.has("equipment_id"):
					check(browser.get_node("%AppearanceComparison").visible and is_instance_valid(browser.get_node("%AppearanceComparison").after_preview.sprite), "Actual equipment preview loads: " + entry.id)
				else:
					check(browser.get_node("%Preview").icon != null, "Decoded icon loads: " + entry.id)
			if entry.preview.get("kind") == "actor":
				var preview: Control = browser.get_node("%Preview")
				check(is_instance_valid(preview.sprite), "Actual actor preview: " + entry.id)
				var attack_loop: bool = preview.sprite.sprite_frames.get_animation_loop("attack")
				preview.play_animation("attack")
				check(preview.sprite.sprite_frames.get_animation_loop("attack") == attack_loop, "Preview leaves shared animation loop unchanged: " + entry.id)
			if entry.preview.get("kind") in ["original_animation", "image_frames"]:
				var preview: Control = browser.get_node("%Preview")
				check(is_instance_valid(preview.sprite), "Original atlas loads: " + entry.id)
				var info: Dictionary = entry.preview.animation
				var atlas_center: Vector2 = preview.sprite.offset + Vector2(info.width, info.height) * 0.5
				check(not preview.sprite.centered and (preview.sprite.transform * atlas_center).is_equal_approx(preview.size * 0.5), "Original monster atlas is centered inside the visible preview: " + entry.id)
				for index in entry.preview.animation.sequences.size():
					var steps: Array = entry.preview.animation.sequences[index]
					var animation := ("frame_%d" if entry.preview.kind == "image_frames" else "source_%d") % index
					if steps.is_empty():
						check(not preview.sprite.sprite_frames.has_animation(animation), "Empty source sequence is not played: " + entry.id)
						continue
					check(preview.sprite.sprite_frames.get_frame_count(animation) == steps.size(), "Original monster sequence is complete: " + entry.id + " / " + animation)
					preview.play_animation(animation)
					check(preview.sprite.animation == animation and preview.sprite.is_playing(), "Original monster animation plays: " + entry.id + " / " + animation)
	browser.select_category("characters")
	await get_tree().process_frame
	check(browser.get_node("%Inspector").size.x >= 360, "Readable desktop inspector width")
	check(not browser.get_node("%Raw").editable and not browser.get_node("%Source").editable, "Read-only detail controls")
	get_window().size = Vector2i(960, 540)
	await get_tree().process_frame
	await get_tree().process_frame
	var inspector: Control = browser.get_node("%Inspector")
	check(inspector.get_global_rect().end.x <= get_window().size.x, "Inspector fits minimum window width")
	check(browser.get_node("%Copy").get_global_rect().end.y < get_window().size.y, "Inspector actions fit minimum window height")
	get_window().size = Vector2i(1360, 900)
	await get_tree().process_frame
	await get_tree().process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-animation-labels=") and DisplayServer.get_name() != "headless":
			var output := argument.trim_prefix("--capture-animation-labels=")
			browser.select_category("characters")
			await get_tree().process_frame
			await get_tree().process_frame
			check(capture_image(output), "Rendered Chinese action labels")
			browser.get_node("%RawAnimations").button_pressed = true
			var chooser: OptionButton = browser.get_node("%Animations")
			for index in chooser.item_count:
				if chooser.get_item_metadata(index) == "source_12":
					chooser.select(index)
					chooser.item_selected.emit(index)
			await get_tree().process_frame
			check(capture_image(output.get_basename() + "-raw.png"), "Rendered original-sequence action provenance")
		if argument.begins_with("--capture-data-browser="):
			var output := argument.trim_prefix("--capture-data-browser=")
			if DisplayServer.get_name() != "headless":
				check(capture_image(output), "Rendered browser screenshot")
				browser.select_category("equipment")
				browser.get_node("%StatusFilter").select(4)
				browser.get_node("%EquipmentSlotFilter").select(10)
				browser._fill_list("original/if75")
				await get_tree().process_frame
				check(capture_image(output.get_basename() + "-original-hats.png"), "Rendered original hat records and linked shop details")
				browser.select_category("enemies")
				browser.get_node("%StatusFilter").select(4)
				browser._fill_list()
				browser.get_node("%Search").text = "zbjl2"
				browser._fill_list()
				await get_tree().process_frame
				check(capture_image(output.get_basename() + "-original-monsters.png"), "Rendered complete monster catalog and original animation")
				browser.select_category("maps")
				browser.get_node("%Records").get_root().get_child(2).select(0)
				await get_tree().process_frame
				check(capture_image(output.get_basename() + "-maps.png"), "Rendered map screenshot")
				browser.select_category("weapons")
				browser.get_node("%StatusFilter").select(4)
				browser._fill_list()
				await get_tree().process_frame
				check(capture_image(output.get_basename() + "-weapons.png"), "Rendered complete original-weapon catalog")
				browser.select_category("maps")
				browser.get_node("%StatusFilter").select(5)
				browser._fill_list()
				await get_tree().process_frame
				check(capture_image(output.get_basename() + "-original-maps.png"), "Rendered original map directory and recovery boundary")
				browser.select_category("quests")
				browser.get_node("%StatusFilter").select(6)
				browser._fill_list()
				await get_tree().process_frame
				check(capture_image(output.get_basename() + "-quest-evidence.png"), "Rendered quest text without claiming quest completeness")
	check(Game.player == original_player and Game.save_path == original_save_path, "Browsing all categories leaves player untouched")
	var final_hash := FileAccess.get_sha256(Game.save_path) if FileAccess.file_exists(Game.save_path) else ""
	check(final_hash == save_hash, "Player save bytes unchanged")
	browser.queue_free()
	await get_tree().process_frame
	print("Data browser: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
