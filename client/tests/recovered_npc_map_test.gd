extends Node
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await Game.when_ready()
	Game.save_path="user://recovered_npc_map_test_%d.json" % OS.get_process_id()
	Game.new_player("人物适配检查", 1, 0)
	AIWorld.prepare()
	var representatives := {}
	for m in AIWorld.maps.values():
		for r in m.residents:
			if r.kind=="npc" and String(r.art).begins_with("npc/"): representatives[r.art]=r
	check(representatives.size()==20,"All 20 recovered NPC appearances are in runtime maps")
	for key in representatives:
		var info := OriginalArt.actor_info(key)
		check(not info.is_empty(),"Valid actor metadata: "+key)
		var actor := OriginalArt.actor(key)
		add_child(actor)
		check(actor.scale==Vector2.ONE and actor.offset.y+int(info.height)-2==0,"Unscaled map pixel size and feet at ground: "+key)
		for mode in ["idle","walk","attack"]:
			check(actor.sprite_frames.get_frame_count(mode)==1,"Static appearance never plays fake movement: "+key)
		var image := actor.sprite_frames.get_frame_texture("idle",0).get_image()
		check(image!=null and image.get_height()<=64,"NPC atlas loads with a map-sized height: "+key)
		var opaque := Vector2.ZERO
		var found := false
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x,y).a>0.95:
					opaque=Vector2(x+0.5,y+0.5);found=true;break
			if found: break
		for facing in [1.0,-1.0]:
			actor.scale.x=facing
			check(WorldSpriteHit.hit(actor,actor.to_global(actor.offset+opaque)),"Visible NPC pixels remain clickable when mirrored: "+key)
			check(not WorldSpriteHit.hit(actor,actor.to_global(actor.offset-Vector2(8,8))),"Transparent exterior does not steal map clicks: "+key)
		actor.free()
		var resident: OnlineResident=preload("res://scenes/actors/online_resident.tscn").instantiate()
		add_child(resident)
		var value: Dictionary=representatives[key].duplicate(true)
		value.merge({"next_cell":null,"segment_progress":0,"world_epoch":"1","entity_revision":"0"})
		var population := OnlinePopulation.new()
		var epoch := "20000000-0000-4000-8000-000000000001"
		check(population.receive({"epoch":epoch,"revision":"1","entities":[value]}),"Network packet validates new NPC art against shared definitions: "+key)
		var forged := value.duplicate(true)
		forged.art="hero/mfs"
		check(not population.receive({"epoch":epoch,"revision":"2","entities":[forged]}),"Network packet rejects an unapproved NPC replacement: "+key)
		var grid := AStarGrid2D.new()
		grid.region=Rect2i(0,0,32,32);grid.cell_size=Vector2(16,16);grid.update()
		resident.receive(value,grid)
		check(resident.sprite.get_meta("art_key")==key,"Network population creates the same recovered sprite: "+key)
		check(resident.get_node("Name").text.begins_with(value.name),"Network name/identity preserved: "+key)
		check(resident.get_node("ServiceLabel").text==AIWorld.resident(value.id).service_label,"Network service label preserved: "+key)
		resident.free()
	var output := OS.get_environment("SSJX_NPC_CAPTURE_PATH")
	for id in ["ai_007","ai_021","ai_028","ai_032","ai_041"]:
		var data := AIWorld.map_data(id)
		Game.player.ai_map=id;Game.player.cell=data.spawn.duplicate()
		var viewport := SubViewport.new()
		viewport.size=Vector2i(512,512);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var world := ShushanWorld.new()
		viewport.add_child(world)
		world.enabled=false
		world.camera.position=Vector2(256,256)
		for r in data.residents:
			if r.kind!="npc":continue
			var sprite: AnimatedSprite2D=world.ai_npcs[r.id]
			check(sprite.position==world.cell_center(Vector2i(r.cell[0],r.cell[1])),"Local NPC retains original cell: "+r.id)
			check(sprite.get_meta("art_key")==r.art,"Local map uses shared NPC art: "+r.id)
			check(world.ai_markers.has(r.id),"NPC quest marker binding retained: "+r.id)
		await get_tree().process_frame
		if not output.is_empty() and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(output.path_join(id+".png"))==OK,"Save real map render: "+id)
		viewport.free()
	print("RECOVERED NPC MAPS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
