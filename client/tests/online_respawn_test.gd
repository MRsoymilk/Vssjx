extends "res://tests/online_pve_test.gd"

func _run() -> void:
	await Game.when_ready()
	output = OS.get_environment("SSJX_RESPAWN_CAPTURE_PATH")
	var old := Game.player.duplicate(true)
	var old_characters := OnlineAccount.characters.duplicate(true)
	OnlineAccount.pending_pve = {}
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = SELF
	add_child(view)
	view.set_process(false)
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.stream = EPOCH
	view.network._pve_version = 1
	var model := view.network.pve
	model.bind_character(SELF, "http://127.0.0.1:9999")
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10,16])}
	view.network.changed.emit(view.network.entities)
	view.network.population.receive(residents_packet())
	var snapshot := pve_state(1, 1)
	# Deliberately unrelated to the client's wall clock.
	var clock := 1700000000000
	snapshot.server_time_ms = clock
	snapshot.progress = {"kills":1,"defeated":["wolf_a"],"respawns":{"wolf_a":clock + 80}}
	check(model.receive({"type":"pve.state","state":snapshot}), "Authoritative cooldown snapshot is accepted")
	check(not view.residents.has("wolf_a") and view.residents.size() == 4, "Victory hides only the defeated resident during its cooldown")
	check(view.screen.hud.get_node("Minimap").shared_population.size() == 4, "Minimap hides cooling-down monsters")
	await capture("cooldown")
	check(await wait_until(func() -> bool: return model.server_time_ms() >= clock + 80), "Presentation clock reaches the server deadline using real elapsed time")
	view._process(0.0)
	check(view.residents.has("wolf_a") and view.residents.size() == 5, "Expired monster automatically reappears without a new packet or user action")
	check(view.residents.wolf_a.data.hp == 62 and view.residents.wolf_a.sprite.is_playing(), "Respawn restores the full resident and native animation")
	check(view.screen.hud.get_node("Minimap").shared_population.size() == 5, "Respawn returns the monster's minimap dot")
	await capture("respawned")
	var returned: OnlineResident = view.residents.wolf_a
	view._process(0.0)
	check(view.residents.wolf_a == returned, "Further frames do not create duplicate monsters")
	view.resident_selected.emit("wolf_a")
	check(view._approach.get("target") == "wolf_a", "Respawned monster can be selected for a new challenge")
	view._cancel_approach()
	check(model.state.progress.kills == 1 and model.state.character.quest_stage == 1, "A visual respawn never resets task history")
	var before_clock := model.server_time_ms()
	check(model.receive({"type":"pve.result", "operation_id":PEER,"ok":true,"replayed":true,"lines":[],"state":snapshot}), "Delayed stored receipt is accepted")
	check(model.server_time_ms() >= before_clock and model.unavailable_monsters().is_empty(), "Replayed timestamp cannot rewind cooldowns or re-hide a respawned monster")
	var legacy := snapshot.duplicate(true)
	legacy.erase("server_time_ms")
	legacy.progress.erase("respawns")
	check(model.receive({"type":"pve.result","operation_id":PEER,"ok":true,"replayed":true,"lines":[],"state":legacy}) and model.state.progress.has("respawns") and model.unavailable_monsters().is_empty(), "Same-revision pre-upgrade receipt cannot erase current respawn metadata")
	var next := snapshot.duplicate(true)
	next.character.state_revision = "2"
	next.server_time_ms = model.server_time_ms()
	next.progress.respawns.wolf_a = int(next.server_time_ms) + 80
	check(model.receive({"type":"pve.state","state":next}) and not view.residents.has("wolf_a"), "Another victory starts its own fresh cooldown")
	model.disconnect_channel()
	check(await wait_until(func() -> bool: return model.server_time_ms() >= int(next.progress.respawns.wolf_a)), "Cooldown continues while disconnected")
	view._process(0.0)
	check(not view.residents.has("wolf_a"), "Disconnected client does not invent authoritative population changes")
	next.server_time_ms = model.server_time_ms()
	check(model.receive({"type":"pve.state","state":next}) and view.residents.has("wolf_a"), "Reconnection restores a monster whose durable deadline elapsed")
	var migrated := next.duplicate(true)
	migrated.progress.respawns = {}
	check(model.receive({"type":"pve.state","state":migrated}) and view.residents.size() == 5, "Old defeated history with no cooldown deadlines recovers after migration")
	var all := next.duplicate(true)
	all.character.state_revision = "3"
	all.character.quest_stage = 2
	all.server_time_ms = model.server_time_ms()
	all.progress = {"kills":3,"defeated":["wolf_a","wolf_b","wolf_c","spirit"],"respawns":{}}
	for index in 4: all.progress.respawns[all.progress.defeated[index]] = int(all.server_time_ms) + 80 * (index + 1)
	check(model.receive({"type":"pve.state","state":all}) and view.residents.size() == 1, "All four monsters can have independent cooldowns; NPC stays visible")
	check(await wait_until(func() -> bool: return model.server_time_ms() >= int(all.server_time_ms) + 80), "First independent cooldown reaches its boundary")
	view._process(0.0)
	check(view.residents.has("wolf_a") and not view.residents.has("spirit"), "The first monster returns without waiting for other cooldowns")
	view.menu.show()
	check(await wait_until(func() -> bool: return model.server_time_ms() >= int(all.server_time_ms) + 320), "Remaining independent cooldowns reach their boundaries")
	view._process(0.0)
	check(view.residents.size() == 5 and view.menu.visible, "All monsters refresh behind an open menu without closing it")
	view.menu.hide()
	check(model.receive({"type":"pve.result","operation_id":PEER,"ok":true,"replayed":true,"lines":[],"state":next}) and model.state.character.state_revision == "3" and model.unavailable_monsters().is_empty(), "An older receipt cannot roll the new population state backwards")
	for invalid in [null, [], {"qingwei":clock}, {"wolf_a":-1}, {"wolf_a":1.5}, {"wolf_a":"bad"}, {"wolf_a":int(next.server_time_ms) + 30001}, {"wolf_b":clock}]:
		var bad := next.duplicate(true)
		bad.progress.respawns = invalid
		check(not model.valid(bad), "Invalid respawn metadata is rejected: " + str(invalid))
	var no_clock := next.duplicate(true)
	no_clock.erase("server_time_ms")
	check(not model.valid(no_clock), "Cooldown metadata requires a validated server clock")
	check(Game.player == old, "Online cooldowns never mutate local character progress")
	view.queue_free()
	await get_tree().process_frame
	OnlineAccount.characters = old_characters
	print("ONLINE RESPAWN: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
