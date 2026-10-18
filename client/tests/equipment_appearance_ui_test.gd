extends Node
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func settle() -> void:
	for frame in 4: await get_tree().process_frame
func rendered_pixels(screen: Image, control: Control) -> int:
	var rect := Rect2i(control.get_global_rect()).grow(-1)
	var backgrounds := [screen.get_pixelv(rect.position), screen.get_pixelv(rect.position + Vector2i(20,0))]
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if screen.get_pixel(x,y) not in backgrounds: count += 1
	return count
func _ready() -> void:
	var player := Game.player.duplicate(true)
	var path := Game.save_path
	var save_hash := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var browser = load("res://scenes/admin/data_browser.tscn").instantiate()
	add_child(browser)
	await settle()
	browser.select_category("appearance")
	check(browser.visible_entries.size() == 142, "All 142 equipment mappings appear in their own category")
	check(browser.catalog.find("appearance", "eck1").any(func(row: Dictionary) -> bool: return row.id == "original/iw28"), "Mappings can be searched by original part number")
	var panel = browser.get_node("%AppearanceComparison")
	for id in ["original/iw28", "original/if11", "original/if1", "original/if3", "weapon_2", "armor_2"]:
		browser.get_node("%Search").text = id
		browser._fill_list(id)
		var row: TreeItem = browser.get_node("%Records").get_root().get_first_child()
		while row.get_metadata(0).id != id: row = row.get_next()
		row.select(0)
		await settle()
		check(panel.visible and not browser.get_node("%Preview").visible, "Shows authored comparison instead of duplicate icon: "+id)
		check(is_instance_valid(panel.before_preview.sprite) and is_instance_valid(panel.after_preview.sprite), "Both states use real AnimatedSprite2D: "+id)
		var item := ShopRules.item(id)
		for job in 3: check(panel.get_node("%Job").is_item_disabled(job) == (int(item.job)>=0 and int(item.job)!=job), "Enforces actual job restriction")
		panel.get_node("%Gender").select(1)
		panel.get_node("%Gender").item_selected.emit(1)
		panel.get_node("%Action").select(1)
		panel.get_node("%Action").item_selected.emit(1)
		await settle()
		check(panel.before_preview.sprite.animation == "walk" and panel.after_preview.sprite.animation == "walk", "Both previews play the selected walking animation")
		check(str(panel.after_preview.sprite.get_meta("art_key")).begins_with("hero/w"), "Gender switch renders the matching female actor")
		for control in [panel, panel.before_preview, panel.after_preview, browser.get_node("%Copy"), browser.get_node("%Footer")]:
			check(control.get_viewport().get_visible_rect().grow(1).encloses(control.get_global_rect()), "Comparison and details fit the desktop")
		if id == "original/if3": check(panel.before_preview.sprite.get_meta("art_key") == panel.after_preview.sprite.get_meta("art_key") and panel.get_node("%Mapping").text.contains("只影响属性"), "Stat-only slot honestly keeps the same appearance")
		var capture := OS.get_environment("SSJX_EQUIPMENT_APPEARANCE_CAPTURE")
		if id == "original/if11" and not capture.is_empty() and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			var screen := get_viewport().get_texture().get_image()
			check(screen.save_png(capture) == OK, "Rendered equipment mapping comparison")
			check(rendered_pixels(screen, panel.before_preview) > 50, "Baked actor paints visible pixels inside the before pane")
			check(rendered_pixels(screen, panel.after_preview) > 50, "Trimmed dynamic atlas paints visible pixels inside the after pane")
	browser.select_category("weapons")
	check(browser.current.data.has("外观对应"), "Weapon records also expose mapping details")
	browser.select_category("maps")
	check(not panel.visible and browser.get_node("%Preview").visible and not is_instance_valid(panel.after_preview.sprite), "Leaving equipment restores normal preview and releases comparison")
	check(Game.player == player and Game.save_path == path and (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "") == save_hash, "Inspection never changes player or save bytes")
	browser.queue_free()
	await settle()
	print("EQUIPMENT APPEARANCE UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
