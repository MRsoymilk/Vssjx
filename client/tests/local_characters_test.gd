extends Node
class RejectWrites extends "res://scripts/interface/adapters/native/native_storage.gd":
	func write(_path: String, _text: String) -> PlatformStorageRequest:
		return PlatformStorageRequest.resolved(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "WRITE_FAILED", "测试写入失败"))

var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LOCAL CHARACTERS FAIL: " + message)
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var original := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_storage := Platform.context.storage
	Game.save_path = "user://local_characters_%d.json" % OS.get_process_id()
	Game.new_player("旧存档修士", 1, 2, 1)
	Game.player.gold = 91
	Game.player.quest = 3
	Game.player.kills = 3
	Game.player.potions = 2
	Game.player.equipped = true
	Game.player.signature = "旧角色签名"
	check((await Game.save_game()).ok, "Legacy single-character save is written")
	var legacy := FileAccess.get_file_as_string(Game.save_path)
	check(not JSON.parse_string(legacy).has("local_characters"), "Legacy v1 remains readable without eager conversion")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	app._enter_local_game()
	check(app.character_selection.characters.size() == 1 and not app.character_selection.get_node("Options/Create").disabled, "Existing local character can open another creation")
	app.character_selection.get_node("Options/Create").pressed.emit()
	app.nickname.text = "第二位修士"
	app.selected_job = 2
	app._start_new()
	check(app.mode == "local_select" and app.character_selection.characters.size() == 2 and app.modal == null, "Creation adds a second slot instead of requesting overwrite")
	check(app.character_selection.get_node("Details/Name").text == "第二位修士", "New local character is selected in the shared carousel")
	var second_id := Game.active_local_character_id()
	var entries := Game.local_character_entries()
	check(entries[0].id == "legacy" and entries[0].data.gold == 91 and entries[0].data.potions == 2 and entries[0].data.equipped, "Migration retains old gold, inventory and equipment")
	check(entries[0].data.quest == 3 and entries[0].data.signature == "旧角色签名", "Migration retains old quest and signature")
	var snapshot := FileAccess.get_file_as_string(Game.save_path)
	var result := await Game.create_local_character("第二位修士", 0, 0, 0)
	check(result.code == "NAME_TAKEN" and FileAccess.get_file_as_string(Game.save_path) == snapshot, "Duplicate names cannot accidentally duplicate an uncertain creation")
	for index in 3:
		result = await Game.create_local_character("新增修士%d" % index, index, index, index % 2)
		check(result.ok and Game.local_characters().size() == index + 3, "Additional local characters have independent saved slots")
	app._local_character_selection()
	check(app.character_selection.characters.size() == 5 and app.character_selection.get_node("Options/Create").disabled, "Full local roster disables the create menu")
	var capture := OS.get_environment("SSJX_LOCAL_CHARACTERS_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(capture) == OK, "Five-character local carousel is rendered")
	snapshot = FileAccess.get_file_as_string(Game.save_path)
	result = await Game.create_local_character("第六位修士", 0, 0, 0)
	check(result.code == "CHARACTER_LIMIT_REACHED" and FileAccess.get_file_as_string(Game.save_path) == snapshot, "Direct calls cannot exceed five slots or overwrite saves")
	app.character_selection.step(1) # Fifth -> first.
	check(app.character_selection.characters[app.character_selection.selected_index].id == "legacy", "Five-dot carousel wraps to the original character")
	app.character_selection.enter_button.pressed.emit()
	check(app.mode == "world" and Game.player.name == "旧存档修士" and Game.player.gold == 91 and Game.player.quest == 3, "Entering uses the selected original character's own progress")
	Game.player.gold = 107
	Game.player.quest = 4
	Game.player.potions = 1
	check((await Game.save_game()).ok, "Gameplay saves update the active local slot")
	app._enter_local_game()
	app.character_selection.select_index(1)
	app.character_selection.enter_button.pressed.emit()
	check(Game.active_local_character_id() == second_id and Game.player.name == "第二位修士" and Game.player.gold == 30 and Game.player.quest == 0 and Game.player.potions == 6, "Switching preserves the second character's own gold, quest and inventory")
	check(Game.player.job == 2 and not Game.player.equipped, "Character class and equipment also remain independent")
	Game.player = {}
	check((await Game.load_game()).ok and Game.active_local_character_id() == second_id and Game.local_characters().size() == 5, "Reload restores all slots and last selection from one atomic save")
	check(Game.local_character_entries()[0].data.gold == 107 and Game.local_character_entries()[0].data.quest == 4, "Inactive original progress survives reload")
	var current := Game.player.duplicate(true)
	snapshot = FileAccess.get_file_as_string(Game.save_path)
	Platform.context._storage = RejectWrites.new()
	result = await Game.select_local_character("legacy")
	check(not result.ok and Game.player == current and FileAccess.get_file_as_string(Game.save_path) == snapshot, "Failed selection persistence preserves current player and original file")
	Platform.context._storage = old_storage
	for kind in ["duplicate", "missing", "nested", "mismatch"]:
		var corrupt: Dictionary = JSON.parse_string(snapshot)
		match kind:
			"duplicate": corrupt.local_characters.characters[1].id = corrupt.local_characters.characters[0].id
			"missing": corrupt.local_characters.active_id = "00000000000000000000000000000000"
			"nested": corrupt.local_characters.characters[0].data.local_characters = {}
			"mismatch": corrupt.name = "被串改的角色"
		var raw := JSON.stringify(corrupt)
		FileAccess.open(Game.save_path, FileAccess.WRITE).store_string(raw)
		result = await Game.load_game()
		check(result.code == "INVALID_SAVE" and Game.player == current and FileAccess.get_file_as_string(Game.save_path) == raw, "Corrupt roster is rejected without replacing player or file: " + kind)
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string(legacy)
	check((await Game.load_game()).ok, "Original legacy save is still supported")
	current = Game.player.duplicate(true)
	Platform.context._storage = RejectWrites.new()
	result = await Game.create_local_character("失败创建", 0, 0, 0)
	check(not result.ok and Game.player == current and FileAccess.get_file_as_string(Game.save_path) == legacy, "Failed additional creation rolls back without replacing the old character")
	Platform.context._storage = old_storage
	app.free()
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = original
	print("LOCAL CHARACTERS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
