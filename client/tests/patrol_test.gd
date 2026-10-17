extends Node
var checks := 0
var failures := 0
func _ready() -> void: call_deferred("_run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + text)
func _run() -> void:
	await Game.when_ready()
	var old := Game.player.duplicate(true)
	Game.new_player("巡逻测试", 0, 0)
	var world := ShushanWorld.new()
	add_child(world)
	world.set_process(false)
	var index := 0
	for id in world.patrols:
		world.patrols[id].rng.seed = 403084 + index
		world.patrols[id].wait = world.patrols[id].rng.randf_range(0.2, 2.5)
		index += 1
	var traces := {"wolf_a": [], "wolf_b": [], "wolf_c": []}
	var valid := true
	var mixed := 0
	var moving_counts := {"wolf_a": 0, "wolf_b": 0, "wolf_c": 0}
	for tick in 1200:
		world._update_patrols(0.1)
		var moving := 0
		for id in world.patrols:
			var state: Dictionary = world.patrols[id]
			var sprite: AnimatedSprite2D = world.enemy_nodes[id]
			traces[id].append(sprite.position - world.cell_center(state.home))
			valid = valid and not world.astar.is_point_solid(state.cell) and maxi(absi(state.cell.x - state.home.x), absi(state.cell.y - state.home.y)) <= 2
			if state.next.x >= 0:
				valid = valid and not world.astar.is_point_solid(state.next) and maxi(absi(state.next.x - state.home.x), absi(state.next.y - state.home.y)) <= 2
			if sprite.animation == "walk": moving += 1; moving_counts[id] += 1
		if moving > 0 and moving < 3: mixed += 1
	check(valid, "Patrols stay on walkable cells within two cells of home")
	check(mixed > 100, "One wolf can walk while another rests")
	check(traces.wolf_a != traces.wolf_b and traces.wolf_a != traces.wolf_c and traces.wolf_b != traces.wolf_c, "Wolves no longer repeat the same relative motion")
	for id in moving_counts: check(moving_counts[id] > 100, id + " keeps patrolling")
	check(world.patrols.wolf_a.rng != world.patrols.wolf_b.rng and world.patrols.wolf_b.rng != world.patrols.wolf_c.rng, "Each monster owns a separate random stream")
	var before: Vector2 = world.enemy_nodes.wolf_a.position
	world.enabled = false
	world._update_patrols(1.0)
	check(world.enemy_nodes.wolf_a.position == before, "Paused local world keeps patrols paused")
	world.queue_free()
	await get_tree().process_frame
	Game.player = old
	print("INDEPENDENT PATROLS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
