class_name LocalWorldChat
extends Node
## Local echo only. This controller has no account, HTTP or WebSocket dependency.
const LIMIT := 100
var messages: Array[Dictionary] = []
var _sequence := 0
var _control_busy := false
const CONTROL_HELP := "本地测试指令：/control lv <1～60>；/control hp <血量>（设置）；/control money <正整数>（增加铜币）。例如 /control hp 1、/control money 1。仅修改当前本地角色并保存。"
@onready var screen: Control = get_parent()
@onready var panel: Panel = screen.get_node("Chat")
@onready var input: LineEdit = screen.get_node("Chat/ChatInput")
@onready var log: RichTextLabel = screen.get_node("Chat/ChatLog")
@onready var expanded: ExpandedChatPanel = screen.get_node("ExpandedChat")
@onready var picker: ChatEmotePicker = screen.get_node("Chat/EmotePicker")

func _ready() -> void:
	messages = screen.local_messages
	input.placeholder_text = "本地消息，仅自己可见"
	expanded.public_caption = "本地"
	expanded.get_node("Panel/Tabs/World").text = "本地"
	expanded.set_status("本地聊天 · 仅自己可见")
	expanded.set_emotes_enabled(true)
	screen.get_node("Chat/ChatSend").pressed.connect(send)
	input.text_submitted.connect(func(_text: String) -> void: send())
	input.focus_entered.connect(func() -> void: screen.movement_pause_requested.emit())
	screen.get_node("Chat/ChatEmotes").pressed.connect(_toggle_emotes)
	screen.chat_expand_requested.connect(func() -> void: picker.hide(); expanded.open())
	picker.chosen.connect(_insert_emote)
	picker.dismissed.connect(_focus)
	expanded.emote_chosen.connect(_insert_emote)
	expanded.focus_requested.connect(_focus)
	expanded.dismissed.connect(_focus)
	input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close()
			input.accept_event()
	)
	_render()

func toggle() -> void:
	if expanded.visible: expanded.dismiss()
	else:
		picker.hide()
		expanded.open()

func close() -> void:
	picker.hide()
	expanded.hide()
	expanded.close_emotes()
	# The inline composer stays available while menus/history close.
	panel.show()
	screen.chrome.log_label.hide()
	Platform.context.text_input.release_focus(input)

func _focus() -> void:
	Platform.context.text_input.request_focus(input)

func release_input() -> void:
	picker.hide()
	expanded.hide()
	expanded.close_emotes()
	Platform.context.text_input.release_focus(input)

func _toggle_emotes() -> void:
	if not Platform.context.text_input.check_submission([input]).ok: return
	if expanded.visible: expanded.toggle_emotes()
	else: picker.visible = not picker.visible
	_focus()

func _insert_emote(token: String) -> void:
	if ChatEmotePicker.CATALOG.texture_for(token) == null: return
	if not Platform.context.text_input.check_submission([input]).ok: return
	var start := input.get_selection_from_column() if input.has_selection() else input.caret_column
	var end := input.get_selection_to_column() if input.has_selection() else start
	var draft := input.text.left(start) + token + input.text.substr(end)
	if draft.length() > 120 or draft.to_utf8_buffer().size() > 480: return
	input.text = draft
	input.deselect()
	input.caret_column = start + token.length()
	picker.hide()
	expanded.close_emotes()
	_focus()

func send() -> void:
	if screen.online_mode or _control_busy: return
	var submission := Platform.context.text_input.check_submission([input])
	if not submission.ok: return
	var text := input.text.strip_edges()
	if not OnlinePublicChat.valid_text(text):
		expanded.set_status("消息不能为空，最多120字。")
		return
	var words := text.split(" ", false)
	if words[0].to_lower() == "/control":
		input.clear()
		picker.hide()
		expanded.close_emotes()
		await _control(words)
		return
	_sequence += 1
	messages.append({"message_id": "local-%d-%d" % [Time.get_ticks_usec(), _sequence], "channel": "public",
		"display_name": String(Game.player.name), "text": text})
	while messages.size() > LIMIT: messages.pop_front()
	input.clear()
	picker.hide()
	expanded.close_emotes()
	expanded.set_status("本地聊天 · 仅自己可见")
	_render()

func _control(words: PackedStringArray) -> void:
	if screen.online_mode: return
	if words.size()==1 or (words.size()==2 and words[1].to_lower()=="help"):
		_control_message(CONTROL_HELP)
		return
	if words.size()!=3 or words[1].to_lower() not in ["lv","hp","money"] or not words[2].is_valid_int():
		_control_message(CONTROL_HELP)
		return
	var kind:=words[1].to_lower()
	if kind!="lv":
		_control_busy=true
		var value:=words[2].to_int()
		var changed:=await Game.set_local_test_value(kind,value)
		if not is_inside_tree():return
		_control_busy=false
		if changed.ok:
			_control_message("本地测试：血量已设置为%d。已保存。"%value if kind=="hp" else "本地测试：增加铜币%d，当前铜币%d。已保存。"%[value,int(Game.player.gold)])
		else:_control_message("本地测试未生效："+changed.message)
		return
	var level := words[2].to_int()
	if level<1 or level>60:
		_control_message("等级必须为1～60。"+CONTROL_HELP)
		return
	_control_busy = true
	var result := await Game.set_local_test_level(level)
	if not is_inside_tree(): return
	_control_busy = false
	if result.ok:
		_control_message("本地测试：等级已设置为%d，经验清零，气血与灵力已回满。已保存。"%level+("等级降低，已重置属性分配。" if result.value.reset_attributes else ""))
	else:
		_control_message("本地测试未生效："+result.message)

func _control_message(text: String) -> void:
	_sequence += 1
	messages.append({"message_id":"local-control-%d-%d"%[Time.get_ticks_usec(),_sequence],"channel":"system","display_name":"系统","text":text})
	while messages.size()>LIMIT: messages.pop_front()
	expanded.set_status(text)
	_render()
	screen.local_control_completed.emit()

func _render() -> void:
	log.clear()
	log.add_text("[系统] 本地消息仅自己可见")
	if messages.is_empty(): log.add_text("\n[系统] "+Game.quest_text())
	for message in messages:
		log.add_text("\n[系统] " if message.channel=="system" else "\n[本地] %s：" % message.display_name)
		ChatEmotePicker.CATALOG.append_body(log, message.text)
	expanded.sync_messages(messages)
