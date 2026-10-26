extends "res://tests/shared_interface_test.gd"

func drag_bar(bar: VScrollBar, forward: bool) -> void:
	bar.value = bar.min_value if forward else bar.max_value-bar.page
	await get_tree().process_frame
	var start := bar.value
	var point := bar.global_position + Vector2(2 if forward else bar.size.x-2, 14 if forward else bar.size.y-14)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.position = point; press.pressed = true
	get_viewport().push_input(press,true)
	var after_press := bar.value
	var move := InputEventMouseMotion.new()
	move.position = point + Vector2(0,30 if forward else -30)
	move.relative = Vector2(0,30 if forward else -30); move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move,true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT; release.position = move.position; release.pressed = false
	get_viewport().push_input(release,true)
	await get_tree().process_frame
	check(bar.value > start and bar.value > after_press if forward else bar.value < start and bar.value < after_press, "Widened scrollbar is draggable from its %s edge" % ("left" if forward else "right"))

func _run() -> void:
	await Game.when_ready()
	var old := Game.player.duplicate(true)
	var outbox := OnlineAccount.pending_pve.duplicate(true)
	Game.new_player("触屏滚动",0,3,0); Game.player.level = 60
	for i in 20: Game.player.loot_state.items.append(LootRules.roll("ai/eva01/mzs/weapon",60,"yellow",17+i))
	var before := Game.player.duplicate(true)
	var background := ColorRect.new(); background.size = Vector2(320,480); background.color = Color("224a39"); add_child(background)
	for online in [false,true]:
		var panel := LootPanel.new()
		if online:
			var model := OnlinePve.new(); model.ready = true
			model.state = {"character":{"job":0,"gender":0,"level":60,"corpse":null},"shop":ShopRules.local_state(Game.player),"loot":{"state":Game.player.loot_state.duplicate(true)},"potions":Game.player.potions,"stats":Game.stats()}
			panel.online_model = model
		add_child(panel)
		panel.list.select(1); panel.list.item_selected.emit(1)
		for frame in 3: await get_tree().process_frame
		var bars: Array[VScrollBar] = [panel.list.get_v_scroll_bar(),panel.detail_scroll.get_v_scroll_bar()]
		check(panel.rows.size() >= 20 and panel.details.text.contains("稀有"), "Production equipment list and long affix details are populated")
		for bar in bars:
			check(bar.visible and bar.size.x >= 24 and bar.get_combined_minimum_size().x >= 24, "List and details expose a genuinely wider touch target")
			for state in ["scroll","scroll_focus","grabber","grabber_highlight","grabber_pressed"]:
				check(bar.get_theme_stylebox(state).get_minimum_size().x >= 24, "Every scrollbar visual state keeps its full width")
			check(bar.get_theme_stylebox("grabber").get_minimum_size().y >= 28, "Short scrollbar thumb still has a usable minimum height")
			await drag_bar(bar,true); await drag_bar(bar,false)
		check(panel.details.position.x+panel.details.size.x <= bars[1].position.x, "Wrapped equipment text leaves space for the widened scrollbar")
		check(not panel.detail_scroll.get_h_scroll_bar().visible, "Widening does not introduce horizontal scrolling or obscure details")
		for bar in bars: bar.value = 0
		if not online:
			var path := OS.get_environment("SSJX_LOOT_SCROLLBAR_CAPTURE")
			if not path.is_empty() and DisplayServer.get_name() != "headless":
				await get_tree().process_frame; await RenderingServer.frame_post_draw
				check(get_viewport().get_texture().get_image().save_png(path) == OK, "Capture actual widened equipment list and details scrollbars")
		panel.show_builds()
		for frame in 2: await get_tree().process_frame
		check(panel.detail_scroll.get_v_scroll_bar().size.x >= 24 and panel.detail_scroll.size.y == 210, "Expanded build descriptions retain the wider scrollbar")
		panel._describe()
		check(panel.detail_scroll.size.y == 76 and panel.equip.position.y == 382, "Returning to equipment leaves action buttons in place")
		panel.queue_free(); await get_tree().process_frame
	check(Game.player == before and OnlineAccount.pending_pve == outbox, "Scrolling changes no equipment, save data or online command outbox")
	background.queue_free(); Game.player = old
	print("LOOT SCROLLBAR: %d checks, %d failures" % [checks,failures]); get_tree().quit(1 if failures else 0)
