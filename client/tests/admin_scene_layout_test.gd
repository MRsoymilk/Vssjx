extends Node

var checks := 0
var failures := 0
var output := OS.get_environment("SSJX_ADMIN_LAYOUT_CAPTURE")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func settle() -> void:
	for frame in 5: await get_tree().process_frame

func capture(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Rendered " + name)

func fits(control: Control, description: String) -> void:
	var visible := control.get_viewport().get_visible_rect().grow(1.0)
	check(visible.encloses(control.get_global_rect()), description)

func _ready() -> void:
	var player := Game.player.duplicate(true)
	var save_path: String = Game.save_path
	var save_hash := FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else ""
	var original_settings := {
		"width": ProjectSettings.get_setting("display/window/size/viewport_width"),
		"height": ProjectSettings.get_setting("display/window/size/viewport_height"),
		"stretch": ProjectSettings.get_setting("display/window/stretch/mode")
	}
	var browser = load("res://scenes/admin/data_browser.tscn").instantiate()
	add_child(browser)
	await settle()
	check(get_window().size == Vector2i(960, 640) and get_viewport().get_visible_rect().size.is_equal_approx(Vector2(960, 640)), "Browser starts with a real 960x640 desktop viewport")
	for dimensions in [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1360, 900), Vector2i(640, 480)]:
		get_window().min_size = Vector2i.ZERO
		get_window().size = dimensions
		await settle()
		check(get_viewport().get_visible_rect().size.x >= 959, "Browser keeps a complete virtual desktop at " + str(dimensions))
		check(get_viewport().get_visible_rect().size.y >= 639, "Browser keeps its 640px canvas height at " + str(dimensions))
		fits(browser.get_node("%Inspector"), "Inspector fits at " + str(dimensions))
		fits(browser.get_node("%Copy"), "Copy action fits at " + str(dimensions))
		fits(browser.get_node("%Footer"), "Footer fits at " + str(dimensions))
		if dimensions == Vector2i(640, 480): await capture("browser-small-window")
		if dimensions == Vector2i(960, 640): await capture("browser-desktop")
	get_window().size = Vector2i(960, 640)
	await settle()
	for category in ["weapons", "equipment", "items", "characters", "quests", "maps", "enemies", "art"]:
		browser.select_category(category)
		await settle()
		fits(browser.get_node("%Inspector"), "Desktop inspector fits category " + category)
		fits(browser.get_node("%Copy"), "Desktop actions fit category " + category)
		fits(browser.get_node("%Footer"), "Desktop footer fits category " + category)
		if category == "characters": await capture("browser-characters-desktop")
		if category == "enemies":
			browser.get_node("%StatusFilter").select(4)
			browser._fill_list()
			browser.get_node("%Search").text = "zbjl2"
			browser._fill_list()
			await settle()
			fits(browser.get_node("%Copy"), "Original monster animation actions fit 960x640")
			check(browser.visible_entries.size() == 1 and browser.current.id == "original/monster/zbjl2", "Desktop can preview a previously missing monster")
			await capture("browser-original-monsters-desktop")
	browser.select_category("maps")
	browser.get_node("%StatusFilter").select(5)
	browser._fill_list()
	await settle()
	fits(browser.get_node("%Copy"), "Original-map details fit the 960x640 desktop")
	await capture("browser-original-maps-desktop")
	var popup: Window = browser.open_world_overview()
	await settle()
	check(popup != null, "Browser can still open the overview popup")
	if popup != null:
		var previews := popup.find_children("WorldPreview", "Control", true, false)
		check(previews.size() == 1 and previews[0].record.get("preview", {}).get("world", {}).get("nodes", []).size() == 79, "Popup receives the selected real overview data")
		if DisplayServer.get_name() != "headless":
			check(not popup.is_embedded(), "Overview popup is a separate desktop window, not an embedded page")
		check(popup.size == Vector2i(960, 540), "Overview popup also uses the desktop resolution")
		fits(popup.get_node("Overview").get_node("%Scope"), "Popup scope/footer also fits inside its own scaled canvas")
		if not output.is_empty() and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			check(popup.get_texture().get_image().save_png(output.path_join("overview-popup.png")) == OK, "Rendered overview popup")
		popup.queue_free()
	browser.queue_free()
	await settle()
	var overview = load("res://scenes/admin/world_overview.tscn").instantiate()
	check(overview is Control, "Standalone overview has its own runnable desktop content")
	if not overview is Control:
		overview.free()
		print("ADMIN SCENE LAYOUT: %d checks, %d failures" % [checks, failures])
		get_tree().quit(1)
		return
	add_child(overview)
	await settle()
	check(get_window().size == Vector2i(960, 540) and get_viewport().get_visible_rect().size.is_equal_approx(Vector2(960, 540)), "Overview starts with a real 960x540 desktop viewport")
	var preview: Control = overview.get_node("%WorldPreview")
	check(preview.record.get("preview", {}).get("world", {}).get("nodes", []).size() == 79, "Standalone overview initializes all 79 original locations")
	check(preview.record.get("preview", {}).get("world", {}).get("routes", []).size() == 78, "Standalone overview initializes all 78 original routes")
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(640, 480)]:
		get_window().min_size = Vector2i.ZERO
		get_window().size = dimensions
		await settle()
		fits(overview.get_node("%Title"), "Overview title fits at " + str(dimensions))
		fits(preview, "Entire overview preview fits at " + str(dimensions))
		fits(overview.get_node("%Scope"), "Overview scope footer fits at " + str(dimensions))
		for point in preview.record.get("preview", {}).get("world", {}).get("nodes", []):
			var at: Vector2 = preview.overview_transform() * Vector2(point.world_position[0], point.world_position[1])
			check(Rect2(Vector2.ZERO, preview.size).has_point(at), "Original location is within overview bounds")
		if dimensions == Vector2i(960, 540): await capture("overview-desktop")
		if dimensions == Vector2i(640, 480): await capture("overview-small-window")
	check(Game.player == player and Game.save_path == save_path, "Admin scenes leave offline state untouched")
	check((FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else "") == save_hash, "Admin scenes never rewrite the save")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == original_settings.width and ProjectSettings.get_setting("display/window/size/viewport_height") == original_settings.height and ProjectSettings.get_setting("display/window/stretch/mode") == original_settings.stretch, "Game's 320x480 project settings are unchanged")
	overview.queue_free()
	await settle()
	print("ADMIN SCENE LAYOUT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
