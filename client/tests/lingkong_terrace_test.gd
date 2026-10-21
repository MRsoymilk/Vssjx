extends Node
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	Game.save_path="user://lingkong_terrace_%d.json"%OS.get_process_id()
	Game.new_player("坡道通行检查",1,0);AIWorld.prepare()
	Game.player.ai_map="ai_001";Game.player.cell=[7,21]
	var viewport:=SubViewport.new();viewport.size=Vector2i(512,512)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var world:=ShushanWorld.new();viewport.add_child(world);world.enabled=false
	world.camera.position=Vector2(256,256)
	var steps:=[[50,51,52],[60,61,62],[70,71,72]]
	for dy in 3:
		for dx in 3:
			var cell:=Vector2i(10+dx,24+dy)
			check(not world.astar.is_point_solid(cell),"Every stair cell is walkable")
			check(world.terrain.get_cell_atlas_coords(cell)==Vector2i(steps[dy][dx]%32,steps[dy][dx]/32),"Native scene uses the whole staircase prefab")
	for x in range(10,13):
		var route:=world.astar.get_id_path(Vector2i(x,22),Vector2i(x,29))
		check(route.size()==8,"Upper lawn connects directly to the southern landing")
	for x in [8,9,13,14]:
		check(world.astar.is_point_solid(Vector2i(x,25)),"Visible terrace cliff is solid")
		check(not world.astar.is_point_solid(Vector2i(x,26)),"Ground below the cliff remains walkable")
	check(not world.astar.get_id_path(Vector2i(7,21),Vector2i(11,26)).is_empty(),"Screenshot player position reaches the former blocked mound")
	for r in SharedWorldMap.population("ai_001"):
		check(not world.astar.get_id_path(Vector2i(11,26),Vector2i(r.cell[0],r.cell[1])).is_empty(),"Terrace reaches NPC/monster: "+r.id)
	for gate in SharedWorldMap.exits("ai_001"):
		check(not world.astar.get_id_path(Vector2i(11,26),Vector2i(gate.cell[0],gate.cell[1])).is_empty(),"Terrace reaches existing transfer point")
	world.enabled=true
	world.path=world._route_to(Vector2i(11,22));world.move_target.set_destination(Vector2i(11,22))
	for frame in 240:
		world._process(1.0/30.0)
		if world.cell==Vector2i(11,22) and world.next_cell.x<0:break
	check(world.cell==Vector2i(11,22) and world.hero.position.is_equal_approx(world.cell_center(Vector2i(11,22))),"Player walks from the screenshot position around the cliff and up onto the platform")
	world.enabled=false;world.camera.position=Vector2(256,256)
	var folder:=OS.get_environment("SSJX_LINGKONG_CAPTURE")
	if not folder.is_empty() and DisplayServer.get_name()!="headless":
		for mode in ["full","detail"]:
			if mode=="detail":
				viewport.size=Vector2i(320,320);world.camera.position=world.cell_center(Vector2i(11,23))
			for frame in 2:await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(viewport.get_texture().get_image().save_png(folder.path_join(mode+".png"))==OK,"Capture real terrace map: "+mode)
	viewport.free()
	print("LINGKONG TERRACE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
