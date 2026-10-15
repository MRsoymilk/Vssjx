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
@onready var left_arrow: TextureRect = $LeftArrow
@onready var right_arrow: TextureRect = $RightArrow
@onready var up_arrow: TextureRect = $UpArrow
@onready var down_arrow: TextureRect = $DownArrow

func _ready() -> void:
	original_text = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cover.json"))
	for index in PAGE_SIZE:
		var row: Button = get_node("Rows%d" % index)
		row.pressed.connect(_activate_row.bind(index))
		row.mouse_entered.connect(_hover_row.bind(index))
		rows.append(row)
	$Confirm.pressed.connect(_activate)
	$Exit.pressed.connect(func() -> void: exit_requested.emit())
	_refresh()

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
