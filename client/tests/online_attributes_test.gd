extends "res://tests/online_pve_test.gd"

func _run() -> void:
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_characters := OnlineAccount.characters.duplicate(true)
	Game.new_player("离线旧角色", 2, 1, 1)
	Game.player.level = 5
	Game.player.gold = 986
	Game.player.hp = 41
	Game.player.signature = "仅存在于本地"
	Game.save_path = "user://online_attributes_%d.json" % OS.get_process_id()
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("offline-sentinel")
	var offline := Game.player.duplicate(true)
	var state := pve_state()
	OnlineAccount.characters = [state.character.duplicate(true)]
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.pve.bind_character(SELF,"http://127.0.0.1:9999")
	view.network.entities = {SELF:entity(SELF,1,"昆仑客",1,0,[10,16])}
	view.network.changed.emit(view.network.entities)
	check(view.network.pve.receive({"type":"pve.state","state":state}), "Validated server character snapshot reaches the UI")
	view.screen.chrome.get_node("Properties").pressed.emit()
	var page := view.attributes
	check(page.visible and page.online_mode and not view.details.visible and page.scene_file_path == "res://scenes/ui/character_attributes.tscn", "Header plus opens the original local attributes layout in online mode")
	check(page.snapshot.name == "昆仑客" and page.content.get_node("NameValue").text == "昆仑客" and page.content.get_node("SchoolValue").text == "昆仑派", "Name and school come from the server character")
	check(page.preview is AnimatedSprite2D and page.preview.sprite_frames == OriginalArt.cached["hero/mck"], "Online preview uses the server's avatar, not the offline avatar")
	check(page.numbers.hp.value == "95/95" and page.numbers.mp.value == "45/45" and page.numbers.gold.value == "30", "Original bitmap values display server health, mana and wallet")
	check(page.numbers.xp.value == "0/40" and page.bars.hp.value == 95 and page.bars.mp.max_value == 45, "Original progress bars use server maxima and level threshold")
	check(not page.signature.editable and page.get_node("EditSignature").disabled and page.signature.text.is_empty(), "Online signature cannot read or overwrite local signature")
	for key in ["ingots","guild_contribution","essence"]:
		check(page.numbers[key].value.is_empty() and page.content.get_node("Unavailable" + key.to_pascal_case()).visible, "Unavailable online balances display a dash instead of offline values")
	var timer := view._key_timer
	view._process(.25)
	check(view._key_timer == timer, "Attribute page prevents map keyboard movement")
	page.signature.text_changed.emit("不能写入本地")
	check(Game.player == offline and FileAccess.get_file_as_string(Game.save_path) == "offline-sentinel", "Online attribute callbacks preserve local character and save")
	output = OS.get_environment("SSJX_ATTRIBUTES_CAPTURE_PATH")
	await capture("online_attributes_regular")
	page.get_node("TabButtons1").pressed.emit()
	check(page.selected_tab == 1 and page.content.get_node("StatValue5").text == "28" and page.content.get_node("StatValue11").text == "4", "Extended tab uses server attack and defense")
	await capture("online_attributes_extended")
	var updated := pve_state(2)
	updated.character.level = 2
	updated.character.hp = 107
	updated.character.mp = 49
	updated.character.gold = 57
	updated.character.xp = 8
	updated.stats = {"hp":113,"mp":53,"attack":32,"defense":6}
	check(view.network.pve.receive({"type":"pve.state","state":updated}), "New authoritative stats accepted while page remains open")
	check(page.visible and page.selected_tab == 1 and page.content.get_node("StatValue5").text == "32" and page.content.get_node("StatValue11").text == "6", "Live update preserves selected tab and refreshes its values")
	page.select_tab(0)
	check(page.numbers.hp.value == "107/113" and page.numbers.mp.value == "49/53" and page.numbers.xp.value == "8/80" and page.numbers.gold.value == "57", "Level and wallet changes refresh the original regular tab")
	page.display_online(updated.character,{})
	check(page.numbers.hp.value == "107" and not page.bars.hp.visible, "Missing server maxima never fall back to offline stats")
	page.select_tab(1)
	check(page.content.get_node("StatValue5").text == "—" and page.content.get_node("StatValue11").text == "—", "Unknown extended stats remain blank until synchronized")
	page.display_online(updated.character,updated.stats)
	page.get_node("TabButtons2").pressed.emit()
	check(page.selected_tab == 2 and page.content.get_node("SkillName").text == "御剑诀", "Original skill tab matches the online job")
	await capture("online_attributes_skills")
	page.get_node("TabButtons3").pressed.emit()
	check(page.selected_tab == 3 and page.content.get_node("Label0").text.contains("心法"), "Original inner practice tab remains accessible")
	await capture("online_attributes_inner")
	page.get_node("Back").pressed.emit()
	check(not page.visible and view.network.world_ready and view.battle_view.is_processing_unhandled_key_input(), "Back returns to the same online map without leaving the session")
	view._scene_action("menu")
	view.menu.get_node("Panel/Rows/Properties").pressed.emit()
	check(page.visible and not view.menu.visible, "People entry opens the same original attributes page")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	view._unhandled_key_input(escape)
	check(not page.visible, "Escape returns from attributes to the online map")
	var shortcut := InputEventKey.new()
	shortcut.pressed = true
	shortcut.keycode = KEY_C
	view._unhandled_key_input(shortcut)
	check(page.visible, "C shortcut matches local attributes entry")
	page.get_node("Back").pressed.emit()
	view._open_expanded_chat()
	view._scene_action("properties")
	check(page.visible and not view.expanded_chat.visible, "Attributes close expanded chat instead of overlapping it")
	page.get_node("Back").pressed.emit()
	var local_page: OriginalCharacterAttributes = load("res://scenes/ui/character_attributes.tscn").instantiate()
	add_child(local_page)
	check(not local_page.online_mode and local_page.signature.editable and local_page.snapshot.name == offline.name, "Local attributes keep editable signature and their original data source")
	local_page.signature.text_changed.emit("本地仍可编辑")
	check(Game.player.signature == "本地仍可编辑", "Local signature behavior is preserved")
	local_page.queue_free()
	Game.player = offline.duplicate(true)
	check(FileAccess.get_file_as_string(Game.save_path) == "offline-sentinel", "Online navigation never writes the offline save")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = old_player
	OnlineAccount.characters = old_characters
	print("ONLINE ATTRIBUTES: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
