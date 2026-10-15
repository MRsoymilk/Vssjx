extends "res://tests/shared_interface_test.gd"
## Two actual UI instances exchange validated chat packets; no DB/WebSocket fixture.

func make_view(id: String) -> OnlineWorldView:
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = id
	add_child(view)
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10, 16]), PEER: entity(PEER, 2, "青衫客", 0, 1, [12, 16])}
	view.network.changed.emit(view.network.entities)
	view.network.chat.receive({"type": "chat.ready", "channel_epoch": EPOCH, "latest_seq": "0", "oldest_seq": "1", "history_limit": 50, "dedup_seconds": 300, "max_chars": 120, "max_bytes": 480})
	view.network.chat.enabled = true
	view._process(0.0)
	return view

func message(seq: int, text: String, sender_id: String = SELF) -> Dictionary:
	return {"seq": str(seq), "message_id": "30000000-0000-4000-8000-%012d" % seq, "sender_character_id": sender_id, "display_name": "昆仑客" if sender_id == SELF else "青衫客", "server_time_ms": "1792036800000", "channel": "public", "text": text}

func receive(view: OnlineWorldView, entries: Array) -> bool:
	return view.network.chat.receive({"type": "chat.batch", "channel_epoch": EPOCH, "messages": entries})

func _run() -> void:
	output = OS.get_environment("SSJX_EMOTE_CAPTURE_PATH")
	var before := Game.player.duplicate(true)
	var old_characters := OnlineAccount.characters.duplicate(true)
	OnlineAccount.characters = [
		{"id": SELF, "display_name": "昆仑客", "job": 1, "gender": 0, "school": 2, "level": 1, "hp": 95, "mp": 45},
		{"id": PEER, "display_name": "青衫客", "job": 0, "gender": 1, "school": 0, "level": 1, "hp": 95, "mp": 45}]
	var sender_view := make_view(SELF)
	var peer_view := make_view(PEER)
	peer_view.hide()
	var catalog := ChatEmotePicker.CATALOG
	check(catalog.tokens.size() == 8 and catalog.textures.size() == 8, "Eight built-in emotes have packaged textures")
	check(sender_view.emote_picker.scene_file_path == "res://scenes/ui/chat_emote_picker.tscn", "Picker is an authored tscn instance")
	var buttons := sender_view.emote_picker.get_node("Content/Grid").get_children()
	for button in buttons:
		check(catalog.texture_for(button.tooltip_text) == button.icon and button.icon.get_size() == Vector2(16, 16), "Picker icon and received marker share the same built-in texture: " + button.tooltip_text)
	for raw in ["[未知]", "[微笑", "微笑]", "[微笑 ]", "[img]https://example.invalid/image.png[/img]", "[b]普通文字[/b]"]:
		check(catalog.segments(raw) == [{"text": raw}], "Unknown/markup text stays literal: " + raw)
	var all_tokens := "".join(catalog.tokens)
	var parts := catalog.segments("你好" + all_tokens + "！")
	check(parts.size() == 10 and parts[0].text == "你好" and parts[-1].text == "！", "Adjacent emotes preserve surrounding Unicode text")
	sender_view.emote_button.pressed.emit()
	await get_tree().process_frame
	check(sender_view.emote_picker.visible and sender_view.chat_input.has_focus(), "Bottom emote button opens the picker and retains composer focus")
	check(Rect2(0, 0, 320, 480).encloses(sender_view.emote_picker.get_global_rect()), "Expanded picker remains inside the game area")
	check(sender_view.emote_picker.get_global_rect().end.y <= sender_view.chat_panel.position.y, "Picker opens above the inline message area")
	var timer := sender_view._key_timer
	sender_view._process(0.2)
	check(sender_view._key_timer == timer and not sender_view._was_keyboard, "Picking emotes does not advance keyboard movement")
	sender_view.chat_input.text = "你好世界"
	sender_view.chat_input.caret_column = 2
	buttons[0].pressed.emit()
	check(sender_view.chat_input.text == "你好[微笑]世界" and sender_view.chat_input.caret_column == 6, "Selection inserts marker at the Unicode caret")
	check(not sender_view.emote_picker.visible and sender_view.chat_input.has_focus(), "Choosing returns to the same inline composer")
	sender_view.chat_input.text = "甲乙丙丁"
	sender_view.chat_input.select(1, 3)
	sender_view.emote_button.pressed.emit()
	buttons[2].pressed.emit()
	check(sender_view.chat_input.text == "甲[爱心]丁" and not sender_view.chat_input.has_selection(), "Emote replaces only the selected text")
	sender_view.chat_input.text = "界".repeat(117)
	sender_view.chat_input.caret_column = 117
	sender_view.emote_button.pressed.emit()
	buttons[0].pressed.emit()
	check(sender_view.chat_input.text.length() == 117 and sender_view.emote_picker.visible and sender_view.chat_status.text.contains("120"), "Over-limit insertion leaves draft intact and explains the limit")
	sender_view.chat_input.text = "😀".repeat(116)
	sender_view.chat_input.caret_column = 116
	buttons[0].pressed.emit()
	check(sender_view.chat_input.text.length() == 120 and OnlinePublicChat.valid_text(sender_view.chat_input.text), "Exact-limit Unicode draft accepts a complete marker without truncation")
	var draft := sender_view.chat_input.text
	sender_view._insert_emote("[未收录]")
	check(sender_view.chat_input.text == draft, "Unknown picker tokens cannot alter the draft")
	sender_view.emote_button.pressed.emit()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	sender_view.chat_input.gui_input.emit(escape)
	check(not sender_view.emote_picker.visible and sender_view.chat_input.has_focus(), "Escape dismisses picker before leaving text input")
	sender_view.emote_button.pressed.emit()
	sender_view.emote_picker.get_node("Content/Header/Close").pressed.emit()
	check(not sender_view.emote_picker.visible and sender_view.chat_input.has_focus(), "Picker close keeps the draft in focus")
	sender_view.emote_button.pressed.emit()
	sender_view.screen.chrome.toolbar.get_node("Menu").pressed.emit()
	check(not sender_view.emote_picker.visible and sender_view.menu.visible, "Opening the game menu closes the picker")
	sender_view.get_node("Menu/Panel/Continue").pressed.emit()
	sender_view.emote_button.pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(180, 200)
	sender_view._map_input(click)
	check(not sender_view.emote_picker.visible and sender_view.chat_input.has_focus(), "Outside map click dismisses picker without leaving composer")
	var body := "你好[微笑][爱心][未知][b]字[/b][img]res://no.png[/img]"
	sender_view.chat_input.text = body
	sender_view.network.chat.send_requested.connect(func(packet: Dictionary) -> void: sent.append(packet.duplicate(true)))
	sender_view.chat_send.pressed.emit()
	sender_view._process(0.0)
	check(sent.size() == 1 and sent[0].text == body and sender_view.chat_input.text == body, "Wire payload keeps text markers and draft waits for confirmation")
	check(sender_view.emote_button.disabled and not sender_view.chat_input.editable, "Pending send locks emote edits together with text input")
	sender_view._insert_emote("[加油]")
	check(sender_view.chat_input.text == body, "Pending message content cannot be changed by picker callbacks")
	var delivered := message(1, sent[0].text)
	check(receive(sender_view, [delivered]) and receive(peer_view, [delivered]), "Both clients validate the same marker message through the public channel")
	check(not peer_view.chat_log.get_parsed_text().contains("[微笑]") and not peer_view.chat_log.get_parsed_text().contains("[爱心]"), "Known marker text is replaced by native inline image items")
	check(sender_view.chat_log.get_parsed_text() == peer_view.chat_log.get_parsed_text(), "Sender and peer produce identical visible message content")
	check(peer_view.chat_log.get_parsed_text().contains("[未知][b]字[/b][img]res://no.png[/img]") and not peer_view.chat_log.bbcode_enabled, "Only catalog markers become images; arbitrary markup remains literal")
	check(sender_view.network.chat.receive({"type": "chat.result", "result": {"client_message_id": sent[0].client_message_id, "status": "SENT", "message_id": delivered.message_id}}), "Server confirmation resolves marker message")
	sender_view._process(0.0)
	check(sender_view.chat_input.text.is_empty() and not sender_view.emote_button.disabled, "Confirmation clears the composer and unlocks emotes")
	var greetings := message(2, "大家好[微笑][大笑][爱心][流泪]", PEER)
	var cheers := message(3, "一起游历[生气][惊讶][害羞][加油]")
	check(receive(sender_view, [greetings, cheers]) and receive(peer_view, [greetings, cheers]), "All eight emotes render in both clients from ordered history")
	peer_view.network.chat.disconnect_channel()
	check(peer_view.network.chat.receive({"type": "chat.ready", "channel_epoch": EPOCH, "latest_seq": "3", "oldest_seq": "1", "history_limit": 50, "dedup_seconds": 300, "max_chars": 120, "max_bytes": 480}), "Reconnect restores the original public channel")
	peer_view.network.chat.enabled = true
	check(receive(peer_view, [delivered, greetings, cheers]) and peer_view.chat_log.get_parsed_text() == sender_view.chat_log.get_parsed_text(), "History replay reconstructs the same inline images without duplicate messages")
	peer_view.show()
	sender_view.hide()
	await get_tree().process_frame
	peer_view.emote_button.pressed.emit()
	await capture("01_emote_picker")
	peer_view.emote_picker.hide()
	await capture("02_emote_messages")
	peer_view.network.world_ready = false
	peer_view._process(0.0)
	check(peer_view.emote_button.disabled and not peer_view.emote_picker.visible, "Disconnected channel closes and disables the picker")
	check(Game.player == before, "Chat emotes do not modify offline player state")
	sender_view.queue_free()
	peer_view.queue_free()
	await get_tree().process_frame
	OnlineAccount.characters = old_characters
	print("CHAT EMOTES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
