class_name LocalWorldChat
extends Node
## Local echo only. This controller has no account, HTTP or WebSocket dependency.
const LIMIT := 100
var messages: Array[Dictionary] = []
var _sequence := 0
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
	expanded.emotes_requested.connect(_toggle_emotes)
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
	if panel.visible: close()
	else:
		panel.show()
		screen.chrome.log_label.hide()
		_focus()

func close() -> void:
	picker.hide()
	expanded.hide()
	expanded.close_emotes()
	panel.hide()
	screen.chrome.log_label.show()
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
	var submission := Platform.context.text_input.check_submission([input])
	if not submission.ok: return
	var text := input.text.strip_edges()
	if not OnlinePublicChat.valid_text(text):
		expanded.set_status("消息不能为空，最多120字。")
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

func _render() -> void:
	log.clear()
	log.add_text("[系统] 本地消息仅自己可见")
	for message in messages:
		log.add_text("\n[本地] %s：" % message.display_name)
		ChatEmotePicker.CATALOG.append_body(log, message.text)
	expanded.sync_messages(messages)
