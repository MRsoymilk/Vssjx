@tool
class_name NativeAppearanceRecipe
extends Resource
## Original per-frame draw order, part selection and placement, editable in Inspector.
@export var sources: Array = []
@export var frames: Array = []
@export var sequences: Array = []
@export var opaque_tail_hex := ""
func to_spec() -> Dictionary:
	return {"sources":sources.duplicate(),"frames":frames.duplicate(true),"sequences":sequences.duplicate(true),"opaque_tail_hex":opaque_tail_hex}
