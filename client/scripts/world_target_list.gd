class_name WorldTargetList
extends Control
## Explicit target selection, shared by crowded picking and same-map NPC lookup.
signal chosen(kind: String, id: String)
signal dismissed
const CHROME := preload("res://scripts/social_chrome.gd")
var entries: Array[Dictionary] = []
var caption := "选择目标"
var search: LineEdit
var rows: VBoxContainer
var empty: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 25
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := CHROME.frame(self, Rect2(12, 54, 296, 372), caption)
	search = LineEdit.new()
	panel.add_child(search)
	search.position = Vector2(16, 42); search.size = Vector2(264, 30)
	search.placeholder_text = "搜索名称或用途"
	search.max_length = 64
	search.text_changed.connect(func(_text: String) -> void: _refresh())
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	scroll.position = Vector2(16, 80); scroll.size = Vector2(264, 236)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	empty = OriginalSceneChrome.label(panel, "暂无可选目标", Rect2(20, 84, 256, 32), 13, CHROME.INK)
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CHROME.placed_button(panel, "返回", Rect2(16, 330, 264, 30)).pressed.connect(func() -> void: dismissed.emit())
	_refresh()

func _refresh() -> void:
	for row in rows.get_children(): rows.remove_child(row); row.queue_free()
	var query := search.text.strip_edges().to_lower()
	for entry in entries:
		var text := String(entry.name) + "\n" + String(entry.get("detail", ""))
		if not query.is_empty() and not text.to_lower().contains(query): continue
		var button := CHROME.button(rows, text)
		button.custom_minimum_size = Vector2(0, 46)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func() -> void: chosen.emit(entry.kind, entry.id))
	empty.visible = rows.get_child_count() == 0
