class_name AppearanceResources
extends RefCounted
## Godot-native visual library. No JSON loading, and no eager texture references.
const PATH := "res://assets/appearance_resources/catalog.tres"
static var _catalog: NativeAppearanceCatalog
static var _parts: Dictionary = {}
static var _recipes: Dictionary = {}
static var _equipment:Dictionary={}
static var _defaults:Dictionary={}
static var _creation:Dictionary={}
static var _outfits:Dictionary={}
static var _outfit_order:Array[String]=[]
static var revision:=0
static func invalidate()->void:revision+=1
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
static func equipment(stem:String,slot:String,code:int)->NativeHeroEquipment:
	var key:="%s/%s/%d"%[stem,slot,code]
	if not catalog().equipment.has(key):return null
	if not _equipment.has(key):_equipment[key]=load(catalog().equipment[key])
	return _equipment[key]
static func default_outfit(stem:String)->NativeHeroOutfit:
	if not catalog().defaults.has(stem):return null
	if not _defaults.has(stem):
		_defaults[stem]=load(catalog().defaults[stem])
		if not _defaults[stem].changed.is_connected(invalidate):_defaults[stem].changed.connect(invalidate)
	return _defaults[stem]
static func creation_outfit(stem:String)->NativeHeroOutfit:
	if not catalog().creation.has(stem):return null
	if not _creation.has(stem):
		_creation[stem]=load(catalog().creation[stem])
		if not _creation[stem].changed.is_connected(invalidate):_creation[stem].changed.connect(invalidate)
	return _creation[stem]
static func outfit(stem:String,codes:Array)->NativeHeroOutfit:
	var standard:=default_outfit(stem)
	if standard==null or codes.size()!=3:return null
	if codes==[1,0,0]:return standard if standard.valid() else null
	var key:="%s/%d/%d/%d"%[stem,int(codes[0]),int(codes[1]),int(codes[2])]
	if _outfits.has(key):return _outfits[key]
	var result:=NativeHeroOutfit.new();result.stem=stem;result.recipe=recipe(stem)
	result.weapon=equipment(stem,"weapon",int(codes[0]));result.clothing=equipment(stem,"clothing",int(codes[1]));result.head=equipment(stem,"head",int(codes[2]))
	if not result.valid():return null
	result.changed.connect(invalidate)
	_outfits[key]=result;_outfit_order.append(key)
	while _outfit_order.size()>6:_outfits.erase(_outfit_order.pop_front())
	return result
static func part_specs(sources:Array=[]) -> Dictionary:
	var specs:Dictionary={}
	for source in catalog().parts if sources.is_empty() else sources: specs[source]=part(source).to_spec()
	return specs
static func recipe_specs() -> Dictionary:
	var specs:Dictionary={}
	for stem in catalog().recipes: specs[stem]=recipe(stem).to_spec()
	return specs
