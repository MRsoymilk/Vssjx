class_name OriginalCharacterCreation
extends Control
## Coordinates are measured from the 320×480 game area of the user's reference.

signal selection_changed(job: int, gender: int)
signal create_requested
@export var online_mode := false

const BODY_COLOR := Color("dedb49")
const TEXT_COLOR := Color("654518")
const NAMES := ["上官青云", "慕容听雪", "凌霄剑客", "青衫游仙", "白云无尘", "花间独行", "云中月", "昆仑客"]
var selected_variant := 0
var active := true:
	set(value):
		active = value
		if nickname != null: nickname.editable = value
var data: Dictionary
@onready var nickname: LineEdit = $Nickname
var preview: AnimatedSprite2D
@onready var description: Label = $Description
@onready var quote: Label = $Quote
@onready var stamp: TextureRect = $Stamp
@onready var cursor: TextureRect = $Cursor
var slots: Array[Control] = []
var portrait_buttons: Array[Button] = []

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/creation.json"))
	for i in 6:
		var slot: Control = get_node("Slots%d" % i)
		var button: Button = slot.get_node("PortraitButtons%d" % i)
		button.pressed.connect(select_variant.bind(i))
		slots.append(slot)
		portrait_buttons.append(button)
	$Previous.pressed.connect(func() -> void: select_variant(selected_variant - 1))
	$Next.pressed.connect(func() -> void: select_variant(selected_variant + 1))
	nickname.text_submitted.connect(func(_value: String) -> void: _request_create())
	$Edit.pressed.connect(edit_name)
	$Create.pressed.connect(_request_create)
	$Rename.pressed.connect(edit_name)
	$Random.pressed.connect(random_name)
	select_variant(selected_variant)

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
	Platform.context.text_input.request_focus(nickname, true)

func random_name() -> void:
	if not active: return
	var previous := nickname.text
	while nickname.text == previous or nickname.text.is_empty(): nickname.text = NAMES.pick_random()
	nickname.caret_column = nickname.text.length()

func _request_create() -> void:
	if not Platform.context.text_input.check_submission([nickname]).ok: return
	if active or online_mode: create_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not active or nickname.has_focus() or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_LEFT: select_variant(selected_variant - 1)
	elif event.keycode == KEY_RIGHT: select_variant(selected_variant + 1)
	else: return
	get_viewport().set_input_as_handled()
