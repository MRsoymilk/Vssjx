extends "res://scripts/interface/adapters/common/godot_text_input.gd"
## Inject only the IME boolean; real native focus/field validation still runs.
var composing := false

func _is_composing(_field: LineEdit) -> bool:
	return composing
