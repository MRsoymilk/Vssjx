extends "res://tests/chat_emotes_test.gd"

func settle() -> void:
	for _frame in 4: await get_tree().process_frame

func _run() -> void:
	output = OS.get_environment("SSJX_EXPANDED_CHAT_CAPTURE_PATH")
	var before := Game.player.duplicate(true)
	var before_characters := OnlineAccount.characters.duplicate(true)
	OnlineAccount.characters = [{"id": SELF, "display_name":"昆仑客","job":1,"gender":0,"school":2,"level":1,"hp":95,"mp":45}]
	var view := make_view(SELF)
	var expanded := view.expanded_chat
	var expand_button: Button = view.get_node("Screen/Chat/Expand")
	check(not expanded.visible and view.get_node("Screen/Chat/Expand").icon.resource_path == "res://assets/ui/chat_expand.svg", "Collapsed chat uses the supplied themed upward arrow")
	check(expanded.scene_file_path == "res://scenes/ui/expanded_chat_panel.tscn", "Expanded window is an authored scene")
	check(not expanded.has_node("Panel/Emotes") and not expanded.has_node("Panel/Return"), "Popup footer contains neither duplicate button; the shared arrow handles opening and closing")
	for corner_name in ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]:
		var corner: TextureRect = expanded.get_node("Panel/" + corner_name)
		check(corner.texture.resource_path == "res://assets/ui/chat_corner.png" and corner.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Original pixel corner is decorative and cannot intercept input: " + corner_name)
		check(not corner.get_global_rect().intersects(expanded.get_node("Panel/Tabs").get_global_rect()) and
			not corner.get_global_rect().intersects(expanded.get_node("Panel/Status").get_global_rect()),
			"Original scroll ornament does not cover tabs or footer text: " + corner_name)
	expand_button.pressed.emit()
	await settle()
	check(expand_button.icon.resource_path == "res://assets/ui/chat_collapse.svg" and expand_button.tooltip_text == "收起聊天", "Opening points the same arrow down and explains collapse")
	await capture("empty_chat")
	expand_button.pressed.emit()
	check(not expanded.visible and expand_button.icon.resource_path == "res://assets/ui/chat_expand.svg", "Clicking the down arrow collapses rather than reopening history")
	for batch_index in 3:
		var batch: Array = []
		for i in 12:
			var seq := batch_index * 12 + i + 1
			batch.append(message(seq, "结伴游历青云山道，山林试炼等你同行！[微笑][加油] 第%d条" % seq, PEER if seq % 2 == 0 else SELF))
		check(receive(view, batch), "Only existing validated session messages enter expanded history")
	view.chat_input.text = "未发送的草稿[爱心]"
	view.chat_input.caret_column = view.chat_input.text.length()
	view.get_node("Screen/Chat/Expand").pressed.emit()
	await settle()
	check(expanded.visible and not view.chat_input.has_focus() and view.chat_input.text == "未发送的草稿[爱心]", "Open preserves draft and leaves keyboard in reading mode")
	check(Rect2(0,0,320,480).encloses(expanded.get_node("Panel").get_global_rect()) and expanded.get_node("Panel").get_global_rect().end.y < view.chat_panel.position.y, "Paper window stays above the inline composer")
	check(expanded.selected_filter == "public" and expanded.history.get_parsed_text().contains("第36条") and not expanded.history.get_parsed_text().contains("[微笑]"), "World tab renders current messages and inline emotes")
	var bar := expanded.history.get_v_scroll_bar()
	check(bar.max_value > bar.page and absf(bar.value + bar.page - bar.max_value) < 3, "Opening starts at newest messages with a real scrollbar")
	bar.value = bar.min_value + 25
	var previous := bar.value
	check(receive(view, [message(37,"大家一起去桥边汇合吧[大笑]"),message(38,"道人身旁见[微笑]")]), "New live messages update expanded history")
	await settle()
	check(absf(bar.value - previous) < 2, "Receiving new messages preserves manual scroll position")
	bar.value = bar.max_value
	check(receive(view, [message(39,"准备出发！[加油]")]), "Live message accepted while following bottom")
	await settle()
	check(absf(bar.value + bar.page - bar.max_value) < 3, "Reading at bottom continues following newest messages")
	expanded.add_system("试炼完成，获得铜钱与修为。")
	expanded.get_node("Panel/Tabs/System").pressed.emit()
	await settle()
	check(expanded.history.get_parsed_text().contains("试炼完成") and not expanded.history.get_parsed_text().contains("[世界]"), "System tab filters actual system messages")
	expanded.get_node("Panel/Tabs/All").pressed.emit()
	await settle()
	check(expanded.history.get_parsed_text().contains("[系统]") and expanded.history.get_parsed_text().contains("[世界]"), "All tab combines world and system messages")
	for name_value in ["Area", "Team", "Guild", "Private"]:
		check(expanded.get_node("Panel/Tabs/" + name_value).disabled, "Unavailable channels cannot send through the world channel")
	var timer := view._key_timer
	view._process(0.25)
	check(view._key_timer == timer and not view._was_keyboard, "Reading expanded chat blocks keyboard movement")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(180,200)
	view._map_input(click)
	check(not view.chat_input.text.is_empty() and expanded.visible, "Map handlers cannot move through expanded chat")
	view.emote_button.pressed.emit()
	await settle()
	check(expanded.picker.visible and view.chat_input.has_focus() and Rect2(0,0,320,480).encloses(expanded.picker.get_global_rect()), "Expanded emotes open above the paper panel and use the existing draft")
	expanded.picker.get_node("Content/Grid/Smile").pressed.emit()
	check(view.chat_input.text == "未发送的草稿[爱心][微笑]" and not expanded.picker.visible and expanded.visible, "Emote selection edits the same inline composer without closing history")
	view.network.chat.send_requested.connect(func(packet: Dictionary) -> void: sent.append(packet.duplicate(true)))
	view.chat_send.pressed.emit()
	view._process(0.0)
	check(sent.size() == 1 and sent[0].channel == "public" and not view.chat_input.text.is_empty(), "Expanded window sends once through the existing reliable channel")
	check(view.emote_button.disabled and not expanded.picker.visible, "Pending send locks the existing emote entry and closes the picker")
	check(view.network.chat.receive({"type":"chat.result","result":{"client_message_id":sent[0].client_message_id,"status":"SENT","message_id":"30000000-0000-4000-8000-000000000040"}}), "Delivery acknowledgement resolves expanded send")
	view._process(0.0)
	check(view.chat_input.text.is_empty() and expanded.visible, "Acknowledgement clears draft while history remains expanded")
	expanded.get_node("Panel/Tabs/World").pressed.emit()
	await settle()
	await capture("expanded_chat")
	expand_button.pressed.emit()
	check(not expanded.visible and not view.chat_input.has_focus() and view.chat_panel.visible, "The downward arrow collapses into the original inline chat")
	check(expand_button.icon.resource_path == "res://assets/ui/chat_expand.svg", "Collapsing restores the upward arrow")
	await capture("collapsed_chat")
	view.get_node("Screen/Chat/Expand").pressed.emit()
	view._set_battle_layout(true)
	check(expanded.get_node("Shade").size.y == 424 and expanded.visible and view.chat_panel.position.y == 424, "Expanded chat covers battle controls while retaining the combat composer")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	view._unhandled_key_input(escape)
	check(not expanded.visible and view.battle_view.is_processing_unhandled_key_input(), "Escape collapses expanded history and restores battle keyboard handling")
	check(expand_button.icon.resource_path == "res://assets/ui/chat_expand.svg", "Escape also resets the arrow")
	expand_button.pressed.emit()
	# Dispatch through the GUI, so the modal shade cannot silently cover the arrow.
	var arrow_click := InputEventMouseButton.new()
	arrow_click.position = get_viewport().get_final_transform() * expand_button.get_global_rect().get_center()
	arrow_click.button_index = MOUSE_BUTTON_LEFT
	arrow_click.pressed = true
	Input.parse_input_event(arrow_click)
	var arrow_release := arrow_click.duplicate()
	arrow_release.pressed = false
	Input.parse_input_event(arrow_release)
	await settle()
	check(not expanded.visible and view.battle_view.is_processing_unhandled_key_input(), "Down arrow collapse restores battle keyboard handling too")
	view._set_battle_layout(false)
	view.get_node("Screen/Chat/Expand").pressed.emit()
	view._scene_action("menu")
	check(not expanded.visible and view.menu.visible, "Game menu does not overlap the chat window")
	view.menu.dismiss()
	check(receive(view, [message(40, "[b]仍为文字[/b][img]res://fake.png[/img][未知]")]), "Literal markup message uses normal protocol validation")
	view.get_node("Screen/Chat/Expand").pressed.emit()
	check(not expanded.history.bbcode_enabled and expanded.history.get_parsed_text().contains("[img]res://fake.png[/img]"), "Expanded history never interprets arbitrary markup or remote images")
	expanded.get_node("Panel/Tabs/World").pressed.emit()
	await settle()
	var moderation_notice := message(41, "青衫客所属账号已被管理员禁言10分钟。原因：刷屏")
	moderation_notice.system = true
	check(view.network.chat.receive({"type":"chat.batch", "channel_epoch":EPOCH, "messages":[moderation_notice], "removed_message_ids":[message(40, "").message_id]}), "Operator removal and notice use the validated existing channel")
	await settle()
	check(not expanded.history.get_parsed_text().contains("仍为文字"), "Expanded chat erases removed original text")
	expanded.get_node("Panel/Tabs/System").pressed.emit()
	await settle()
	check(expanded.history.get_parsed_text().contains("管理员禁言10分钟") and view.chat_log.get_parsed_text().contains("[系统]"), "Operator notice appears in the system tab and compact chat")
	for i in 150: expanded.add_system("系统消息%d" % i)
	check(expanded.entries.size() == expanded.LIMIT, "Expanded history stays bounded")
	expanded.sync_messages(view.network.chat.messages)
	check(expanded.entries.all(func(entry: Dictionary) -> bool: return entry.channel == "system"), "Trimmed public entries do not reappear as newly arrived messages")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(5, 200)
	expanded.get_node("Shade").gui_input.emit(touch)
	check(not expanded.visible, "Outside touch dismisses the expanded window")
	check(expand_button.icon.resource_path == "res://assets/ui/chat_expand.svg", "Outside touch restores the upward arrow")
	check(Game.player == before, "Expanded history does not change local character progress")
	view.queue_free()
	await get_tree().process_frame
	OnlineAccount.characters = before_characters
	print("EXPANDED CHAT: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
