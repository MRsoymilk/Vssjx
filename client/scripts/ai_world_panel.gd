class_name AIWorldPanel
extends Control
## Expansion quest journal. Map travel is handled by OriginalWorldMap.
signal back_requested
signal requested(action: String, target: String)
var map_id := "qingyun_trail"
var progress: Dictionary = {}
var level := 1
var selected_quest := ""
var npc_id := ""
var body: VBoxContainer
var paper: PanelContainer
const INK := Color("654518")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 25
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.05, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	add_theme_font_override("font",preload("res://assets/fonts/NotoSansCJKsc-Regular.otf"))
	paper = PanelContainer.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.offset_left = 10; paper.offset_top = 12; paper.offset_right = -10; paper.offset_bottom = -12
	add_child(paper)
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("fff0b8"); skin.border_color = Color("b77c20"); skin.set_border_width_all(4)
	skin.content_margin_left = 12; skin.content_margin_right = 12; skin.content_margin_top = 12; skin.content_margin_bottom = 12
	paper.add_theme_stylebox_override("panel", skin)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", 7); paper.add_child(body)
	var ornaments := Control.new()
	ornaments.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(ornaments)
	for index in 4:
		var corner := TextureRect.new()
		corner.texture = preload("res://assets/ui/chat_corner.png")
		corner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corner.set_anchors_and_offsets_preset([Control.PRESET_TOP_LEFT,Control.PRESET_TOP_RIGHT,Control.PRESET_BOTTOM_LEFT,Control.PRESET_BOTTOM_RIGHT][index])
		corner.offset_left = -10 if index%2 else 0; corner.offset_right = 0 if index%2 else 10
		corner.offset_top = -10 if index>=2 else 0; corner.offset_bottom = 0 if index>=2 else 10
		corner.flip_h = index%2 == 1; corner.flip_v = index>=2; ornaments.add_child(corner)
	refresh()

func present(current: String, state: Dictionary, character_level: int, npc: String = "") -> void:
	map_id = current; progress = state; level = character_level; npc_id = npc
	if is_node_ready(): refresh()

func _label(parent: Node, text: String, font_size: int = 12) -> Label:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size); label.add_theme_color_override("font_color", INK)
	parent.add_child(label); return label

func _button(parent: Node, text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size = Vector2(mini(160,maxi(54,text.length()*10)),30)
	button.add_theme_font_size_override("font_size", 12); button.clip_text = true; button.disabled = disabled
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new(); style.bg_color = Color("e3d4a6") if state=="disabled" else (Color("f5d181") if state in ["hover","pressed"] else Color("fff0b8"))
		style.border_color = Color("b77c20"); style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]: button.add_theme_color_override(key, INK)
	parent.add_child(button); button.pressed.connect(callback); return button

func _scroll() -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; body.add_child(scroll)
	var rows := VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6); scroll.add_child(rows); return rows

func refresh() -> void:
	AIWorld.prepare()
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	var top := HBoxContainer.new(); body.add_child(top)
	var title := _label(top, "支线任务 · AI生成", 16); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(top, "关闭", func() -> void: back_requested.emit())
	_label(body, "地名参考原包；布局、NPC布置、剧情与奖励为AI生成。", 11)
	_button(body, "任务 %d/3" % progress.get("active", {}).size(), func() -> void: selected_quest=""; refresh())
	if not selected_quest.is_empty(): _quest_detail(); return
	_quests()

func _quests() -> void:
	var rows := _scroll()
	if not npc_id.is_empty():
		var r := AIWorld.resident(npc_id)
		_label(rows, r.get("name", "巡山人") + " · AI生成", 14)
		_label(rows,r.get("service_label","驻地人物"),12)
		_label(rows,r.get("dialogue","这条驿路仍需修士照应。"),12)
		_label(rows,"称谓来源："+String(r.get("npc_reference",{}).get("source","AI生成"))+"；对白与摆放为AI设计。",10)
		_button(rows,"前往交谈",func()->void:requested.emit("ai_talk",npc_id))
	var ids: Array = progress.get("active", {}).keys()
	for q in AIWorld.map_data(map_id).get("quests", []):
		if not ids.has(q.id): ids.append(q.id)
	if ids.is_empty(): _label(rows, "当前在原有试炼区域。\n前往灵空台，与巡山人交谈开启支线。")
	for id in ids:
		var q := AIWorld.quest(id)
		_button(rows, "%s · %s" % [q.name,AIWorld.status(id,progress,level)], func() -> void: selected_quest=id; refresh())
	_label(body, "最多同时接取3个任务。完成后须返回发布人领取奖励。", 11)

func _quest_detail() -> void:
	var q := AIWorld.quest(selected_quest)
	var rows := _scroll()
	_label(rows, q.name + " · AI生成", 14)
	_label(rows, q.description)
	var counts: Array = progress.get("active", {}).get(q.id, [])
	for i in q.objectives.size():
		var goal: Dictionary = q.objectives[i]
		_label(rows, "%s　%d/%d" % [goal.text, int(counts[i]) if counts.size()>i else 0, int(goal.count)])
		_button(rows, "寻路：" + goal.text, func() -> void: requested.emit("ai_track", goal.target))
	_label(rows, "奖励：%d铜钱、%d修为\n接取等级：%d" % [int(q.gold),int(q.xp),int(q.min_level)])
	var value := AIWorld.status(q.id,progress,level)
	_button(body, {"可交付":"前往发布人交谈", "可接取":"前往发布人交谈"}.get(value,value), func() -> void: requested.emit("ai_talk", q.giver), value not in ["可交付","可接取"])
	_button(body, "返回任务", func() -> void: selected_quest=""; refresh())

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		back_requested.emit()
		get_viewport().set_input_as_handled()
