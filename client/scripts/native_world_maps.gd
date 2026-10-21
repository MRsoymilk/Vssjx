class_name NativeWorldMaps
extends RefCounted
## Native presentation only. SharedWorldMap retains authoritative gameplay data.
const PATH:="res://assets/map_resources/catalog.tres"
static var _catalog:NativeMapCatalog
static func scene(map_id:String)->PackedScene:
	if _catalog==null:_catalog=load(PATH)
	if not _catalog.scenes.has(map_id):return null
	return load(_catalog.scenes[map_id]) as PackedScene
static func build(terrain:TileMapLayer,map_id:String)->void:
	var packed:=scene(map_id)
	assert(packed!=null,"Missing native world scene: "+map_id)
	var world:=packed.instantiate()
	var ground:TileMapLayer=world.get_node("Ground")
	terrain.clear();terrain.tile_set=ground.tile_set;terrain.tile_map_data=ground.tile_map_data
	terrain.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	world.free()
static func add_scenery(parent:Node2D,map_id:String)->void:
	var packed:=scene(map_id)
	assert(packed!=null,"Missing native world scene: "+map_id)
	var world:=packed.instantiate()
	var scenery:Node2D=world.get_node("Scenery")
	# Flatten into the live Y-sorted layer so moving actors and roofs share order.
	for child in scenery.get_children():
		child.owner=null;scenery.remove_child(child);parent.add_child(child)
	world.free()
