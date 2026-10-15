class_name ExpandedChatPanel
extends Control
## Authored paper chat window over the map, backed by this session's existing cache.
signal dismissed
signal emotes_requested
signal emote_chosen(token: String)
signal focus_requested
@onready var history: RichTextLabel = $Panel/History
@onready var picker: ChatEmotePicker = $EmotePicker
var selected_filter := "public"
var entries: Array[Dictionary] = []
var _render_generation := 0
var _known_public_ids: Dictionary = {}
var _emotes_enabled := false
var _scroll_pending := false
var _pending_scroll := 0.0
var _pending_follow := true
const LIMIT := 100

func _ready() -> void:
	$Panel/Return.pressed.connect(dismiss)
	$Panel/Emotes.pressed.connect(func() -> void: emotes_requested.emit())
	picker.chosen.connect(func(token: String) -> void: emote_chosen.emit(token))
	picker.dismissed.connect(func() -> void: focus_requested.emit())
	$Shade.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			dismiss()
			$Shade.accept_event()
	)
	for button in $Panel/Tabs.get_children():
		if not button.disabled: button.pressed.connect(_select_filter.bind(String(button.get_meta("channel"))))

func open() -> void:
	show()
	picker.hide()
	_render(true)

func dismiss() -> void:
	picker.hide()
	hide()
	dismissed.emit()

func _select_filter(channel: String) -> void:
	if channel not in ["all", "public", "system"]: return
	selected_filter = channel
	for button in $Panel/Tabs.get_children(): button.set_pressed_no_signal(button.get_meta("channel") == channel)
	_render(true)

func add_system(text: String) -> void:
	if text.is_empty(): return
	if not entries.is_empty() and entries[-1].channel == "system" and entries[-1].text == text: return
	entries.append({"channel": "system", "text": text})
	_trim()
	if visible: _render()

func sync_messages(messages: Array) -> void:
	var valid_ids := {}
	for message in messages: valid_ids[message.message_id] = true
	var updated: Array[Dictionary] = []
	for entry in entries:
		if entry.channel == "system" or valid_ids.has(entry.get("message_id")):
			updated.append(entry)
	for message in messages:
		if not _known_public_ids.has(message.message_id): updated.append(message.duplicate(true))
	_known_public_ids = valid_ids
	if updated == entries: return
	entries = updated
	_trim()
	if visible: _render()

func _trim() -> void:
	while entries.size() > LIMIT: entries.pop_front()

func set_emotes_enabled(enabled: bool) -> void:
	_emotes_enabled = enabled
	$Panel/Emotes.disabled = not enabled
	if not enabled: picker.hide()

func toggle_emotes() -> void:
	if _emotes_enabled: picker.visible = not picker.visible

func close_emotes() -> void:
	picker.hide()

func set_status(text: String) -> void:
	$Panel/Status.text = text
	$Panel/Status.tooltip_text = text

func _render(follow: bool = false) -> void:
	var bar := history.get_v_scroll_bar()
	var previous := _pending_scroll if _scroll_pending else bar.value
	var at_bottom := follow or (_pending_follow if _scroll_pending else bar.value + bar.page >= bar.max_value - 2.0)
	_pending_scroll = previous
	_pending_follow = at_bottom
	_scroll_pending = true
	history.clear()
	var count := 0
	for entry in entries:
		if selected_filter != "all" and entry.channel != selected_filter: continue
		if count > 0: history.add_text("\n")
		count += 1
		history.push_color(Color("9470a6") if entry.channel == "public" else Color("af6a47"))
		history.add_text("[世界] " if entry.channel == "public" else "[系统] ")
		history.pop()
		if entry.channel == "public":
			history.push_color(Color("597e7d"))
			history.add_text(entry.display_name + "：")
			history.pop()
		ChatEmotePicker.CATALOG.append_body(history, entry.text)
	$Panel/Empty.visible = count == 0
	$Panel/Empty.text = {"all":"暂时没有消息", "public":"暂时没有世界消息", "system":"暂时没有系统消息"}[selected_filter]
	_render_generation += 1
	_restore_scroll.call_deferred(_render_generation, previous, at_bottom)

func _restore_scroll(generation: int, previous: float, follow: bool) -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	if generation != _render_generation or not is_inside_tree(): return
	_scroll_pending = false
	var bar := history.get_v_scroll_bar()
	bar.value = bar.max_value if follow else previous
