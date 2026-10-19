extends "res://tests/shared_interface_test.gd"

func _run() -> void:
	var old := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path="user://ai_world_test_%d.json" % OS.get_process_id()
	Game.new_player("试游修士",1,0)
	AIWorld.prepare()
	check(AIWorld.maps.size()==214 and AIWorld.quests.size()==642,"Entire AI directory and three-stage quest chains")
	check(AIWorld.catalog_hash==FileAccess.get_file_as_string(AIWorld.PATH).replace("\r\n","\n").sha256_text(),"Client hashes the canonical LF shared bundle")
	Game.player.cell=[3,16]
	check(AIWorld.apply_local("ai_travel","ai_001").is_empty(),"Enter AI map from station")
	check(AIWorld.local_map_id()=="ai_001","Map identity persists separately from tutorial zone")
	check(not AIWorld.apply_local("ai_accept","ai_001_q1").is_empty(),"Cannot accept quest remotely")
	Game.player.cell=[10,14]
	check(AIWorld.apply_local("ai_accept","ai_001_q1").is_empty(),"Accept first quest near guide")
	check(not AIWorld.apply_local("ai_accept","ai_001_q2").is_empty(),"Must finish prerequisite")
	Game.player.cell=[23,10]
	check(not AIWorld.apply_local("ai_interact","ai_001_courier").is_empty(),"Ordered survey before delivery")
	Game.player.cell=[22,23]
	check(AIWorld.apply_local("ai_interact","ai_001_survey").is_empty(),"Survey landmark")
	Game.player.cell=[23,10]
	check(AIWorld.apply_local("ai_interact","ai_001_courier").is_empty(),"Deliver findings")
	Game.player.cell=[10,14]
	var gold := int(Game.player.gold)
	check(AIWorld.apply_local("ai_claim","ai_001_q1").is_empty(),"Claim with guide")
	check(int(Game.player.gold)==gold+int(AIWorld.quest("ai_001_q1").gold),"Rewards come from definition")
	check(not AIWorld.apply_local("ai_claim","ai_001_q1").is_empty(),"Cannot claim twice")
	check(AIWorld.apply_local("ai_accept","ai_001_q2").is_empty(),"Unlock second chapter")
	var enemy := AIWorld.resident("ai_001_mob")
	Game.finish_enemy(enemy)
	check(not Game.enemy_available(enemy.id) and int(AIWorld.progress().active.ai_001_q2[0])==1,"Kill updates AI quest and respawn deadline")
	check(Game.player.defeated.is_empty() and int(Game.player.quest)==0,"Expansion leaves tutorial masks/stage intact")
	check(Game.valid_save(Game.player),"AI character validates for local saves")
	var saved := await Game.save_game()
	Game.player={}
	var loaded := await Game.load_game()
	check(saved.ok and loaded.ok and AIWorld.local_map_id()=="ai_001" and AIWorld.progress().active.has("ai_001_q2"),"Map and objectives survive storage roundtrip")
	var app: Control=load("res://scenes/main.tscn").instantiate()
	add_child(app);app._enter_world()
	check(app.world.ai_npcs.size()==3 and app.world.enemy_nodes.size()==1,"AI map renders NPCs and hides defeated monster")
	var names: Control=app.world_view.get_node("WorldNameplates")
	for facing in [true,false]:
		app.world._face_actor(app.world.hero,facing)
		names._process(0.0)
		var tag: Label=app.world.hero.get_child(0)
		var proxy: Label=names.entries[tag.get_instance_id()].proxy
		check(proxy.scale.x>0 and absf(proxy.position.x+proxy.size.x*0.5-app.world.hero.get_global_transform_with_canvas().origin.x)<0.1,"Readable name remains centered and unmirrored in either direction")
	app.world._face_actor(app.world.hero,true)
	var marker: Node2D=app.world.portal_marker
	check(marker.ground is Sprite2D and marker.ground.texture==load("res://assets/ui/portal_tile.png") and marker.position==app.world.cell_center(AIWorld.station("ai_001")),"Original cyan spiral tile occupies its actual transfer cell")
	check(marker.get_child(0) is Label,"Native internal visuals preserve portal label and interaction API")
	check(marker.get_child_count(true)==2,"Portal has tile and destination label, without selection arrows or hovering pin")
	app._open_ai("quests","ai_001_guide")
	check(app.modal is OriginalNpcDialog and not app.world.enabled,"AI NPC reuses the original online paper dialogue in local mode")
	output=OS.get_environment("SSJX_AI_CAPTURE_PATH") if DisplayServer.get_name()!="headless" else ""
	await capture("ai-quests")
	app._open_ai("quests")
	app.modal.selected_quest="ai_001_q2";app.modal.refresh()
	await capture("ai-task-detail")
	app._open_ai("maps");app.modal.selected_map="ai_004";app.modal.refresh()
	await capture("ai-map-detail")
	app._close_modal()
	check(app.world.enabled,"Closing expansion panel resumes movement")
	var exit: Dictionary=SharedWorldMap.exits("ai_001")[1]
	app.world._walk_to({"kind":"map_exit","cell":Vector2i(exit.cell[0],exit.cell[1]),"data":exit})
	var deadline := Time.get_ticks_msec()+15000
	while AIWorld.local_map_id()!=exit.target_map and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(AIWorld.local_map_id()==exit.target_map and app.modal==null,"Walking onto the pad transfers directly without a directory or confirmation")
	while app.map_transition != null and app.map_transition.blocking and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(app.world.map_id==exit.target_map and app.world.enabled,"New local map is revealed only after its loading animation completes")
	Game.player.ai_map="ai_021";Game.player.cell=[16,22]
	app._enter_world()
	check(app.world.ai_npcs.size()==4,"Flower sect uses the four screenshot/table NPC identities")
	var strips := 0
	for portal_node in app.world.actors.get_children():
		if portal_node.get_script()!=preload("res://scripts/portal.gd"):continue
		if portal_node.gate.get("cells",[]).size()!=3:continue
		strips+=1
		check(portal_node.get_child_count(true)==4,"Three native ground tiles and one nameplate render each exit strip")
	check(strips==2,"Left and right flower-sect exits use vertical three-tile strips")
	for gate in SharedWorldMap.exits("ai_021"):
		for point in gate.get("cells",[gate.cell]):
			check(SharedWorldMap.exit_at("ai_021",Vector2i(point[0],point[1])).get("target_map")==gate.target_map,"Every visible strip cell triggers the matching destination")
	check(SharedWorldMap.exit_at("ai_021",Vector2i(4,27)).is_empty(),"Adjacent normal path does not trigger transfer")
	await capture("flower-sect-reference")
	Game.player.ai_map="ai_213";Game.player.cell=[15,26]
	app._enter_world()
	check(app.world.ai_npcs.size()==7,"Camp has its seven distinct service/social residents")
	check(app.world.actors.get_children().filter(func(n: Node)->bool:return n.get_script()==preload("res://scripts/portal.gd")).size()==2,"Only two real transfer exits render in the camp")
	for old_cell in [Vector2i(19,3),Vector2i(18,27)]:
		check(SharedWorldMap.exit_at("ai_213",old_cell).is_empty(),"Removed decorative portals no longer trigger transfer")
	app._open_ai("quests","ai_213_npc03")
	var labels: Array = app.modal.find_children("*","Label",true,false)
	check(labels.any(func(n: Label)->bool:return n.text==AIWorld.resident("ai_213_npc03").dialogue),"Ambient NPC exposes its own readable dialogue")
	check(not app.modal.find_children("*","Button",true,false).any(func(n: Button)->bool:return n.text.begins_with("调查 / 传讯")),"Ambient conversation does not send a fake quest-objective request")
	app._close_modal()
	Game.player.ai_map="ai_002"
	var giver := AIWorld.resident("ai_002_guide")
	var region := AIWorld.map_data("ai_002")
	for offset in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var cell: Vector2i = Vector2i(giver.cell[0],giver.cell[1])+offset
		if not region.blocked[cell.y*32+cell.x]:Game.player.cell=[cell.x,cell.y];break
	app._enter_world()
	app._open_ai("quests")
	app.modal.selected_quest="ai_002_q1";app.modal.refresh()
	check(app.modal.find_children("*","Button",true,false).any(func(n: Button)->bool:return n.text=="前往发布人交谈"),"Journal routes to conversation rather than accepting remotely")
	app._ai_requested("ai_talk","ai_002_guide")
	var talk_deadline := Time.get_ticks_msec()+5000
	while not app.modal is OriginalNpcDialog and Time.get_ticks_msec()<talk_deadline:await get_tree().process_frame
	check(app.modal is OriginalNpcDialog and not AIWorld.progress().active.has("ai_002_q1"),"Reaching the giver opens a conversation without automatic acceptance")
	if app.modal is OriginalNpcDialog:
		check(app.modal.quest_button.text.contains("接受"),"Original task option offers explicit acceptance")
		await capture("local-ai-npc-accept")
		var talk_dialog: OriginalNpcDialog=app.modal
		talk_dialog.quest_button.pressed.emit();talk_dialog.quest_button.pressed.emit()
		await Game.wait_for_storage();await get_tree().process_frame
		check(AIWorld.progress().active.has("ai_002_q1") and app.modal==null and app.world.enabled,"One local task click saves and returns to the map")
	var marker_value := AIWorld.npc_marker("ai_002_survey",AIWorld.progress(),int(Game.player.level))
	check(marker_value.stage==2 and AIWorld.npc_marker("ai_002_courier",AIWorld.progress(),int(Game.player.level)).stage==-1,"Only the currently ordered objective shows the original quest marker")
	if not output.is_empty():
		var seen_biomes := {}
		for id in AIWorld.maps:
			var m: Dictionary = AIWorld.maps[id]
			if seen_biomes.has(m.biome): continue
			seen_biomes[m.biome] = true
			Game.player.ai_map=id; Game.player.cell=m.spawn.duplicate()
			app._enter_world()
			await capture("scene-"+m.biome)
	var grid:=AStarGrid2D.new();var terrain:=TileMapLayer.new()
	for id in AIWorld.maps:
		var m: Dictionary=SharedWorldMap.load_data(id)
		SharedWorldMap.build(terrain,grid,m)
		for r in SharedWorldMap.population(id):
			check(not grid.get_id_path(Vector2i(m.spawn[0],m.spawn[1]),Vector2i(r.cell[0],r.cell[1])).is_empty(),"NPC/monster reachable "+r.id)
		for gate in m.exits:
			for point in gate.get("cells",[gate.cell]):
				check(not grid.get_id_path(Vector2i(m.spawn[0],m.spawn[1]),Vector2i(point[0],point[1])).is_empty(),"Transfer pad reachable "+id+" "+gate.target_map)
	terrain.free()
	app.queue_free()
	await get_tree().process_frame
	Game.player=old;Game.save_path=old_path
	print("AI WORLD: %d checks, %d failures" % [checks,failures]);get_tree().quit(0 if failures==0 else 1)
