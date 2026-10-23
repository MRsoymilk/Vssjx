class_name OriginalCover
extends Control
## Original cover artwork with the two public entry actions.

signal chosen(option: String)
signal exit_requested

const MENU_OPTIONS := ["登陆游戏", "退出游戏"]
const MENU_RECT := Rect2(164, 400, 142, 30)
var active := true:
	set(value):
		active = value
		if is_node_ready():
			panda_button.disabled = not active
			_reset_panda()
var selected_index := 0
var original_text: Dictionary
var rows: Array[Button] = []
@onready var left_arrow: TextureRect = $LeftArrow
@onready var right_arrow: TextureRect = $RightArrow
@onready var panda_button: Button = $Panda
@onready var panda: AnimatedSprite2D = $Panda/Sprite

func _ready() -> void:
	original_text = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cover.json"))
	for index in MENU_OPTIONS.size():
		var row: Button = get_node("Rows%d" % index)
		row.pressed.connect(_activate_row.bind(index))
		row.mouse_entered.connect(_hover_row.bind(index))
		rows.append(row)
	panda_button.pressed.connect(_look_back)
	panda_button.disabled = not active
	panda.animation_finished.connect(_reset_panda)
	_reset_panda()
	_refresh()

func _look_back() -> void:
	if not active or panda.animation == &"look_back": return
	panda.play(&"look_back")

func _reset_panda() -> void:
	panda.stop()
	if active: panda.play(&"roll")
	else: panda.animation = &"idle"

func _refresh() -> void:
	for i in rows.size():
		rows[i].text = MENU_OPTIONS[i]
		rows[i].add_theme_color_override("font_color", Color("ffff00") if i == selected_index else Color.WHITE)
	var y := MENU_RECT.position.y + selected_index * 38 + 11
	left_arrow.position = Vector2(169, y)
	right_arrow.position = Vector2(296, y)

func select_option(index: int) -> void:
	selected_index = wrapi(index, 0, MENU_OPTIONS.size())
	_refresh()

func _hover_row(index: int) -> void:
	if not active: return
	selected_index = index
	_refresh()

func _activate_row(index: int) -> void:
	if not active: return
	selected_index = index
	_activate()

func _activate() -> void:
	if active: chosen.emit(MENU_OPTIONS[selected_index])

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
