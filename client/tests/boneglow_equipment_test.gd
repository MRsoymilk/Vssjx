extends Node
const MAPPING := preload("res://scripts/admin/equipment_appearance.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BONEGLOW: "+message)

func _ready() -> void: _run.call_deferred()

func capture(name: String) -> void:
	var folder := OS.get_environment("SSJX_BONEGLOW_GAME_CAPTURE")
	if folder.is_empty() or DisplayServer.get_name()=="headless": return
	for frame in 4: await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"Captured actual game UI: "+name)

func _run() -> void:
	await Platform.when_ready()
	var previous := Game.player.duplicate(true)
	var previous_path := Game.save_path
	var previous_hash := FileAccess.get_sha256(previous_path) if FileAccess.file_exists(previous_path) else ""
	var pending := OnlineAccount.pending_pve.duplicate(true)
	var scratch := "user://boneglow_test_%d.json" % Time.get_ticks_usec()
	Game.save_path = scratch
	for definition in BoneglowEquipment.manifest().sets:
		Game.new_player("骨甲测试",int(definition.job),0,int(definition.gender))
		Game.player.gold = 10000
		var base_stats := Game.stats()
		var items: Array = ShopRules.catalog.items.filter(func(entry: Dictionary) -> bool: return entry.get("set_id") == definition.id)
		check(items.size() == 10,"Every set covers ten slots")
		for entry in items:
			check((await Game.shop_command("buy",entry.id)).ok,"Durable purchase: "+entry.id)
			check((await Game.shop_command("equip",entry.id)).ok,"Durable equip: "+entry.id)
			check(ResourceLoader.exists(entry.icon),"Production icon imported")
			var foreign := Game.player.duplicate(true)
			foreign.gender = 1-int(definition.gender)
			check(ShopRules.apply_local(foreign,"equip",entry.id)=="WRONG_GENDER","Wrong gender cannot equip")
			check(not Game.valid_save(foreign),"A forged save cannot bypass gender restrictions")
			foreign = Game.player.duplicate(true)
			foreign.job = (int(definition.job)+1)%3
			check(ShopRules.apply_local(foreign,"equip",entry.id)=="WRONG_JOB","Wrong job cannot equip")
		var look := [int(definition.weapon_code),int(definition.clothing_code),int(definition.head_code)]
		var gear := ShopRules.local_state(Game.player)
		check(ShopRules.appearance(gear)==look and ShopRules.valid_gear(gear),"Full set produces valid authoritative gear and codes")
		check(Game.stats().attack==base_stats.attack+12 and Game.stats().defense==base_stats.defense+27,"All ten slots contribute the defined stats")
		check((await Game.load_game()).ok and ShopRules.appearance(ShopRules.local_state(Game.player))==look,"Purchase and full loadout survive disk reload")
		var key := ShopRules.actor_key(int(definition.job),int(definition.gender),look)
		var native := OriginalArt.actor_info("hero/"+definition.stem)
		var built := HeroAppearance.build(key,native)
		check(not built.is_empty() and built.info.playback==native.playback and built.info.count==native.count,"Full native animation timing and frames preserved")
		var actor := OriginalArt.battle_actor(key)
		for action in native.playback:
			check(actor.sprite_frames.get_frame_count(action)==native.playback[action].size(),"Playable native action: "+definition.stem+" / "+action)
		check(actor.get_meta("native_ground_anchor",false),"Battle ground/recoil anchors are retained")
		actor.free()
		for component in 3:
			var mixed := [0,0,0]
			mixed[component] = look[component]
			check(not OriginalArt.actor_info(ShopRules.actor_key(int(definition.job),int(definition.gender),mixed)).is_empty(),"Each new visual component works with default parts")
		var mapping := MAPPING.variant(ShopRules.item("ai/"+definition.id+"/armor"),int(definition.job),int(definition.gender),true)
		check(mapping["装备后动画"]==key and mapping["装备后部件"]["头饰"]==[definition.head],"Full-set admin preview uses exact game parts")
		var shop: ShopPanel = load("res://scenes/ui/shop_panel.tscn").instantiate()
		add_child(shop)
		shop.category = "骨甲幽光 · 本角色"
		shop._filter()
		check(shop.goods.size()==10 and shop.goods.all(func(entry: Dictionary) -> bool: return entry.set_id==definition.id),"Shop exposes the complete set for this character")
		shop.queue_free()
		await get_tree().process_frame
	var app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_world()
	check(app.world.hero.get_meta("art_key")==Game.appearance_key(),"World scene renders the actual equipped set")
	await capture("world")
	app._scene_action("shop")
	var game_shop: ShopPanel = app.modal.get_child(1)
	game_shop.category="骨甲幽光 · 本角色"
	game_shop._filter()
	check(game_shop.goods.size()==10,"Game menu reaches the real themed shop category")
	await capture("shop")
	app._close_modal()
	app._bag()
	check(app.backpack.preview.get_meta("art_key")==Game.appearance_key(),"Backpack renders the new equipped portrait")
	check(app.backpack.slot_icons.values().all(func(icon: TextureRect)->bool:return icon.visible and icon.texture!=null),"Backpack displays every new equipment icon")
	await capture("inventory")
	app.queue_free()
	await get_tree().process_frame
	var browser = load("res://scenes/admin/data_browser.tscn").instantiate()
	add_child(browser)
	browser.select_category("appearance")
	browser.get_node("%Search").text = "ai/boneglow/mzs/armor"
	browser._fill_list()
	var panel = browser.get_node("%AppearanceComparison")
	check(browser.visible_entries.size()==1 and panel.get_node("%SetPreview").visible,"Generated equipment discoverable in data browser")
	panel.get_node("%SetPreview").button_pressed = true
	check(panel.after_preview.sprite.get_meta("art_key")=="hero/mzs_w28_c12_h10","Authored full-set toggle previews all three visual components")
	check(panel.get_node("%Gender").is_item_disabled(1),"Preview enforces the actual gender restriction")
	for frame in 4: await get_tree().process_frame
	for control in [panel,panel.get_node("%SetPreview"),panel.after_preview,browser.get_node("%Copy"),browser.get_node("%Footer")]:
		check(get_viewport().get_visible_rect().grow(1).encloses(control.get_global_rect()),"Full-set preview controls fit the desktop")
	await capture("admin")
	browser.queue_free()
	var world := OnlineWorldClient.new()
	world.world_ready = true
	world._shop_version = 2
	world.map_id = "qingyun_path"
	var id := "00000000-0000-4000-8000-000000000001"
	world._receive({"type":"world.appearance","map_id":world.map_id,"looks":{id:[33,17,15]}},PackedByteArray())
	check(world.world_ready and world.appearances.get(id)==[33,17,15],"World stream accepts the new head/body/weapon codes")
	world.free()
	for bad in [[34,0,0],[0,18,0],[0,0,16],[28.5,12,10],[-1,0,0],[],[0,0]]:
		check(not ShopRules.valid_appearance(bad),"Reject out-of-range or malformed appearance")
	var fixture := OS.get_environment("SSJX_BONEGLOW_LIVE_FIXTURE")
	if not fixture.is_empty():
		var records: Array = JSON.parse_string(FileAccess.get_file_as_string(fixture))
		for record in records:
			var pve := OnlinePve.new()
			pve.character_id = record.character.id
			check(OnlineAccount._valid_character(record.character),"Real server roster accepts generated appearance")
			check(pve.valid(record.state),"Real persisted server state is accepted by the client")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	Game.player = previous
	Game.save_path = previous_path
	check(OnlineAccount.pending_pve==pending and (FileAccess.get_sha256(previous_path) if FileAccess.file_exists(previous_path) else "")==previous_hash,"No player's save or online command was changed")
	await get_tree().process_frame
	print("BONEGLOW EQUIPMENT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
