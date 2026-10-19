extends "res://tests/online_pve_live_test.gd"

func _run() -> void:
	var old := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_ATTRIBUTES_BASE"), "attr_ui", OS.get_environment("SSJX_ATTRIBUTES_PASSWORD"))
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(), "Isolated allocation test account authenticated")
	OnlineAccount.list_characters()
	await OnlineAccount.completed
	if OnlineAccount.characters.is_empty(): get_tree().quit(1); return
	own_id = OnlineAccount.characters[0].id
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(own_id)
	view = app.ui.get_node("OnlineWorld")
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready), "Real connection supplies validated attribute state")
	if not view.network.pve.ready: get_tree().quit(1); return
	view.screen.chrome.get_node("Properties").pressed.emit()
	view.attributes.get_node("TabButtons1").pressed.emit()
	var page := view.attributes
	check(await wait_until(func() -> bool: return page.allocation_enabled), "Opening properties waits for movement acknowledgement")
	check(page.content.get_node("Remaining").text == "5", "New real character has five points")
	var before := view.network.pve.state.duplicate(true)
	page.content.get_node("Recommend").pressed.emit()
	check(page.allocation_draft == [1,0,1,3,0] and view.network.pve.state == before, "Recommend does not mutate authoritative state")
	page.content.get_node("Confirm").pressed.emit()
	var pending := OnlineAccount.pending_pve.duplicate(true)
	check(not pending.is_empty() and page.content.get_node("Confirm").disabled, "Confirmation starts one durable operation")
	var connection := view.network.connection_epoch
	var ownership := view.network.world_epoch
	# Simulate loss of a response immediately after sending the operation.
	view.network.socket.close()
	check(await wait_until(func() -> bool: return view.network.pve.ready and not view.network.pve.pending() and (view.network.connection_epoch != connection or view.network.world_epoch != ownership)), "Save with unknown result recovers through reconnect")
	check(view.network.pve.state.attributes.allocated == [1,0,1,3,0] and view.network.pve.state.attributes.available == 0, "Server applies one allocation and exhausts budget")
	check(int(view.network.pve.state.character.state_revision) == int(pending.command.expected_revision)+1, "Replayed confirmation increments revision only once")
	check(int(view.network.pve.state.stats.hp) == int(before.stats.hp)+8 and int(view.network.pve.state.stats.attack) == int(before.stats.attack)+2, "Saved points update actual authoritative combat values")
	check(page.content.get_node("Remaining").text == "0" and page.content.get_node("Points2").text == "1", "Open extension refreshes from saved state")
	page.get_node("Back").pressed.emit()
	view._scene_action("properties")
	page.select_tab(1)
	check(page.content.get_node("Points0").text == "1" and page.content.get_node("Minus0").disabled, "Reopening shows saved totals with no respec")
	check(Game.player == old, "Real online allocation preserves local progress")
	app.queue_free()
	await get_tree().process_frame
	OnlineAccount.clear()
	print("ONLINE ALLOCATION LIVE: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
