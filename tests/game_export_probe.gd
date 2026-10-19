extends SceneTree
## Run this filesystem script against the actual exported PCK, not source res://.

var checks := 0

func _initialize() -> void:
	_verify.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		push_error("EXPORT FAIL: " + description)
		quit(1)
		assert(false, description)

func _verify() -> void:
	check(FileAccess.file_exists("res://project.binary"), "Running from packed project settings")
	for path in ["res://scenes/admin/data_browser.tscn", "res://scenes/admin/world_overview.tscn", "res://scripts/admin/data_browser.gd", "res://scripts/admin/admin_window_layout.gd", "res://tests/data_browser_test.tscn"]:
		check(not ResourceLoader.exists(path), "Developer resource is absent: " + path)
	for path in ["res://scenes/admin", "res://scripts/admin", "res://assets/admin", "res://tests"]:
		check(not DirAccess.dir_exists_absolute(path), "Developer directory is absent: " + path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/actors.json"))
	check(manifest.get("actors", {}).size() >= 100 and manifest.actors.has("main/death") and manifest.actors.has("main/ltz_win") and manifest.actors.has("main/ltz_lose"), "Actor index includes death, battle results, equipment and expanded monsters")
	for path in manifest.actors.values():
		check(FileAccess.file_exists(path), "Dynamically loaded actor JSON is included: " + path)
	var ai_world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/ai-world-v1.json"))
	check(ai_world.maps.size() == 214, "All generated map definitions are included")
	for map in ai_world.maps:
		for resident in map.residents:
			check(manifest.actors.has(resident.art), "Packed resident actor: " + resident.id)
	var skill_rules = load("res://scripts/skill_rules.gd")
	check(skill_rules.list_for(1, 0, 50).size() == 8 and skill_rules.list_for(1, 3, 50) == skill_rules.list_for(1, 0, 50), "Packed skills unlock by job and level for all schools")
	var shop_rules = load("res://scripts/shop_rules.gd")
	check(shop_rules.catalog.items.size()==214,"All recovered goods are in the packed catalog")
	for item in shop_rules.catalog.items:
		check(ResourceLoader.exists(item.icon),"Packed product icon: "+item.id)
	var parts:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/hero-parts.json"))
	check(parts.parts.size()==299,"All original appearance parts are packaged")
	for part in parts.parts.values():check(ResourceLoader.exists(part.texture),"Packed original part: "+part.texture)
	var art=load("res://scripts/art.gd")
	for stem in ["mzs","wzs","mck","wck","mfs","wfs"]:
		var key:String="hero/%s_w19_c11_h9"%stem
		var actor=art.actor(key)
		check(actor.sprite_frames!=null and actor.get_meta("art_key","")==key,"Packed dynamic head/body/weapon: "+stem)
		actor.free()
	for gender in 2:
		for job in 3:
			for weapon in 4:
				for armor in 3:
					var key: String = shop_rules.actor_key(job,gender,[weapon,armor])
					check(manifest.actors.has(key), "Packed appearance metadata: " + key)
					var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest.actors[key]))
					check(ResourceLoader.exists(info.texture), "Packed appearance texture: " + key)
	check(ResourceLoader.exists("res://scenes/ui/shop_panel.tscn"), "Shop interface is included")
	check(FileAccess.file_exists("res://assets/data/original_world.json"), "Shared game world data is still included")
	check(ResourceLoader.exists("res://scenes/main.tscn"), "Game main scene is included")
	var bundled_font = load("res://assets/fonts/cjk_fallback.tres")
	check(bundled_font is Font and bundled_font.has_char(0x4e2d), "Bundled CJK fallback contains actual Chinese glyphs")
	check(ResourceLoader.exists("res://scripts/interface/adapters/web/web_resource_loader.gd"), "Single-threaded Web resource port is packaged")
	check(ResourceLoader.exists("res://scripts/interface/adapters/web/web_lifecycle.gd"), "Browser lifecycle port is packaged")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for frame in 5: await process_frame
	check(scene.mode == "home" and is_instance_valid(scene.original_cover), "The exported game reaches its normal home screen")
	check(root.content_scale_size == Vector2i(320, 480), "Game export keeps its portrait viewport")
	var platform = root.get_node("Platform")
	check(platform.is_available() and platform.context.capabilities().resource_preparation, "Packed project publishes the resource interface")
	var game = root.get_node("Game")
	var original_path: String = game.save_path
	var original_player: Dictionary = game.player.duplicate(true)
	game.save_path = "user://export_async_probe_%d.json" % OS.get_process_id()
	game.new_player("包内存档", 1, 0)
	var saved = await game.save_game()
	check(saved.ok and saved.value.durability == "native_file", "Packed async save completes with the actual native-file receipt")
	var probed = await game.probe_save()
	check(probed.ok and probed.value, "Packed async probe confirms the slot")
	game.player.gold = 0
	var restored = await game.load_game()
	check(restored.ok and game.player.gold == 30 and game.player.version == 1, "Packed async read preserves v1 save compatibility")
	game.player.gold = 200
	check((await game.shop_command("buy","weapon_2")).ok and (await game.shop_command("buy","armor_2")).ok, "Packed shop purchases use actual persistent storage")
	check((await game.shop_command("equip","weapon_2")).ok and (await game.shop_command("equip","armor_2")).ok, "Packed equipment can be equipped")
	check(game.appearance_key() == "hero/mck_w2_c1" and game.stats().attack == 31 and game.stats().defense == 7, "Packed gear changes appearance and combat stats")
	check((await game.load_game()).ok and game.player.gold == 125 and game.appearance_key() == "hero/mck_w2_c1", "Packed purchase and appearance survive reload")
	check(DirAccess.remove_absolute(game.save_path) == OK, "Remove only the owned export save fixture")
	game.save_path = original_path
	game.player = original_player
	var texture_path := "res://assets/actors/map_m10.png"
	var request = platform.context.resource_loader.prepare(PackedStringArray([texture_path]), scene, 1)
	var deadline := Time.get_ticks_msec() + 5000
	while not request.is_finished() and Time.get_ticks_msec() < deadline: await process_frame
	check(request.is_finished() and request.result.ok and request.result.value[texture_path] is Texture2D, "Threaded preparation reads the actual packed texture")
	check(request.progress == 1.0 and request.generation == 1, "Packed resource request completes with its generation")
	scene._server_login()
	var login = scene.modal.get_node("ServerLogin")
	check(platform.context.text_input.request_focus(login.username_input).ok and login.username_input.has_focus(), "Packed login uses the actual text-input adapter")
	check(platform.context.text_input.check_submission([login.username_input, login.password_input]).ok, "Packed native controls support the submission guard")
	check(platform.context.capabilities().exit_application and platform.context.system_actions.is_inside_tree(), "Packed project owns its native system-actions adapter")
	check(platform.context.runtime_config.connection_options().value.editable and platform.context.runtime_config.allows_remembered_login(), "Packed native policy retains address selection and opt-in remembering")
	check(platform.context.runtime_config.check_network_target("https://game.example.com/ssjx").ok, "Packed native target policy leaves HTTPS validation with the account client")
	var web_config = load("res://scripts/interface/adapters/web/web_runtime_config.gd").new()
	check(not web_config.connection_options().ok and not web_config.allows_remembered_login(), "Packed Web config cannot silently use native config or credential storage")
	var profile = load("res://scripts/interface/profiles/web_runtime.tres")
	check(profile.api_prefix == "" and not profile.allow_loopback_http, "Packed public build profile has safe root/HTTPS defaults")
	check(load("res://scripts/interface/platform_factory.gd").create("web") == null, "Native process cannot impersonate the browser runtime")
	check(FileAccess.file_exists("res://scripts/interface/adapters/web/indexeddb_storage.js"), "Trusted JS storage module is included as a raw packaged file")
	var web_storage = load("res://scripts/interface/adapters/web/web_storage.gd").new()
	var web_initialization = await web_storage.initialize().wait()
	check(not web_initialization.ok and web_storage.status().retention == "unknown", "Packed Web storage cannot silently inherit native guarantees")
	check(web_config.local_path("save").value == "offline://save-v1" and not web_config.local_path("save", "user://override.json").ok, "Packed Web configuration pins the logical slot")
	web_storage.close()
	scene._close_modal()
	scene.queue_free()
	await process_frame
	print("GAME EXPORT: %d checks, 0 failures" % checks)
	quit()
