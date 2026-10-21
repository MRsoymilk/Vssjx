extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("NATIVE MAP: "+text)
func _ready()->void:_run.call_deferred()
func _run()->void:
	AIWorld.prepare()
	var ids:Array=["qingyun_trail","ancient_ruins"]+AIWorld.maps.keys()
	var registry:NativeMapCatalog=load(NativeWorldMaps.PATH)
	check(registry.scenes.size()==216,"All 216 playable maps have a native scene")
	var tileset:TileSet=load("res://assets/map_resources/original_tiles.tres")
	check(tileset.get_source(0).get_tiles_count()==756,"Native TileSet covers the original atlas")
	for id in ids:
		var data:=SharedWorldMap.load_data(id)
		var world:=NativeWorldMaps.scene(id).instantiate()
		var ground:TileMapLayer=world.get_node("Ground")
		check(world.get_meta("map_id")==id and ground.tile_set==tileset,"Native identity and shared TileSet: "+id)
		check(ground.get_used_cells().size()==1024,"Full native terrain: "+id)
		var terrain:=TileMapLayer.new();var grid:=AStarGrid2D.new()
		SharedWorldMap.build(terrain,grid,data)
		for i in 1024:
			var p:=Vector2i(i%32,i/32);var t:=int(data.tiles[i])
			check(terrain.get_cell_atlas_coords(p)==Vector2i(t%32,t/32),"Exact baked terrain: %s/%d"%[id,i])
			check(grid.is_point_solid(p)==bool(data.blocked[i]),"Server collision parity: %s/%d"%[id,i])
		var scenery:=Node2D.new();scenery.y_sort_enabled=true
		SharedWorldMap.add_scenery(scenery,data)
		check(scenery.get_child_count()==data.scenery.size(),"All native scenery: "+id)
		for i in scenery.get_child_count():
			var prop:Dictionary=data.scenery[i];var actor:=scenery.get_child(i)
			check(actor.position==Vector2(prop.x,prop.y) and actor.art_key==prop.art,"Native scenery identity/anchor: "+id)
		check(not grid.is_point_solid(Vector2i(data.spawn[0],data.spawn[1])),"Saved arrival preserved: "+id)
		scenery.free();terrain.free();world.free()
	check(not SharedWorldMap.load_data("ai_001").blocked[15*32+12],"Endless guardian at [12,15] stays reachable")
	print("NATIVE WORLD MAPS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
