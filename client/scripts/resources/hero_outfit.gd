@tool
class_name NativeHeroOutfit
extends Resource
## Assign this Resource on any of the six base hero scenes in the Inspector.
@export var stem := "":
	set(value):stem=value;_part_changed()
@export var recipe: NativeAppearanceRecipe:
	set(value):_unwatch(recipe);recipe=value;_watch(recipe);_part_changed()
@export var weapon: NativeHeroEquipment:
	set(value):_unwatch(weapon);weapon=value;_watch(weapon);_part_changed()
@export var clothing: NativeHeroEquipment:
	set(value):_unwatch(clothing);clothing=value;_watch(clothing);_part_changed()
@export var head: NativeHeroEquipment:
	set(value):_unwatch(head);head=value;_watch(head);_part_changed()
@export_storage var baked_signature := ""
var _signature_cache:=""
func _unwatch(resource:Resource)->void:
	if resource!=null and resource.changed.is_connected(_part_changed):resource.changed.disconnect(_part_changed)
func _watch(resource:Resource)->void:
	if resource!=null and not resource.changed.is_connected(_part_changed):resource.changed.connect(_part_changed)
func _part_changed()->void:_signature_cache="";emit_changed()
func valid()->bool:
	return stem in ["mzs","wzs","mck","wck","mfs","wfs"] and recipe!=null and recipe.sources.size()>=5 and String(recipe.sources[0]).begins_with(stem) and not recipe.frames.is_empty() and weapon!=null and clothing!=null and head!=null and weapon.valid_for(stem,"weapon") and clothing.valid_for(stem,"clothing") and head.valid_for(stem,"head")
func codes()->Array:return [weapon.visual_code,clothing.visual_code,head.visual_code]
func key()->String:return "hero/%s_w%d_c%d_h%d"%[stem,weapon.visual_code,clothing.visual_code,head.visual_code]
func signature()->String:
	if not valid():return ""
	if _signature_cache.is_empty():_signature_cache=JSON.stringify({"stem":stem,"recipe":recipe.to_spec(),"equipment":[weapon.signature_data(),clothing.signature_data(),head.signature_data()]},"",true).sha256_text()
	return _signature_cache
func uses_baked()->bool:return not baked_signature.is_empty() and signature()==baked_signature and not AppearanceEdits.any()
func replacements()->Dictionary:
	var result:Dictionary={}
	if not valid():return result
	if not weapon.parts.is_empty():result[recipe.sources[2]]=weapon.parts[0]
	result[recipe.sources[0]]=head.parts[0]
	for i in 3:result[recipe.sources[[1,3,4][i]]]=clothing.parts[i]
	return result
