extends SceneTree
## Run this filesystem script against the actual exported PCK, not source res://.

var checks := 0

func _initialize() -> void:
	_verify.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		push_error("EXPORT FAIL: " + description)
		quit(1)
		assert(false, description)

func _verify() -> void:
	check(FileAccess.file_exists("res://project.binary"), "Running from packed project settings")
	for path in ["res://scenes/admin/data_browser.tscn", "res://scenes/admin/world_overview.tscn", "res://scenes/admin/world_overview_popup.tscn", "res://scripts/admin/data_browser.gd", "res://scripts/admin/admin_window_layout.gd", "res://tests/data_browser_test.tscn"]:
		check(not ResourceLoader.exists(path), "Developer resource is absent: " + path)
	for path in ["res://scenes/admin", "res://scripts/admin", "res://tests"]:
		check(not DirAccess.dir_exists_absolute(path), "Developer directory is absent: " + path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/actors.json"))
	check(manifest.get("actors", {}).size() == 33, "Actor index is included")
	for path in manifest.actors.values():
		check(FileAccess.file_exists(path), "Dynamically loaded actor JSON is included: " + path)
	check(FileAccess.file_exists("res://assets/data/original_world.json"), "Shared game world data is still included")
	check(ResourceLoader.exists("res://scenes/main.tscn"), "Game main scene is included")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for frame in 5: await process_frame
	check(scene.mode == "home" and is_instance_valid(scene.original_cover), "The exported game reaches its normal home screen")
	check(root.content_scale_size == Vector2i(320, 480), "Game export keeps its portrait viewport")
	scene.queue_free()
	await process_frame
	print("GAME EXPORT: %d checks, 0 failures" % checks)
	quit()
