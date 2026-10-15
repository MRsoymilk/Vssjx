class_name OriginalCharacterCreation
extends Control
## Coordinates are measured from the 320×480 game area of the user's reference.

signal selection_changed(job: int, gender: int)
signal create_requested

const BODY_COLOR := Color("dedb49")
const TEXT_COLOR := Color("654518")
const NAMES := ["上官青云", "慕容听雪", "凌霄剑客", "青衫游仙", "白云无尘", "花间独行", "云中月", "昆仑客"]
var selected_variant := 0
var active := true:
	set(value):
		active = value
		if nickname != null: nickname.editable = value
var data: Dictionary
var nickname: LineEdit
var preview: AnimatedSprite2D
var description: Label
var quote: Label
var stamp: TextureRect
var cursor: TextureRect
var slots: Array[Control] = []
var portrait_buttons: Array[Button] = []

func _ready() -> void:
	size = Vector2(320, 480)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/creation.json"))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimHei", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var skin := Theme.new()
	skin.default_font = font
	skin.default_font_size = 12
	theme = skin
	_picture("create_header_end", Rect2(0, 0, 13, 25))
	_picture("create_header_end", Rect2(307, 0, 13, 25), true)
	_text("创建角色", Rect2(80, 5, 160, 18), 12, true).add_theme_color_override("font_color", Color("e8e148"))
	_picture("create_scroll", Rect2(22, 44, 20, 153))
	_picture("create_scroll", Rect2(278, 44, 20, 153), true)
	_picture("create_scroll_marks", Rect2(50, 64, 20, 117))
	_picture("create_scroll_marks", Rect2(258, 64, 20, 117), true)
	stamp = _picture("create_career_0", Rect2(61, 87, 39, 73))
	quote = _text("", Rect2(120, 76, 123, 15), 11)
	for i in 6:
		var slot := Control.new()
		slot.name = "Portrait%d" % i
		slot.position = Vector2(42 + i * 40, 218)
		slot.size = Vector2(32, 32)
		add_child(slot)
		var frame := NinePatchRect.new()
		frame.texture = load("res://assets/ui/create_slot_%s.png" % ("male" if i % 2 == 0 else "female"))
		frame.size = Vector2(32, 32)
		frame.patch_margin_left = 3
		frame.patch_margin_right = 3
		frame.patch_margin_top = 3
		frame.patch_margin_bottom = 3
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(frame)
		var face := TextureRect.new()
		face.texture = load(String(data.choices[i].portrait))
		face.position = Vector2(2, 2)
		face.size = Vector2(28, 28)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(face)
		face.size = Vector2(28, 28)
		var button := Button.new()
		button.name = "Choose%d" % i
		button.size = Vector2(32, 32)
		button.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(select_variant.bind(i))
		slot.add_child(button)
		slots.append(slot)
		portrait_buttons.append(button)
	cursor = _picture("create_cursor", Rect2(68, 240, 14, 14))
	var left := _image_button("create_arrow", Rect2(12, 220, 22, 29))
	left.pressed.connect(func() -> void: select_variant(selected_variant - 1))
	var right := _image_button("create_arrow", Rect2(286, 220, 22, 29), true)
	right.pressed.connect(func() -> void: select_variant(selected_variant + 1))
	_text("请输入昵称", Rect2(23, 270, 64, 18), 12)
	nickname = LineEdit.new()
	nickname.name = "Nickname"
	nickname.position = Vector2(86, 265)
	nickname.size = Vector2(214, 24)
	nickname.max_length = 24
	nickname.add_theme_font_size_override("font_size", 11)
	nickname.add_theme_color_override("font_color", TEXT_COLOR)
	nickname.add_theme_color_override("caret_color", TEXT_COLOR)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("fff9b5")
	input_style.border_color = Color("b9b657")
	input_style.set_border_width_all(1)
	input_style.content_margin_left = 3
	input_style.content_margin_right = 23
	input_style.content_margin_top = 0
	input_style.content_margin_bottom = 0
	nickname.add_theme_stylebox_override("normal", input_style)
	nickname.add_theme_stylebox_override("focus", input_style)
	nickname.text_submitted.connect(func(_value: String) -> void: _request_create())
	add_child(nickname)
	nickname.size = Vector2(214, 24)
	var edit := _image_button("create_edit", Rect2(283, 270, 13, 13))
	edit.pressed.connect(edit_name)
	description = _text("", Rect2(30, 320, 260, 97), 12)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var create := _wood_button("创建", Rect2(2, 457, 36, 21))
	create.pressed.connect(_request_create)
	var rename := _wood_button("改名", Rect2(141, 457, 36, 21))
	rename.pressed.connect(edit_name)
	var random := _wood_button("随机", Rect2(283, 457, 36, 21))
	random.pressed.connect(random_name)
	select_variant(selected_variant)

func _text(value: String, rect: Rect2, font_size: int = 12, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Color("756013"))
		label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.size = rect.size
	return label

func _picture(key: String, rect: Rect2, mirror: bool = false) -> TextureRect:
	var image := TextureRect.new()
	image.texture = load("res://assets/ui/%s.png" % key)
	image.position = rect.position
	image.size = rect.size
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.flip_h = mirror
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.size = rect.size
	return image

func _image_button(key: String, rect: Rect2, mirror: bool = false) -> Button:
	_picture(key, rect, mirror)
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 1)
	for state in ["normal", "hover", "pressed", "focus"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(button)
	button.size = rect.size
	return button

func _wood_button(value: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("b77927")
	style.border_color = Color("75410e")
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("d0953f")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", Color("fffbd2"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color("78441b"))
	button.add_theme_constant_override("outline_size", 1)
	add_child(button)
	button.size = rect.size
	var inner := Panel.new()
	inner.position = Vector2(2, 2)
	inner.size = rect.size - Vector2(4, 4)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.border_color = Color("ffe3a1")
	rim.set_border_width_all(1)
	inner.add_theme_stylebox_override("panel", rim)
	button.add_child(inner)
	return button

func select_variant(index: int) -> void:
	if not active: return
	selected_variant = wrapi(index, 0, 6)
	var choice: Dictionary = data.choices[selected_variant]
	if preview != null:
		remove_child(preview)
		preview.queue_free()
	preview = OriginalArt.actor(String(choice.preview))
	preview.position = Vector2(188, 153)
	add_child(preview)
	stamp.texture = load("res://assets/ui/create_career_%d.png" % int(choice.job))
	quote.text = String(choice.quote)
	description.text = String(data.descriptions[int(choice.job)]).replace("\r", "").replace("\n\n", "\n")
	for i in slots.size(): slots[i].position.y = 215 if i == selected_variant else 218
	cursor.position = slots[selected_variant].position + Vector2(26, 25)
	selection_changed.emit(int(choice.job), int(choice.gender))

func edit_name() -> void:
	if not active: return
	nickname.grab_focus()
	nickname.select_all()

func random_name() -> void:
	if not active: return
	var previous := nickname.text
	while nickname.text == previous or nickname.text.is_empty(): nickname.text = NAMES.pick_random()
	nickname.caret_column = nickname.text.length()

func _request_create() -> void:
	if active: create_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not active or nickname.has_focus() or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_LEFT: select_variant(selected_variant - 1)
	elif event.keycode == KEY_RIGHT: select_variant(selected_variant + 1)
	else: return
	get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 480), BODY_COLOR)
	draw_rect(Rect2(11, 1, 298, 23), Color("a7d700"))
	draw_line(Vector2(11, 1), Vector2(309, 1), Color("fff391"), 1)
	draw_line(Vector2(11, 24), Vector2(309, 24), Color("746016"), 1)
	draw_rect(Rect2(34, 50, 252, 135), Color("ffb500"))
	draw_line(Vector2(34, 50), Vector2(286, 50), Color("754713"), 1)
	draw_line(Vector2(34, 184), Vector2(286, 184), Color("714d16"), 1)
	var bubble := PackedVector2Array([Vector2(116, 72), Vector2(246, 72), Vector2(246, 94), Vector2(166, 94), Vector2(181, 104), Vector2(151, 94), Vector2(116, 94)])
	draw_colored_polygon(bubble, Color("ffe482"))
	var outline := bubble.duplicate()
	outline.append(bubble[0])
	draw_polyline(outline, Color("81501b"), 1)
	draw_rect(Rect2(0, 226, 320, 20), Color("b6ae26"))
	draw_rect(Rect2(20, 265, 66, 24), Color("b7b220"))
	draw_rect(Rect2(20, 305, 280, 119), Color("bcb769"))
	draw_rect(Rect2(21, 306, 278, 117), Color("fff8b8"))
