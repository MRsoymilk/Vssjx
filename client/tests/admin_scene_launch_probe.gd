extends Node
## A separate-process standalone desktop tool launch.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var editor_host := arguments.has("--expect-editor-host")
	var host := get_tree().root
	var host_size := host.size
	var path := arguments[arguments.find("--admin-scene") + 1]
	var scene = load(path).instantiate()
	host.add_child(scene)
	get_tree().current_scene = scene
	for frame in 8: await get_tree().process_frame
	assert(scene is Control and scene.is_inside_tree())
	var window: Window = scene.get_window()
	if editor_host and (window == host or window.is_embedded()):
		push_error("ADMIN F6: tool must leave the portrait Game host and use a native desktop window")
		get_tree().quit(1)
		return
	if editor_host:
		assert(host_size == Vector2i(640, 960) and host.size == host_size, "Editor keeps its portrait host; admin must not fight it")
		assert(get_tree().current_scene == window, "Desktop wrapper remains owned by the same scene/debug process")
	var viewport := window.get_visible_rect()
	var expected_size := Vector2i(960, 640) if path.ends_with("data_browser.tscn") else Vector2i(960, 540)
	assert(window.size == expected_size, "Admin defaults to its desktop window size")
	assert(viewport.size.is_equal_approx(Vector2(expected_size)), "Admin uses a desktop canvas, not the mobile viewport")
	assert(viewport.encloses(scene.get_global_rect()))
	if path.ends_with("data_browser.tscn"):
		assert(scene.visible_entries.size() == 59)
		assert(viewport.encloses(scene.get_node("%Copy").get_global_rect()))
		assert(viewport.encloses(scene.get_node("%Inspector").get_global_rect()))
	else:
		assert(scene.get_node("%WorldPreview").record.preview.world.nodes.size() == 79)
		assert(viewport.encloses(scene.get_node("%Scope").get_global_rect()))
	assert(window.title.contains("数据管理") or window.title.contains("世界总图"))
	if DisplayServer.get_name() != "headless":
		assert(not window.gui_embed_subwindows)
	var output := OS.get_environment("SSJX_ADMIN_LAYOUT_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		assert(window.get_texture().get_image().save_png(output) == OK)
	print("ADMIN SCENE LAUNCH: PASS ", path, " window=", window.size, " canvas=", viewport.size, " editor_host=", host.size, " detached=", window != host)
	scene.queue_free()
	await get_tree().process_frame
	if editor_host: window.close_requested.emit()
	else: get_tree().quit()
