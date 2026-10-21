extends "res://tests/shared_interface_test.gd"

class RejectWrites extends "res://scripts/interface/adapters/native/native_storage.gd":
	func write(_path: String, _text: String) -> PlatformStorageRequest:
		return PlatformStorageRequest.resolved(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "WRITE_FAILED", "测试写入失败"))

var deletions: Array = []

func _run() -> void:
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	var storage := Platform.context.storage
	Game.save_path = "user://character_deletion_%d.json" % OS.get_process_id()
	Game.new_player("原角色", 1, SchoolRules.UNJOINED)
	Game.player.gold = 91
	check((await Game.save_game()).ok, "Write isolated legacy save")
	check((await Game.create_local_character("第二角色", 2, 3, 1)).ok, "Add independent character")
	var second := Game.active_local_character_id()
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	app._local_character_selection()
	var page: OriginalCharacterSelection = app.character_selection
	var snapshot := FileAccess.get_file_as_string(Game.save_path)
	page._ask_delete()
	check(page.get_node("DeleteConfirmation").visible and page.get_node("DeleteConfirmation/Panel/Description").text.contains("第二角色（1级）"), "Confirmation names selected role and level")
	page.step(1)
	page._enter()
	check(page.characters[page.selected_index].id == second and app.mode == "local_select", "Confirmation blocks role switching and entering")
	page._cancel_delete()
	check(Game.local_characters().size() == 2 and FileAccess.get_file_as_string(Game.save_path) == snapshot, "Cancel preserves roster and bytes")
	page._ask_delete()
	page._confirm_delete()
	check(Game.local_characters().size() == 1 and Game.active_local_character_id() == "legacy" and Game.player.gold == 91, "UI deletes selected role and preserves surviving progress")
	check(app.character_selection.characters.size() == 1 and not app.character_selection.get_node("Options/Create").disabled, "Selection refreshes and releases slot")
	Game.player = {}
	check((await Game.load_game()).ok and Game.local_characters().size() == 1 and Game.player.name == "原角色", "Deletion persists after reload")
	snapshot = FileAccess.get_file_as_string(Game.save_path)
	check((await Game.delete_local_character("legacy", "错误名字")).code == "CHARACTER_NOT_FOUND" and FileAccess.get_file_as_string(Game.save_path) == snapshot, "Stale confirmation cannot delete another role")
	Platform.context._storage = RejectWrites.new()
	var before := Game.player.duplicate(true)
	check(not (await Game.delete_local_character("legacy", "原角色")).ok and Game.player == before and FileAccess.get_file_as_string(Game.save_path) == snapshot, "Failed write rolls back deletion")
	Platform.context._storage = storage
	check((await Game.delete_local_character("legacy", "原角色")).ok and Game.local_characters().is_empty(), "Last role can be deleted")
	Game.player = {}
	check((await Game.load_game()).ok and Game.local_characters().is_empty(), "Empty persisted roster cannot become a legacy role")
	app._local_character_selection()
	page = app.character_selection
	check(page.enter_button.disabled and page.get_node("Options/Delete").disabled and not page.get_node("Options/Create").disabled and page.status.text.contains("尚无"), "Empty roster offers creation only")
	check((await Game.create_local_character("重建角色", 0, 3, 0)).ok and Game.local_characters().size() == 1, "Create works again after deleting last role")
	var fresh := Game.active_local_character_id()
	check((await Game.create_local_character("保留角色", 1, 3, 0)).ok, "Create another active role")
	var active := Game.active_local_character_id()
	check((await Game.delete_local_character(fresh, "重建角色")).ok and Game.active_local_character_id() == active, "Deleting inactive role keeps current role")
	app._local_character_selection()
	page = app.character_selection
	page._ask_delete()
	output = OS.get_environment("SSJX_DELETE_CAPTURE") if DisplayServer.get_name() != "headless" else ""
	await capture("character_delete_confirmation")
	page._cancel_delete()
	app.free()
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = old_player
	# Validate transport receipts without issuing real requests or touching credentials.
	var account_client: Node = load("res://scripts/network/online_account.gd").new()
	add_child(account_client)
	account_client.set_process(false)
	account_client.characters = [{"id": SELF}, {"id": PEER}]
	account_client.pending_deletion = {"operation_id": EPOCH, "character_id": SELF, "character_name": "测试角色"}
	account_client._action = "character_delete"
	var bad := {"operation_id": EPOCH, "character_id": PEER, "deleted": true, "replayed": false}
	account_client._on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(bad).to_utf8_buffer(), 0)
	check(account_client.characters.size() == 2 and not account_client.pending_deletion.is_empty(), "Mismatched server receipt cannot delete cached role")
	account_client._action = "character_delete"
	bad.character_id = SELF
	account_client._on_response(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(bad).to_utf8_buffer(), 0)
	check(account_client.characters == [{"id": PEER}] and account_client.pending_deletion.is_empty(), "Confirmed receipt removes only exact role")
	account_client.clear()
	account_client.free()
	print("CHARACTER DELETION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
