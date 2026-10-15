class_name OriginalCover
extends Control
## Original cover pixels and menu strings. Menu geometry is not stored in the
## recovered assets; the four-row viewport is provisional pending a cover photo.

signal chosen(option: String)
signal exit_requested

const PAGE_SIZE := 4
const MENU_RECT := Rect2(164, 396, 142, 18)
var active := true
var selected_index := 0
var first_visible := 0
var original_text: Dictionary
var rows: Array[Button] = []
var left_arrow: TextureRect
var right_arrow: TextureRect
var up_arrow: TextureRect
var down_arrow: TextureRect

func _ready() -> void:
	size = Vector2(320, 480)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	original_text = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cover.json"))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimSun", "Noto Serif CJK SC", "serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var cover_theme := Theme.new()
	cover_theme.default_font = font
	cover_theme.default_font_size = 16
	theme = cover_theme
	var artwork := TextureRect.new()
	artwork.name = "Original320x480Artwork"
	artwork.texture = load("res://assets/ui/original_cover.png")
	artwork.size = Vector2(320, 480)
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(artwork)
	for index in PAGE_SIZE:
		var row := _text_button("", Rect2(MENU_RECT.position + Vector2(0, index * 18), MENU_RECT.size))
		row.pressed.connect(_activate_row.bind(index))
		row.mouse_entered.connect(_hover_row.bind(index))
		rows.append(row)
	left_arrow = _arrow(3)
	right_arrow = _arrow(2)
	up_arrow = _arrow(0)
	down_arrow = _arrow(1)
	up_arrow.position = Vector2(307, 395)
	down_arrow.position = Vector2(307, 459)
	var confirm := _text_button("确定", Rect2(4, 463, 52, 17))
	confirm.pressed.connect(_activate)
	var exit_button := _text_button("退出", Rect2(264, 463, 52, 17))
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	_refresh()

func _text_button(value: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_color_override("font_outline_color", Color("713500"))
	button.add_theme_color_override("font_color", Color("ffff00"))
	button.add_theme_color_override("font_hover_color", Color("ffff00"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	add_child(button)
	return button

func _arrow(index: int) -> TextureRect:
	var result := TextureRect.new()
	result.texture = load("res://assets/ui/select_%d.png" % index)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func _refresh() -> void:
	for i in PAGE_SIZE:
		var index := first_visible + i
		rows[i].text = String(original_text.menu[index])
		rows[i].add_theme_color_override("font_color", Color("ffff00") if index == selected_index else Color.WHITE)
	var y := MENU_RECT.position.y + (selected_index - first_visible) * 18 + 6
	left_arrow.position = Vector2(169, y)
	right_arrow.position = Vector2(296, y)
	up_arrow.visible = first_visible > 0
	down_arrow.visible = first_visible + PAGE_SIZE < original_text.menu.size()

func select_option(index: int) -> void:
	selected_index = wrapi(index, 0, original_text.menu.size())
	if selected_index < first_visible: first_visible = selected_index
	if selected_index >= first_visible + PAGE_SIZE: first_visible = selected_index - PAGE_SIZE + 1
	_refresh()

func _hover_row(index: int) -> void:
	if not active: return
	selected_index = first_visible + index
	_refresh()

func _activate_row(index: int) -> void:
	if not active: return
	selected_index = first_visible + index
	_activate()

func _activate() -> void:
	if active: chosen.emit(String(original_text.menu[selected_index]))

func _gui_input(event: InputEvent) -> void:
	if not active or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: select_option(selected_index + 1)
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP: select_option(selected_index - 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if not active or not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_UP: select_option(selected_index - 1)
		KEY_DOWN: select_option(selected_index + 1)
		KEY_ENTER, KEY_SPACE: _activate()
		KEY_ESCAPE: exit_requested.emit()
		_: return

	get_viewport().set_input_as_handled()
