class_name BoneglowEquipment
extends RefCounted
## Approved AI designs, adapted to the existing ANI layers and frame coordinates.
const PATH := "res://assets/data/boneglow-equipment.json"
static var _manifest: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty(): _manifest = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _manifest

static func replacements(stem: String, weapon: int, clothing: int, head: int, sources: Array) -> Dictionary:
	var result := {}
	for definition in manifest().sets:
		if definition.stem != stem: continue
		if weapon == int(definition.weapon_code): result[sources[2]] = definition.weapon
		if clothing == int(definition.clothing_code):
			for index in 3: result[sources[[1,3,4][index]]] = definition.body[index]
		if head == int(definition.head_code): result[sources[0]] = definition.head
	return result
