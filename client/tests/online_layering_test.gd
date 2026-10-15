extends "res://tests/population_test.gd"

func render_world(view: OnlineWorldView) -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.viewport.get_texture().get_image()

func _run() -> void:
	var old := Game.player.duplicate(true)
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = SELF
	add_child(view)
	view.network.set_process(false)
	view.set_process(false)
	view.network.world_ready = true
	view.network.entities = {SELF:entity(SELF,1,"青衫客",1,0,[8,7])}
	view.network.changed.emit(view.network.entities)
	view.network.population.receive(residents_packet())
	var trees: Array[Node] = []
	for child in view.actor_layer.get_children():
		if child is AnimatedSprite2D: trees.append(child)
	check(trees.size() == view.map_data.scenery.size(), "Trees share the foot-position sorting layer with online actors")
	check(view.get_node("Viewport/Scene/Terrain").z_index < view.actor_layer.z_index, "Terrain stays below the shared actors and scenery")
	check(view.actors[SELF].root.z_index == trees[0].z_index and view.residents.qingwei.z_index == trees[0].z_index, "Players, NPCs and monsters cannot override scenery with a fixed higher layer")
	check(view.actor_layer.y_sort_enabled and not view._motion_grid.is_point_solid(Vector2i(8,7)) and view._motion_grid.is_point_solid(Vector2i(8,8)), "Canopy remains passable while the trunk remains blocked")
	if DisplayServer.get_name() != "headless":
		var hero: AnimatedSprite2D = view.actors[SELF].sprite
		for child in view.actors[SELF].root.get_children():
			if child != hero: child.hide()
		for resident in view.residents.values(): resident.hide()
		var tree: AnimatedSprite2D
		for item in trees:
			item.hide()
			if item.position == Vector2(136,136): tree = item
		check(tree != null, "Tree reproduction uses the exported online map")
		view.camera.position = Vector2(160,187.5)
		hero.pause()
		hero.set_frame_and_progress(0,0)
		for front in [false,true]:
			var value := entity(SELF,1,"青衫客",1,0,[8,9] if front else [8,7])
			value.world_epoch = "2" if front else "1"
			view.network.entities = {SELF:value}
			view.network.changed.emit(view.network.entities)
			hero.pause()
			hero.set_frame_and_progress(0,0)
			view.actors[SELF].root.hide()
			tree.hide()
			var ground := await render_world(view)
			tree.show()
			var tree_only := await render_world(view)
			tree.hide()
			view.actors[SELF].root.show()
			var hero_only := await render_world(view)
			tree.show()
			var together := await render_world(view)
			var overlaps := 0
			var correct := 0
			for y in range(40,180):
				for x in range(100,180):
					var base := ground.get_pixel(x,y)
					var leaf := tree_only.get_pixel(x,y)
					var person := hero_only.get_pixel(x,y)
					if not base.is_equal_approx(leaf) and not base.is_equal_approx(person) and not leaf.is_equal_approx(person):
						overlaps += 1
						if together.get_pixel(x,y).is_equal_approx(person if front else leaf): correct += 1
			check(overlaps > 20 and correct >= overlaps * 0.98, "Rendered overlap puts the hero %s the tree: %d/%d correct pixels" % ["in front of" if front else "behind",correct,overlaps])
			output = OS.get_environment("SSJX_LAYERING_CAPTURE_PATH")
			await capture("tree_front" if front else "tree_behind")
	check(Game.player == old, "Scenery sorting does not change offline progress")
	view.queue_free()
	await get_tree().process_frame
	print("ONLINE LAYERING: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
