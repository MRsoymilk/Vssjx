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
	Game.save_path="user://map_distribution_%d.json" % OS.get_process_id()
	Game.new_player("地图分布检查",1,0)
	AIWorld.prepare()
	var output := OS.get_environment("SSJX_MAP_CAPTURE_PATH")
	for id in ["ai_007","ai_012","ai_013","ai_021","ai_028","ai_029","ai_030","ai_032","ai_041","ai_043","ai_045","ai_046","ai_103"]:
		var data := AIWorld.map_data(id)
		Game.player.ai_map=id; Game.player.cell=data.spawn.duplicate()
		var viewport := SubViewport.new()
		viewport.size=Vector2i(512,512); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var world := ShushanWorld.new()
		viewport.add_child(world); world.enabled=false
		world.camera.position=Vector2(256,256)
		for r in data.residents:
			var point := Vector2i(r.cell[0],r.cell[1])
			check(not world.astar.is_point_solid(point),"Resident on walkable ground: "+r.id)
			var sprite: AnimatedSprite2D=world.ai_npcs[r.id] if r.kind=="npc" else world.enemy_nodes[r.id]
			check(sprite.position==world.cell_center(point),"Runtime uses shared cell: "+r.id)
			check(sprite.get_meta("art_key")==r.art,"Appearance retained: "+r.id)
			if r.kind!="npc":
				var tag: Label=sprite.get_child(0)
				check(tag.text=="%d级 %s" % [int(r.level),String(r.name)],"Local monster name shows its configured level: "+r.id)
				check(tag.get_theme_color("font_color")==Color("ff3030"),"Local monster name is red: "+r.id)
				for y in range(point.y-2,point.y+3):
					for x in range(point.x-2,point.x+3):
						if world.astar.is_in_boundsv(Vector2i(x,y)): world.astar.set_point_solid(Vector2i(x,y),true)
		for r in data.residents:
			if r.kind=="npc":
				check(not world.astar.get_id_path(Vector2i(data.spawn[0],data.spawn[1]),Vector2i(r.cell[0],r.cell[1])).is_empty(),"Service reachable while bypassing patrols: "+r.id)
		for gate in data.exits:
			for p in gate.get("cells",[gate.cell]):
				check(not world.astar.get_id_path(Vector2i(data.spawn[0],data.spawn[1]),Vector2i(p[0],p[1])).is_empty(),"Arrival route bypasses patrols: "+id+"/"+gate.id)
		await get_tree().process_frame
		if not output.is_empty() and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(output.path_join(id+".png"))==OK,"Save map render: "+id)
		viewport.free()
	print("MAP DISTRIBUTION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
