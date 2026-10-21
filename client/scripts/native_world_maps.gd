class_name NativeWorldMaps
extends RefCounted
## Native presentation only. SharedWorldMap retains authoritative gameplay data.
const PATH:="res://assets/map_resources/catalog.tres"
static var _catalog:NativeMapCatalog
static var _previews:Dictionary={}
static var _preview_order:Array[String]=[]
static func scene(map_id:String)->PackedScene:
	if _catalog==null:_catalog=load(PATH)
	if not _catalog.scenes.has(map_id):return null
	return load(_catalog.scenes[map_id]) as PackedScene
static func navigation_hash(data:Dictionary)->String:
	return JSON.stringify({"width":int(data.width),"height":int(data.height),"cell_size":int(data.cell_size),"blocked":data.blocked},"",true).sha256_text()
static func build(terrain:TileMapLayer,data:Dictionary)->void:
	var map_id:=String(data.map_id)
	var packed:=scene(map_id)
	assert(packed!=null,"Missing native world scene: "+map_id)
	var world:=packed.instantiate()
	assert(world.get_meta("navigation_sha256")==navigation_hash(data),"Rebuild native map after changing server geometry: "+map_id)
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
static func preview(map_id:String)->Dictionary:
	if _previews.has(map_id):return _previews[map_id]
	var packed:=scene(map_id)
	if packed==null:return {}
	var world:=packed.instantiate();var ground:TileMapLayer=world.get_node("Ground")
	var tiles:=PackedInt32Array();tiles.resize(1024)
	for point in ground.get_used_cells():
		var atlas:=ground.get_cell_atlas_coords(point);tiles[point.y*32+point.x]=atlas.y*32+atlas.x
	var props:Array=[]
	for child in world.get_node("Scenery").get_children():
		if child is TileMapLayer:
			for point in child.get_used_cells():
				var atlas:Vector2i=child.get_cell_atlas_coords(point)
				var p:Vector2i=point+Vector2i(child.position/16)
				tiles[p.y*32+p.x]=atlas.y*32+atlas.x
		elif child is NativeActorSprite:
			props.append({"art":child.art_key,"x":child.position.x,"y":child.position.y})
	world.free()
	var result:={"tiles":tiles,"scenery":props}
	_previews[map_id]=result;_preview_order.append(map_id)
	while _preview_order.size()>6:_previews.erase(_preview_order.pop_front())
	return result
