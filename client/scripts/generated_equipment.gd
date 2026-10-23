class_name GeneratedEquipment
extends RefCounted
## Data-driven native-layer registry for all additional equipment families.
const FAMILIES := [
	{"id":"boneglow","name":"骨甲幽光","path":"res://assets/appearance_resources/families/boneglow.tres"},
	{"id":"gravebloom","name":"冥林异装","path":"res://assets/appearance_resources/families/gravebloom.tres"},
	{"id":"eva01","name":"初号机","path":"res://assets/appearance_resources/families/eva01.tres"},
	{"id":"legendary","name":"传世兵器","path":"res://assets/appearance_resources/families/legendary.tres"},
	{"id":"vow","name":"誓约礼装","path":"res://assets/appearance_resources/families/vow.tres"}
]
const NATIVE_LIMITS := [27,11,9]
static var _data: Dictionary = {}

static func manifest() -> Dictionary:
	if _data.is_empty():
		_data = {"sets":[],"weapons":[],"parts":{}}
		for family in FAMILIES:
			var source:NativeEquipmentFamily=load(family.path)
			_data.sets.append_array(source.sets)
			_data.weapons.append_array(source.weapons)
			_data.parts.merge(AppearanceResources.part_specs(source.parts))
	return _data

static func appearance_limits() -> Array:
	var result := NATIVE_LIMITS.duplicate()
	for definition in manifest().sets+manifest().weapons:
		for index in 3:
			result[index] = maxi(result[index],int(definition.get(["weapon_code","clothing_code","head_code"][index],0)))
	return result

static func valid_key(stem: String, look: Array) -> bool:
	for index in 3:
		if int(look[index]) <= NATIVE_LIMITS[index]: continue
		var found := false
		for definition in manifest().sets+manifest().weapons:
			if definition.stem == stem and int(definition.get(["weapon_code","clothing_code","head_code"][index],-1)) == int(look[index]): found = true; break
		if not found: return false
	return true

static func replacements(stem: String, weapon: int, clothing: int, head: int, sources: Array) -> Dictionary:
	var result := {}
	for definition in manifest().sets+manifest().weapons:
		if definition.stem != stem: continue
		if weapon == int(definition.weapon_code): result[sources[2]] = definition.weapon
		if clothing == int(definition.get("clothing_code",-1)):
			for index in 3: result[sources[[1,3,4][index]]] = definition.body[index]
		if head == int(definition.get("head_code",-1)): result[sources[0]] = definition.head
	return result

static func family_for_category(category: String) -> String:
	for family in FAMILIES:
		if category == family.name+" · 本角色": return family.id
	return ""
