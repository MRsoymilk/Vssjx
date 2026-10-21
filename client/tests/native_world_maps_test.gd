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
		check(world.get_meta("navigation_sha256")==NativeWorldMaps.navigation_hash(data),"Native/server geometry signature: "+id)
		check(ground.get_used_cells().size()==1024,"Full native terrain: "+id)
		var terrain:=TileMapLayer.new();var grid:=AStarGrid2D.new()
		SharedWorldMap.build(terrain,grid,data)
		var preview:=NativeWorldMaps.preview(id)
		check(preview.tiles.size()==1024,"Native preview is complete: "+id)
		for i in 1024:
			var p:=Vector2i(i%32,i/32)
			check(terrain.get_cell_atlas_coords(p)==ground.get_cell_atlas_coords(p),"Live renderer uses native terrain: %s/%d"%[id,i])
			check(grid.is_point_solid(p)==bool(data.blocked[i]),"Server collision parity: %s/%d"%[id,i])
		var scenery:=Node2D.new();scenery.y_sort_enabled=true
		SharedWorldMap.add_scenery(scenery,data)
		check(scenery.get_child_count()>=data.scenery.size(),"All original native scenery retained: "+id)
		for i in data.scenery.size():
			var prop:Dictionary=data.scenery[i];var actor:=scenery.get_child(i)
			check(actor.position==Vector2(prop.x,prop.y) and actor.art_key==prop.art,"Native scenery identity/anchor: "+id)
		for actor in scenery.get_children():
			if actor is TileMapLayer:
				check(not actor.y_sort_enabled and actor.position.y>0,"Roofs sort as one building at its foundation: "+id)
				for p in actor.get_used_cells():
					var cell:Vector2i=p+Vector2i(actor.position/16);var atlas:Vector2i=actor.get_cell_atlas_coords(p)
					check(int(preview.tiles[cell.y*32+cell.x])==atlas.y*32+atlas.x,"Preview includes native roof: "+id)
			elif actor is NativeActorSprite:
				var cell:Vector2i=Vector2i(actor.position/16)
				check(bool(data.blocked[cell.y*32+cell.x]),"No new trunk on any server walkable cell: "+id)
		check(not grid.is_point_solid(Vector2i(data.spawn[0],data.spawn[1])),"Saved arrival preserved: "+id)
		scenery.free();terrain.free();world.free()
	check(not SharedWorldMap.load_data("ai_001").blocked[15*32+12],"Endless guardian at [12,15] stays reachable")
	check(NativeWorldMaps._previews.size()<=6,"Preview cache remains bounded across all 216 maps")
	var folder:=OS.get_environment("SSJX_MAP_CAPTURE")
	if not folder.is_empty() and DisplayServer.get_name()!="headless":
		await _capture(ids,folder)
		await _roof_sort_test(folder)
	print("NATIVE WORLD MAPS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
func _capture(ids:Array,folder:String)->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,512)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	for id in ids:
		var world:=NativeWorldMaps.scene(id).instantiate();viewport.add_child(world)
		var data:=SharedWorldMap.load_data(id)
		var layer:Node2D=world.get_node("Scenery")
		var hero:=OriginalArt.actor("hero/mck");hero.position=Vector2(data.spawn[0]*16+8,data.spawn[1]*16+8)
		hero.pause();layer.add_child(hero)
		for r in SharedWorldMap.population(id):
			var actor:=OriginalArt.actor(r.art);actor.position=Vector2(r.cell[0]*16+8,r.cell[1]*16+8)
			actor.pause();layer.add_child(actor)
		for gate in SharedWorldMap.exits(id):
			for p in gate.get("cells",[gate.cell]):
				var marker:=Sprite2D.new();marker.texture=load("res://assets/ui/portal_tile.png")
				marker.centered=false;marker.position=Vector2(p[0]*16,p[1]*16);world.add_child(marker)
		for i in 2:await get_tree().process_frame
		RenderingServer.force_draw()
		check(viewport.get_texture().get_image().save_png(folder.path_join(id+".png"))==OK,"Actual native scene rendering: "+id)
		viewport.remove_child(world);world.free()
	viewport.free()
func _roof_sort_test(folder:String)->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,512)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var world:=NativeWorldMaps.scene("ai_021").instantiate();viewport.add_child(world)
	var marker:=Node2D.new();marker.position=Vector2(250,111)
	var square:=Polygon2D.new();square.color=Color.MAGENTA
	square.polygon=PackedVector2Array([Vector2(-6,-35),Vector2(6,-35),Vector2(6,0),Vector2(-6,0)])
	marker.add_child(square);world.get_node("Scenery").add_child(marker)
	for i in 2:await get_tree().process_frame
	RenderingServer.force_draw()
	var behind:=viewport.get_texture().get_image()
	check(behind.get_pixel(250,97)!=Color.MAGENTA,"Actual building pixels occlude an actor north of the foundation")
	behind.save_png(folder.path_join("roof-behind.png"))
	marker.position.y=113
	for i in 2:await get_tree().process_frame
	RenderingServer.force_draw()
	var front:=viewport.get_texture().get_image()
	check(front.get_pixel(250,97)==Color.MAGENTA,"Actual actor pixels cover the building south of the foundation")
	front.save_png(folder.path_join("roof-front.png"));viewport.free()
