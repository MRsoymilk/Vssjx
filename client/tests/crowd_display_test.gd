extends "res://tests/ground_click_test.gd"

func _run() -> void:
	await Platform.when_ready(); await Game.when_ready()
	OnlineAccount.suspend_network()
	var old_player := Game.player.duplicate(true)
	var config := Platform.context.runtime_config
	var old_path: String = config.display_settings_path
	var path := "user://crowd_%d_%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	config.display_settings_path = path
	WorldDisplaySettings.initialized = false; WorldDisplaySettings.initialize()
	check(WorldDisplaySettings.mode == "normal", "Absent preferences default to normal")
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = SELF; add_child(view); view.set_process(false); view.network.set_process(false)
	view.network.world_ready = true; view.network.stream = EPOCH
	view.network.entities = {SELF:entity(SELF, 1, "自己", 1, 0, [10,16])}
	for i in 100:
		var id := "10000000-0000-4000-8000-%012d" % (i + 2)
		view.network.entities[id] = entity(id, i + 2, "玩家%d" % i, i % 3, i % 2, [9+i%3,14+i%2])
	view.network.team_marks = {PEER:{"leader":true}}
	view.team.state.team = {"members":[{"id":SELF}, {"id":PEER}]}
	view._snapshot(view.network.entities)
	var packet := residents_packet()
	view.network._receive(packet, JSON.stringify(packet).to_utf8_buffer())
	view.camera.force_update_scroll()
	output = OS.get_environment("SSJX_CROWD_CAPTURE") if DisplayServer.get_name() != "headless" else ""
	await capture("normal-100")
	check(view.actors.size() == 101 and view.residents.size() == 5, "Dense fixture contains 100 peers plus all residents")
	WorldDisplaySettings.set_mode("faded"); view._refresh_player_display()
	var other := "10000000-0000-4000-8000-000000000003"
	view.network.team_marks[other] = {"leader":true}
	check(view.actors[SELF].root.modulate.a == 1 and view.actors[PEER].root.modulate.a == 1, "Self and own teammate remain opaque")
	check(view.actors[other].root.visible and view.actors[other].root.modulate.a == 0.25, "Other players become translucent")
	var names: Control = view.image.get_node("WorldNameplates")
	names._process(0)
	var label: Label = view.actors[other].root.get_child(1)
	check(names.entries[label.get_instance_id()].proxy.modulate.a == 0.25, "High-resolution nameplates fade with their players")
	await capture("faded-100")
	view._select_player(other)
	WorldDisplaySettings.set_mode("hidden"); view._refresh_player_display(); names._process(0)
	check(not view.actors[other].root.visible and not view.actors[other].sprite.is_playing(), "Hidden players stop animation and render no sprites or flags")
	check(not names.entries[label.get_instance_id()].proxy.visible and view.target.selected.is_empty(), "Hidden nameplates and old selection are removed")
	check(view.actors[SELF].root.visible and view.actors[PEER].root.visible, "Self and teammates cannot be hidden")
	check(view.network.entities.size() == 101 and view.actors.size() == 101 and view.count_label.text == "同图101人", "Visibility never drops authoritative entities or changes population count")
	for resident in view.residents.values(): check(resident.visible and resident.z_index >= 8, "NPCs and monsters stay visible above player sprites")
	var point := view.scene.to_local(visible_point(view.residents.qingwei.sprite))
	var hits := view._targets_at(point)
	check(hits.any(func(hit:Dictionary)->bool:return hit.id == "qingwei") and not hits.any(func(hit:Dictionary)->bool:return hit.id == other), "Invisible players never capture NPC clicks")
	await capture("hidden-100")
	var fresh = preload("res://scripts/interface/adapters/native/native_runtime_config.gd").new()
	fresh.display_settings_path = path
	check(fresh.load_player_display().value == "hidden", "Fresh reader restores the last display choice")
	view.network.entities[other].cell = [14,16]; view.network.appearances[other] = [1,0]
	view._snapshot(view.network.entities)
	WorldDisplaySettings.set_mode("normal"); view._refresh_player_display(); view._process(0.01)
	check(view.actors[other].root.visible and view.actors[other].sprite.sprite_frames != null and view.actors[other].motion.position == view.actors[other].root.position, "Unhiding restores latest synchronized appearance and motion (walking frames are manually advanced)")
	view._open_target_list(view._targets_at(point))
	check(is_instance_valid(view.target_list) and view.target_list.rows.get_child_count() > 1, "Overlap opens explicit scrollable choices, not a random battle")
	view.target_list.search.text = "清微"; view.target_list._refresh()
	check(view.target_list.rows.get_child_count() == 1, "Crowded target search filters the list")
	await capture("overlap-choices")
	view.network.world_ready = false; view._status_changed("断线")
	check(view.target_list == null, "Disconnect clears stale target choices")
	config.display_settings_path = path + "/missing"
	check(not WorldDisplaySettings.set_mode("hidden").ok and WorldDisplaySettings.mode == "hidden", "Write failure still applies display mode for this session")
	check(not WorldDisplaySettings.set_mode("invalid").ok and WorldDisplaySettings.mode == "hidden", "Unknown modes are rejected")
	config.display_settings_path = path
	view.network.world_ready = true
	view._scene_action("system")
	var settings: Control = view.get_node("Menu/Panel/CrowdSettings")
	check(settings.is_visible_in_tree(), "Online System exposes the shared crowd preference")
	settings.get_node("Toggle").pressed.emit(); view._refresh_player_display()
	check(WorldDisplaySettings.mode == "normal" and fresh.load_player_display().value == "normal", "Actual button cycles hidden back to normal and saves")
	await capture("settings")
	view.details.hide(); view._scene_action("mail")
	check(not settings.visible, "Other online pages hide display controls")
	var local_menu: Control = load("res://scenes/ui/system_menu.tscn").instantiate(); add_child(local_menu)
	local_menu.get_node("Panel/CrowdSettings/Toggle").pressed.emit()
	check(WorldDisplaySettings.mode == "faded", "Local System uses the same device preference")
	local_menu.queue_free()
	FileAccess.open(path, FileAccess.WRITE).store_string('[display]\nplayers="bad"\n')
	check(not fresh.load_player_display().ok, "Invalid saved display values are rejected")
	check(Game.player == old_player, "Display changes never modify offline assets")
	view.queue_free(); await get_tree().process_frame
	DirAccess.remove_absolute(path)
	config.display_settings_path = old_path
	WorldDisplaySettings.initialized = false; WorldDisplaySettings.initialize()
	OnlineAccount.resume_network()
	print("CROWD DISPLAY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
