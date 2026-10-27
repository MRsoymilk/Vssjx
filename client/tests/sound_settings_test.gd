extends "res://tests/shared_interface_test.gd"
## Isolated device preferences, actual local/online menus, no player database.

func _run() -> void:
	await Platform.when_ready()
	await Game.when_ready()
	OnlineAccount.suspend_network()
	var config := Platform.context.runtime_config
	var previous_path: String = config.audio_settings_path
	var directory := "user://sound_settings_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_absolute(directory) == OK, "Owned preference directory")
	config.audio_settings_path = directory.path_join("audio.cfg")
	var old_player := Game.player.duplicate(true)
	var old_save := Game.save_path
	Game.save_path = directory.path_join("player.json")
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("player-save-sentinel")
	Game.new_player("声音设置测试", 1, 2)
	var before := Game.player.duplicate(true)
	var master := AudioServer.get_bus_index("Master")
	GameAudio.settings_initialized = false
	GameAudio.initialize_settings()
	check(GameAudio.sound_enabled and not AudioServer.is_bus_mute(master), "First launch enables sound by default")
	check(not FileAccess.file_exists(config.audio_settings_path), "Reading defaults does not create a preference or overwrite a save")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_world()
	app._menu()
	app.modal.get_node("Panel/Rows/System").pressed.emit()
	var local_settings: Control = app.modal.get_node("Panel/SoundSettings")
	check(local_settings.is_visible_in_tree() and local_settings.get_node("Toggle").text.contains("开启"), "Local menu routes to the sound switch")
	var music: AudioStreamPlayer = app.get_node("BackgroundMusic")
	music.seek(3)
	var sound := GameAudio.player("thunder")
	add_child(sound)
	sound.play()
	local_settings.get_node("Toggle").pressed.emit()
	check(not GameAudio.sound_enabled and AudioServer.is_bus_mute(master), "Switch immediately mutes the Master bus, including existing music and effects")
	check(music.playing and sound.playing and music.get_playback_position() >= 2.9, "Muting does not restart or stop active playback")
	check(music.bus == &"Master" and sound.bus == &"Master", "Both actual audio sources pass through the muted bus")
	check(music.volume_db == -18 and sound.volume_db == -6, "Sound switch preserves individual volume levels")
	var later_sound := GameAudio.player("fire")
	add_child(later_sound)
	later_sound.play()
	check(later_sound.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index(later_sound.bus)), "New skill sounds also stay muted")
	later_sound.stop()
	later_sound.queue_free()
	check(config.load_sound_enabled().value == false and GameAudio.settings_error.is_empty(), "Disabled flag is persisted separately")
	output = OS.get_environment("SSJX_SOUND_CAPTURE_PATH")
	await capture("local-muted")
	app._close_modal()
	app._system_menu()
	check(app.modal.get_node("Panel/SoundSettings/Toggle").text.begins_with("声音：关闭"), "Reopening settings preserves the displayed state")
	app._close_modal()
	# Recreate controller state and config reader, as on a subsequent application launch.
	var fresh = preload("res://scripts/interface/adapters/native/native_runtime_config.gd").new()
	fresh.audio_settings_path = config.audio_settings_path
	check(fresh.load_sound_enabled().value == false, "A fresh native reader restores the saved disabled flag")
	GameAudio.sound_enabled = true
	GameAudio.settings_initialized = false
	AudioServer.set_bus_mute(master, false)
	GameAudio.initialize_settings()
	check(not GameAudio.sound_enabled and AudioServer.is_bus_mute(master), "Startup reapplies saved mute before music begins")
	OnlineAccount.characters = [{"id": SELF, "display_name": "声音设置测试", "job": 1, "gender": 0, "school": 2, "level": 1, "hp": 95, "mp": 45, "gold": 30}]
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view._scene_action("menu")
	view.menu.get_node("Panel/Rows/System").pressed.emit()
	var online_settings: Control = view.get_node("Menu/Panel/SoundSettings")
	check(view.details.visible and online_settings.is_visible_in_tree(), "Online System menu exposes the same switch")
	check(online_settings.get_node("Toggle").text.begins_with("声音：关闭"), "Online state follows the device preference, not a character snapshot")
	online_settings.get_node("Toggle").pressed.emit()
	check(GameAudio.sound_enabled and not AudioServer.is_bus_mute(master) and fresh.load_sound_enabled().value == true, "Online switch restores all sound and persists it")
	check(music.playing and music.get_playback_position() >= 2.9, "Unmuting continues music without restarting")
	await capture("online-enabled")
	view.details.hide()
	view._scene_action("mail")
	check(not online_settings.visible, "Unrelated online details never show or overlap sound settings")
	view._scene_action("system")
	config.audio_settings_path = directory.path_join("missing/audio.cfg")
	online_settings.get_node("Toggle").pressed.emit()
	check(AudioServer.is_bus_mute(master) and not GameAudio.settings_error.is_empty(), "Failed storage cannot prevent immediate muting")
	check(online_settings.get_node("Status").text.contains("未能保存"), "UI explicitly reports unpersisted changes")
	await capture("save-failed")
	config.audio_settings_path = fresh.audio_settings_path
	GameAudio.set_sound_enabled(true)
	check(GameAudio.settings_error.is_empty(), "Successful retry clears the storage error")
	FileAccess.open(config.audio_settings_path, FileAccess.WRITE).store_string("not a valid config [")
	GameAudio.settings_initialized = false
	GameAudio.initialize_settings()
	check(GameAudio.sound_enabled and not GameAudio.settings_error.is_empty(), "Corrupt preferences fall back safely and report an error")
	FileAccess.open(config.audio_settings_path, FileAccess.WRITE).store_string('[audio]\nenabled="false"\n')
	check(not fresh.load_sound_enabled().ok, "Wrong-typed preference is not coerced to a boolean")
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == "player-save-sentinel", "Both menus preserve offline assets and save bytes")
	sound.stop()
	sound.queue_free()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	config.audio_settings_path = previous_path
	Game.save_path = old_save
	Game.player = old_player
	OnlineAccount.characters = []
	GameAudio.settings_initialized = false
	GameAudio.initialize_settings()
	OnlineAccount.resume_network()
	print("SOUND SETTINGS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
