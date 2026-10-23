extends Node
var checks := 0
var failures := 0
var sample_seconds := 0.0
var output := ""

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + message)

func test_schedule() -> void:
	for pair in [[0.0,0.0], [3539.0,0.0], [3540.0,0.0], [3570.0,0.5], [3600.0,1.0], [7139.0,1.0], [7140.0,1.0], [7170.0,0.5], [7200.0,0.0]]:
		check(is_equal_approx(WorldDayNight.night_weight(pair[0]), pair[1]), "Exact hourly phase and one-minute transition boundary: %s" % pair[0])
	for seconds in range(0, 7200, 15):
		var weight := WorldDayNight.night_weight(float(seconds))
		check(weight >= 0.0 and weight <= 1.0, "Transition stays inside visible daylight/night bounds")
		check(is_equal_approx(weight, WorldDayNight.night_weight(float(seconds + 7200 * 10000))), "Absolute world phase repeats every two hours, not since login")
	for seconds in range(3541, 3601):
		check(WorldDayNight.night_weight(seconds) >= WorldDayNight.night_weight(seconds - 1), "Dusk never brightens mid-fade")
	for seconds in range(7141, 7201):
		check(WorldDayNight.night_weight(seconds) <= WorldDayNight.night_weight(seconds - 1), "Dawn never darkens mid-fade")
	check(absf(WorldDayNight.night_weight(3599.999) - WorldDayNight.night_weight(3600.0)) < 0.00001, "Day/night boundary is continuous")
	check(absf(WorldDayNight.night_weight(7199.999) - WorldDayNight.night_weight(7200.0)) < 0.00001, "Cycle boundary is continuous")
	for seconds in [-1.0, INF, NAN]:
		check(WorldDayNight.tint_at(seconds) == Color.WHITE, "Unknown or invalid source remains readable")
	check(WorldDayNight.tint_at(0.0) == Color.WHITE and WorldDayNight.tint_at(3600.0) == WorldDayNight.NIGHT, "Day preserves original art and night uses the bounded cool tint")
	for id in ["qingyun_trail", "ancient_ruins", "ai_001"]:
		check(WorldDayNight.uses_cycle(SharedWorldMap.load_data(id)), "Outdoor map follows the cycle: " + id)
	for id in ["ai_053", "ai_047", "ai_087", "ai_101", "ai_109"]:
		check(not WorldDayNight.uses_cycle(SharedWorldMap.load_data(id)), "Cave/underground map keeps fixed lighting: " + id)
	check(not WorldDayNight.uses_cycle({"day_night_enabled":false}), "An authored indoor map can explicitly opt out")
	check(WorldDayNight.uses_cycle({"biome":"cave", "day_night_enabled":true}), "Explicit map lighting override takes precedence")

func settle() -> void:
	for frame in 3: await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func save_frame(name_value: String) -> Image:
	await settle()
	var image := get_viewport().get_texture().get_image()
	if not output.is_empty(): check(image.save_png(output.path_join(name_value + ".png")) == OK, "Save actual rendered screenshot: " + name_value)
	return image

func brightness(image: Image) -> float:
	var total := 0.0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x,y)
			total += (pixel.r + pixel.g + pixel.b) / 3.0
	return total / float(ceili(image.get_width() / 4.0) * ceili(image.get_height() / 4.0))

func _run() -> void:
	await Game.when_ready()
	test_schedule()
	output = OS.get_environment("SSJX_DAY_NIGHT_CAPTURE_PATH")
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://day_night_%d.json" % OS.get_process_id()
	Game.new_player("昼夜验证", 0, 3)
	var before := Game.player.duplicate(true)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	await settle()
	app._enter_world()
	app.set_process(false)
	app.world.enabled = false
	app.world.hero.pause()
	var light: WorldDayNight = app.world.day_night
	light.time_source = func() -> float: return sample_seconds
	sample_seconds = 0.0; light.refresh()
	check(light.get_viewport() == app.viewport and light.get_viewport() != app.ui.get_viewport(), "Local light is confined to the world viewport, outside HUD/chat/bag")
	check(light.color == Color.WHITE, "Local daytime immediately preserves original colors")
	if DisplayServer.get_name() != "headless":
		var day := await save_frame("local-day")
		var day_world: Image = app.viewport.get_texture().get_image()
		sample_seconds = 3570.0; light.refresh()
		await save_frame("local-dusk")
		sample_seconds = 3600.0; light.refresh()
		var night := await save_frame("local-night")
		var night_world: Image = app.viewport.get_texture().get_image()
		check(brightness(night_world) < brightness(day_world) * 0.85, "Actual map pixels visibly darken at night")
		check(brightness(night_world) > brightness(day_world) * 0.5, "Night retains enough map brightness to navigate")
		var scale_factor := Vector2(day.get_size()) / Vector2(320,480)
		var header := Rect2i(Vector2i.ZERO, Vector2i(Vector2(320,28) * scale_factor))
		var footer := Rect2i(Vector2i(Vector2(0,403) * scale_factor), Vector2i(Vector2(320,77) * scale_factor))
		check(day.get_region(header).get_data() == night.get_region(header).get_data(), "Actual HUD header pixels do not darken")
		check(day.get_region(footer).get_data() == night.get_region(footer).get_data(), "Actual chat/toolbar pixels do not darken")
		sample_seconds = 7170.0; light.refresh()
		await save_frame("local-dawn")
	sample_seconds = 3600.0; light.refresh()
	check(light.color == WorldDayNight.NIGHT, "Local night source drives the production effect")
	light._process(0.0)
	sample_seconds = 7200.0; light._process(0.0)
	check(light.color == Color.WHITE, "Resume samples current absolute time, without accumulating paused delta")
	check(Game.player == before, "Day/night changes no local character, stat, loot or progress data")
	app.queue_free()
	await get_tree().process_frame

	var online: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	add_child(online)
	online.set_process(false); online.network.set_process(false)
	light = online.day_night
	check(light.get_viewport() == online.viewport and light.get_viewport() != online.screen.get_viewport(), "Online light is confined to the shared-map viewport")
	check(light.color == Color.WHITE, "No authenticated clock means no device-derived online night")
	online.network._sync_world_clock({"server_time_ms":3600000})
	light.refresh()
	check(light.color == WorldDayNight.NIGHT, "Production online effect uses the server clock, not the device clock")
	if DisplayServer.get_name() != "headless":
		await save_frame("online-night")
	var identity := light.get_instance_id()
	online._map_changed("ai_053")
	check(online.day_night.get_instance_id() == identity and light.color == Color.WHITE and not light.cycle_enabled, "Entering a cave disables the existing effect without stacking lights")
	if DisplayServer.get_name() != "headless": await save_frame("online-cave")
	online._map_changed("qingyun_trail")
	check(online.day_night.get_instance_id() == identity and light.color == WorldDayNight.NIGHT, "Returning outdoors restores the same world phase, not a fresh day")
	check(online.scene.find_children("DayNight", "CanvasModulate", false, false).size() == 1, "Repeated map builds keep exactly one canvas light")
	online.network._failed("TEST_RECONNECT"); light.refresh()
	check(light.color == WorldDayNight.NIGHT, "Reconnection continues the synchronized night")
	online.network.stream = "10000000-0000-4000-8000-000000000001"
	online.network._receive({"type":"pong", "server_time_ms":7200000}, PackedByteArray())
	light.refresh()
	check(light.color.is_equal_approx(Color.WHITE), "New clock sample advances to the next daytime")
	check(Game.player == before, "Online lighting/map presentation never installs or modifies the local player")
	online.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Game.player = old_player; Game.save_path = old_path
	print("DAY NIGHT: %d checks, %d failures (%s)" % [checks, failures, DisplayServer.get_name()])
	get_tree().quit(1 if failures else 0)
