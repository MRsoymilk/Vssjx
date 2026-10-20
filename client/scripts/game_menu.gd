class_name OriginalGameMenu
extends Control
## Authored, unnumbered game menu shared by local and online play.
signal chosen(action: String)
signal dismissed
const ACTIONS := ["shop", "properties", "craft", "social", "quest", "team", "guild", "trade", "system", "help"]
var rows: Array[Button] = []
var selected_index := 0

func _ready() -> void:
	$Dismiss.pressed.connect(dismiss)
	for index in ACTIONS.size():
		var button: Button = $Panel/Rows.get_child(index)
		rows.append(button)
		button.mouse_entered.connect(select_option.bind(index))
		button.pressed.connect(choose.bind(index))
	select_option(0)

func open() -> void:
	select_option(0)
	show()

func select_option(index: int) -> void:
	selected_index = wrapi(index, 0, rows.size())
	for i in rows.size(): rows[i].set_pressed_no_signal(i == selected_index)

func choose(index: int) -> void:
	if not visible: return
	select_option(index)
	hide()
	chosen.emit(ACTIONS[selected_index])

func dismiss() -> void:
	hide()
	dismissed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed: return
	var viewport := get_viewport()
	match event.keycode:
		KEY_UP: select_option(selected_index - 1)
		KEY_DOWN: select_option(selected_index + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: choose(selected_index)
		KEY_ESCAPE: dismiss()
		_: return
	viewport.set_input_as_handled()
