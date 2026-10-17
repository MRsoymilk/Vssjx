extends Node
const RULES = preload("res://scripts/character_attribute_rules.gd")
const DELAYED = preload("res://tests/fixtures/delayed_storage.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("UNIFIED ATTRIBUTES: " + message)

func _allocate(points: Array, results: Array) -> void:
	results.append(await Game.allocate_attributes(points))

func capture(name: String) -> void:
	var output := OS.get_environment("SSJX_ATTRIBUTES_CAPTURE_PATH")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(output)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func _run() -> void:
	await Platform.when_ready()
	var old := Game.player.duplicate(true)
	var old_path := Game.save_path
	var original := Platform.context
	var old_pending := OnlineAccount.pending_pve.duplicate(true)
	Game.save_path = "user://unified_attributes_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	var owned_path := Game.save_path
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/attribute_vectors.json"))
	for c in cases:
		var stats := RULES.stats(int(c.job),int(c.level),bool(c.equipped),c.allocated)
		var same_stats := true
		for key in stats: same_stats = same_stats and stats[key] == int(c.stats[key])
		check(same_stats,"Local combat numbers match independent server vectors")
		var profile := RULES.profile(int(c.job),int(c.level),bool(c.equipped),c.allocated)
		var same_plan: bool = profile.available == int(c.available)
		for i in 5: same_plan = same_plan and profile.recommended[i] == int(c.recommended[i])
		check(same_plan,"Budget and recommendation match server vectors")
		check(profile.combat.physical_attack == c.physical_attack and profile.combat.magic_attack == c.magic_attack,"Both attack types match server vectors")
	Game.new_player("共用属性",1,2)
	Game.player.equipped = true
	Game.player.hp -= 5
	var before := Game.player.duplicate(true)
	var legacy := before.duplicate(true)
	legacy.erase("allocated_attributes")
	check(Game.valid_save(legacy),"Legacy saves without allocation remain valid")
	var file := FileAccess.open(owned_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy));file.close()
	check((await Game.load_game()).ok and Game.attribute_profile().allocated == [0,0,0,0,0],"Legacy load treats missing points as unspent without changing combat")
	var before_ui := Game.player.duplicate(true)
	var local: OriginalCharacterAttributes = load("res://scenes/ui/character_attributes.tscn").instantiate()
	add_child(local)
	var online: OriginalCharacterAttributes = load("res://scenes/ui/character_attributes.tscn").instantiate()
	online.online_mode = true
	add_child(online);online.hide()
	var character := Game.player.duplicate(true)
	character.id = "a4b1a50c-fb82-49c9-adfb-a1ecb37ed210"
	character.display_name = Game.player.name
	character.state_revision = "1"
	online.display_online(character,Game.stats(),Game.attribute_profile())
	online.set_allocation_enabled(true)
	for tab in 4:
		local.select_tab(tab);online.select_tab(tab)
		check(local.content.scene_file_path == online.content.scene_file_path,"Both modes share the authored page: " + str(tab))
	local.select_tab(1);online.select_tab(1)
	for key in Game.attribute_profile().combat:
		check(local.content.get_node("Value_"+key).value == online.content.get_node("Value_"+key).value,"Shared combat field: " + key)
	check(local.signature.editable and not online.signature.editable,"Unified layout preserves local signature editing and online isolation")
	local._adjust_allocation(2,1)
	check(local.content.get_node("Remaining").text == "4" and Game.player == before_ui,"Local draft does not change saved state or combat")
	local.select_tab(0);local.select_tab(1)
	check(local.allocation_draft == [0,0,1,0,0],"Local tab changes retain the draft")
	local._recommend_allocation()
	check(local.allocation_draft == [1,0,3,1,0] and local.content.get_node("Status").text.contains("本地"),"Same recommendation controls explain local persistence")
	await capture("local_extended_draft")
	local.hide();online.show();online._recommend_allocation()
	await capture("online_extended_draft")
	local.queue_free();online.queue_free();await get_tree().process_frame
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app);app._enter_world();app._attributes()
	var page: OriginalCharacterAttributes = app.attributes
	page.select_tab(1);page._recommend_allocation();page._confirm_allocation()
	await get_tree().process_frame
	check(Game.allocated_attributes() == [1,0,3,1,0] and page.content.get_node("Remaining").text == "0","Real local properties entry confirms and persists allocation")
	check(Game.stats().attack == 35 and Game.stats().hp == 109 and Game.player.hp == 104,"Allocation affects real combat while preserving lost HP")
	check(page.content.get_node("Minus2").disabled and page.content.get_node("Confirm").disabled,"Saved allocation cannot be reduced or double-confirmed")
	check((await Game.load_game()).ok and Game.allocated_attributes() == [1,0,3,1,0],"Confirmed points survive actual save reload")
	page.display_local();page.select_tab(1)
	await capture("local_extended_saved")
	check(not (await Game.allocate_attributes([0,0,3,1,0])).ok,"Local committed points cannot be refunded")
	check(not (await Game.allocate_attributes([2,0,3,1,0])).ok,"Local budget cannot be exceeded")
	for invalid in [[1,0,3,1],[-1,0,3,1,0],[1.5,0,2.5,1,0],[true,0,3,1,0],[INF,0,3,1,0]]:
		var bad := Game.player.duplicate(true);bad.allocated_attributes = invalid
		check(not Game.valid_save(bad),"Malformed local allocation is rejected")
	app.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(owned_path)
	check((await Game.create_local_character("本地甲",1,0,0)).ok,"Create owned roster entry A")
	var first_id := Game.active_local_character_id()
	check((await Game.allocate_attributes([1,0,3,1,0])).ok,"Allocate entry A")
	check((await Game.create_local_character("本地乙",2,1,1)).ok and Game.allocated_attributes() == [0,0,0,0,0],"Other local characters retain independent points")
	check((await Game.select_local_character(first_id)).ok and Game.allocated_attributes() == [1,0,3,1,0],"Switching back restores the correct allocation")
	Game.add_rewards(0,40)
	check(Game.attribute_profile().available == 5,"Leveling grants exactly five more points")
	check((await Game.save_game()).ok,"Save owned level-up fixture")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app);app._enter_world();app._attributes()
	page = app.attributes;page.select_tab(1);page._adjust_allocation(0,1)
	var storage := DELAYED.new()
	Platform.context = PlatformContext.new("local-attributes-test",storage,original.runtime_config,original.display,original.lifecycle,original.resource_loader,original.text_input,original.system_actions)
	var before_failure := Game.player.duplicate(true)
	page._confirm_allocation()
	check(Game.storage_busy and storage.operations.size() == 1 and page.content.get_node("Confirm").disabled,"Async save blocks repeated confirmation")
	page._confirm_allocation()
	check(storage.operations.size() == 1,"Double-click does not queue another write")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","持久化失败"))
	check(not Game.storage_busy and Game.player == before_failure and page.allocation_draft == [2,0,3,1,0],"Failed write rolls back memory while preserving draft")
	check(page.content.get_node("Status").text.contains("保存未确认") and not page.content.get_node("Confirm").disabled,"Failed local save remains retryable")
	page._confirm_allocation()
	storage.complete(PlatformResult.success({"written":true,"durability":"browser_sync"}))
	check(Game.allocated_attributes() == [2,0,3,1,0] and page.content.get_node("Points0").text == "2","Confirmed async receipt updates both state and shared page")
	var results: Array = []
	_allocate([3,0,3,1,0],results)
	Game.new_player("切换后的角色",0,0)
	storage.complete(PlatformResult.success({"written":true,"durability":"native_file"}))
	check(results.size() == 1 and results[0].status == PlatformResult.Status.CANCELLED and Game.player.name == "切换后的角色" and Game.allocated_attributes() == [0,0,0,0,0],"Stale allocation completion cannot overwrite a replacement character")
	check(OnlineAccount.pending_pve == old_pending,"Local allocation never submits an online operation")
	Platform.context = original
	app.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(owned_path)
	Game.player = old;Game.save_path = old_path
	print("UNIFIED ATTRIBUTES: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
