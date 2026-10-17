extends Node
const DELAYED = preload("res://tests/fixtures/delayed_storage.gd")
var checks := 0
var failures := 0
func _ready() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error("SHOP: "+text)
func capture(name: String) -> void:
	var path := OS.get_environment("SSJX_SHOP_CAPTURE")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path.path_join(name+".png"))
func _command(results: Array) -> void: results.append(await Game.shop_command("buy","weapon_3"))
func _run() -> void:
	await Platform.when_ready()
	var old := Game.player.duplicate(true)
	var old_path := Game.save_path
	var platform := Platform.context
	var outbox := OnlineAccount.pending_pve.duplicate(true)
	Game.save_path = "user://shop_test_%d.json" % Time.get_ticks_usec()
	var path := Game.save_path
	Game.new_player("商店测试",1,1)
	check(Game.valid_save(Game.player),"Legacy save remains valid")
	var before := Game.player.duplicate(true)
	check(not (await Game.shop_command("buy","weapon_2")).ok and Game.player == before,"Insufficient gold never mutates character")
	Game.player.gold = 500
	check((await Game.shop_command("buy","weapon_2")).ok and int(Game.player.gold) == 460,"Purchase deducts copper")
	check(Game.appearance_key()=="hero/mck_w0_c0","Purchase does not auto equip")
	check(not (await Game.shop_command("buy","weapon_2")).ok and int(Game.player.gold)==460,"Duplicate purchase rejected")
	check((await Game.shop_command("equip","weapon_2")).ok and Game.stats().attack==31,"Purchased weapon equips with correct stats")
	check(Game.appearance_key()=="hero/mck_w2_c0","Weapon changes appearance")
	check((await Game.shop_command("buy","armor_2")).ok and (await Game.shop_command("equip","armor_2")).ok,"Armor can be bought and equipped")
	check(Game.appearance_key()=="hero/mck_w2_c1" and Game.stats().defense==7,"Armor changes appearance and defense")
	check(Game.attribute_profile().combat.physical_attack==31 and Game.attribute_profile().combat.physical_defense==7,"Property page and combat share gear bonuses")
	var equipped := Game.player.duplicate(true)
	check((await Game.load_game()).ok and Game.player == JSON.parse_string(JSON.stringify(equipped)),"Purchases and loadout survive reload")
	var invalid := Game.player.duplicate(true)
	invalid.shop_owned = "weapon_3"
	check(not Game.valid_save(invalid),"Malformed owned list is rejected safely")
	invalid = Game.player.duplicate(true);invalid.shop_weapon = "weapon_3"
	check(not Game.valid_save(invalid),"Unowned equipped item is rejected")
	for gender in 2:
		for job in 3:
			for weapon in 4:
				for armor in 3:
					var key := ShopRules.actor_key(job,gender,[weapon,armor])
					var info := OriginalArt.actor_info(key)
					var base := OriginalArt.actor_info(ShopRules.actor_key(job,gender,[1,0]))
					check(not info.is_empty() and info.playback == base.playback and info.native_battle == base.native_battle,"All loadouts preserve audited animation and motion: "+key)
	var app = load("res://scenes/main.tscn").instantiate()
	add_child(app);app._enter_world();app._scene_action("shop")
	var page: ShopPanel = app.modal.get_child(1)
	check(page is ShopPanel and page.rows.size()==ShopRules.catalog.items.size(),"Game menu opens the complete shared shop")
	page.selected="armor_3";page.refresh()
	check(page.preview.get_meta("art_key")=="hero/mck_w2_c2" and Game.appearance_key()=="hero/mck_w2_c1","Shop preview does not change equipped gear")
	await capture("local_shop")
	app._close_modal();app._bag()
	var bag: OriginalInventory = app.backpack
	check(bag.equipment_icon.visible and bag.armor_icon.visible,"Backpack displays both equipped slots")
	check(bag.preview.get_meta("art_key")==Game.appearance_key(),"Bag uses actual loadout")
	await capture("local_bag")
	bag._select_equipment(2)
	check(bag._selected().id=="armor_2","Armor slot selects correct owned item")
	await bag.equip_item()
	check(ShopRules.local_state(Game.player).armor==null and Game.stats().defense==4,"Backpack unequips armor and restores defense")
	check(app.world.hero.get_meta("art_key")==Game.appearance_key(),"World refreshes appearance after bag operation")
	await Game.shop_command("equip","armor_2")
	app._close_modal();app._attributes()
	check(app.attributes.preview.get_meta("art_key")==Game.appearance_key(),"Attributes preview shares loadout")
	app.queue_free();await get_tree().process_frame
	var storage := DELAYED.new()
	Platform.context = PlatformContext.new("shop-test",storage,platform.runtime_config,platform.display,platform.lifecycle,platform.resource_loader,platform.text_input,platform.system_actions)
	before = Game.player.duplicate(true)
	var results: Array = []
	_command(results)
	check(Game.storage_busy and results.is_empty(),"Local purchase waits for durable receipt")
	check(not (await Game.shop_command("buy","weapon_3")).ok and storage.operations.size()==1,"Double click cannot queue another purchase")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","持久化失败"))
	check(results.size()==1 and not results[0].ok and Game.player==before,"Failed persistence rolls back gold and ownership")
	results.clear()
	_command(results)
	Game.new_player("切换后的角色",0,0)
	storage.complete(PlatformResult.success({"written":true,"durability":"native_file"}))
	check(results.size()==1 and results[0].status==PlatformResult.Status.CANCELLED and Game.player.name=="切换后的角色","Stale purchase receipt cannot replace a switched character")
	check(ShopRules.description("armor_2")=="防御 +3","Armor description formats the displayed bonus")
	check(OnlineAccount.pending_pve==outbox,"Local shop never sends network commands")
	Platform.context=platform
	Game.player=old;Game.save_path=old_path
	DirAccess.remove_absolute(path)
	print("SHOP: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
