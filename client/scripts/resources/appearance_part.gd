@tool
class_name NativeAppearancePart
extends Resource
@export var source_id := "":
	set(value):source_id=value;emit_changed()
@export_file("*.png") var texture_path := "":
	set(value):texture_path=value;emit_changed()
@export var regions: Array[Rect2i] = []:
	set(value):regions=value;emit_changed()
func to_spec() -> Dictionary:
	return {"texture":texture_path,"frames":regions.map(func(r:Rect2i)->Array:return [r.position.x,r.position.y,r.size.x,r.size.y])}
