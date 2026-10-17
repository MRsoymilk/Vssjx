extends Node
var checks := 0
var failures := 0
var view: OnlineWorldView
func _ready() -> void: call_deferred("_run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + text)
func wait_until(predicate: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()
func press_action(name_value: String) -> bool:
	for child in view.backpack.item_menu.get_children():
		if child is Button and child.text == name_value:
			child.pressed.emit()
			return true
	return false
func _run() -> void:
	var local := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_GEAR_TEST_BASE"), "gear_ui", OS.get_environment("SSJX_GEAR_TEST_PASSWORD"))
	await OnlineAccount.completed
	OnlineAccount.list_characters()
	await OnlineAccount.completed
	check(not OnlineAccount.characters.is_empty(), "Owned test account has character")
	if OnlineAccount.characters.is_empty(): get_tree().quit(1); return
	view = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = OnlineAccount.characters[0].id
	add_child(view)
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready), "Equipment capability synchronized")
	view._scene_action("bag")
	check(view.backpack != null and view.backpack.online_model == view.network.pve, "Online bag uses original inventory with server model")
	check(not view.backpack.equipment_icon.visible and view.backpack.items.size() == 2, "Unequipped sword occupies backpack slot")
	view.backpack.select_item(1)
	view.backpack.open_menu()
	check(press_action("装备"), "Item menu exposes Equip")
	check(view.network.pve.pending(), "Equip waits for server confirmation")
	check(not view.backpack.equipment_icon.visible and int(view.network.pve.state.stats.attack) == 18, "No optimistic equipment or attack bonus before server confirmation")
	check(not view.network.pve.submit("equip", "sword"), "Double submit cannot duplicate operation")
	check(await wait_until(func() -> bool: return not view.network.pve.pending() and view.network.pve.state.equipment.weapon == "sword"), "Server confirms equip")
	check(view.backpack.equipment_icon.visible and view.backpack.items.size() == 1, "Equipped sword moves from bag into weapon slot")
	check(int(view.network.pve.state.stats.attack) == 23, "Attack bonus comes from server")
	check(Game.player == local, "Equip does not modify offline character")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := OS.get_environment("SSJX_GEAR_CAPTURE")
		if not path.is_empty(): get_viewport().get_texture().get_image().save_png(path)
	view.backpack.get_node("Back").pressed.emit()
	check(view.backpack == null, "Back closes online backpack")
	var epoch := view.network.connection_epoch
	var ownership := view.network.world_epoch
	view.network.socket.close()
	check(await wait_until(func() -> bool: return view.network.pve.ready and view.network.world_ready and (view.network.connection_epoch != epoch or view.network.world_epoch != ownership)), "Real reconnect restores equipped state")
	view._scene_action("bag")
	check(view.backpack.equipment_icon.visible, "Reopened backpack shows durable equipment")
	view.backpack.get_node("Equipment0").pressed.emit()
	check(press_action("卸下"), "Weapon slot menu exposes Unequip")
	check(await wait_until(func() -> bool: return not view.network.pve.pending() and view.network.pve.state.equipment.weapon == null), "Server confirms unequip")
	check(not view.backpack.equipment_icon.visible and view.backpack.items.size() == 2 and int(view.network.pve.state.stats.attack) == 18, "Unequip restores bag and base attack")
	view.backpack.buy_potion()
	view.backpack.confirm_discard()
	view.backpack.use_item()
	check(Game.player == local and not view.network.pve.pending(), "Offline-only actions cannot mutate local save from online bag")
	view._close_inventory()
	view.network.leave()
	view.queue_free()
	await get_tree().process_frame
	print("ONLINE EQUIPMENT UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
