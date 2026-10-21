@tool
class_name NativeAppearanceRecipe
extends Resource
## Original per-frame draw order, part selection and placement, editable in Inspector.
@export var sources: Array = []:
	set(value):sources=value;emit_changed()
@export var frames: Array = []:
	set(value):frames=value;emit_changed()
@export var sequences: Array = []:
	set(value):sequences=value;emit_changed()
@export var opaque_tail_hex := "":
	set(value):opaque_tail_hex=value;emit_changed()
func to_spec() -> Dictionary:
	return {"sources":sources.duplicate(),"frames":frames.duplicate(true),"sequences":sequences.duplicate(true),"opaque_tail_hex":opaque_tail_hex}
