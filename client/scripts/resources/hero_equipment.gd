@tool
class_name NativeHeroEquipment
extends Resource
## One interchangeable weapon, clothing set (body/front/back), or head style.
@export var stem := "":
	set(value):stem=value;emit_changed()
@export_enum("weapon","clothing","head") var slot := "weapon":
	set(value):slot=value;emit_changed()
@export_range(0,999) var visual_code := 0:
	set(value):visual_code=value;emit_changed()
@export var parts: Array[NativeAppearancePart] = []:
	set(value):
		for part in parts:
			if part!=null and part.changed.is_connected(_part_changed):part.changed.disconnect(_part_changed)
		parts=value
		for part in parts:
			if part!=null and not part.changed.is_connected(_part_changed):part.changed.connect(_part_changed)
		emit_changed()
func _part_changed()->void:emit_changed()
func valid_for(actor_stem:String,expected_slot:String)->bool:
	if stem!=actor_stem or slot!=expected_slot:return false
	var expected:=0 if slot=="weapon" and visual_code==0 else (3 if slot=="clothing" else 1)
	return parts.size()==expected and parts.all(func(p:NativeAppearancePart)->bool:return p!=null and not p.source_id.is_empty() and not p.texture_path.is_empty())
func signature_data()->Dictionary:
	return {"stem":stem,"slot":slot,"code":visual_code,"parts":parts.map(func(p:NativeAppearancePart)->Dictionary:return {"id":p.source_id,"spec":p.to_spec()} if p!=null else {})}
