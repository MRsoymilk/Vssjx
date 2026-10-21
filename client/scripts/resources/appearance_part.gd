@tool
class_name NativeAppearancePart
extends Resource
@export_file("*.png") var texture_path := ""
@export var regions: Array[Rect2i] = []
func to_spec() -> Dictionary:
	return {"texture":texture_path,"frames":regions.map(func(r:Rect2i)->Array:return [r.position.x,r.position.y,r.size.x,r.size.y])}
