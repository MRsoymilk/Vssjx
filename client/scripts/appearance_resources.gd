class_name AppearanceResources
extends RefCounted
## Godot-native visual library. No JSON loading, and no eager texture references.
const PATH := "res://assets/appearance_resources/catalog.tres"
static var _catalog: NativeAppearanceCatalog
static var _parts: Dictionary = {}
static var _recipes: Dictionary = {}
static func catalog() -> NativeAppearanceCatalog:
	if _catalog==null: _catalog=load(PATH)
	return _catalog
static func part(source:String) -> NativeAppearancePart:
	if not catalog().parts.has(source): return null
	if not _parts.has(source): _parts[source]=load(catalog().parts[source])
	return _parts[source]
static func recipe(stem:String) -> NativeAppearanceRecipe:
	if not catalog().recipes.has(stem): return null
	if not _recipes.has(stem): _recipes[stem]=load(catalog().recipes[stem])
	return _recipes[stem]
static func part_specs(sources:Array=[]) -> Dictionary:
	var specs:Dictionary={}
	for source in catalog().parts if sources.is_empty() else sources: specs[source]=part(source).to_spec()
	return specs
static func recipe_specs() -> Dictionary:
	var specs:Dictionary={}
	for stem in catalog().recipes: specs[stem]=recipe(stem).to_spec()
	return specs
