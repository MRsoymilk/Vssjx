extends Node

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in 4: await get_tree().process_frame

func choose(control: OptionButton, index: int) -> void:
	control.select(index)
	control.item_selected.emit(index)

func _ready() -> void:
	var player := Game.player.duplicate(true)
	var save_path := Game.save_path
	var save_hash := FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else ""
	var browser = load("res://scenes/admin/data_browser.tscn").instantiate()
	add_child(browser)
	await settle()
	var slots: OptionButton = browser.get_node("%EquipmentSlotFilter")
	var status: OptionButton = browser.get_node("%StatusFilter")
	var search: LineEdit = browser.get_node("%Search")
	browser.select_category("equipment")
	var total: int = browser.visible_entries.size()
	check(slots.visible and slots.item_count == 11, "Equipment has all ten slot choices and an all-slots reset")
	for index in ShopRules.SLOTS.size():
		choose(slots, index + 1)
		var slot: String = ShopRules.SLOTS[index]
		check(not browser.visible_entries.is_empty(), "Slot contains records: " + slot)
		for entry in browser.visible_entries:
			if entry.data.has("槽位序号"):
				check(ShopRules.SLOTS[int(entry.data["槽位序号"])] == slot, "Slot header belongs to selected slot")
			else:
				var id: String = String(entry.id).trim_prefix("shop/")
				check(ShopRules.item(id).get("slot") == slot, "Every result agrees with game equipment rules: " + id)
	for index in [6, 7]:
		choose(slots, index)
		check(browser.visible_entries.size() == 31, "Pants and boots include nine originals, nine shop rules, twelve AI items and one slot")
		choose(status, 4)
		check(browser.visible_entries.size() == 9, "Original-resource status combines with slot")
		var selected_id: String = browser.visible_entries.back().id
		search.text = selected_id
		browser._fill_list()
		check(browser.visible_entries.size() == 1 and browser.current.id == selected_id, "Search, status and slot all apply together")
		browser.reload_data()
		check(slots.selected == index and status.selected == 4 and browser.visible_entries.size() == 1, "Refresh preserves all filter choices")
		search.text = "no-such-equipment"
		browser._fill_list()
		check(browser.current.is_empty() and browser.get_node("%Copy").disabled and browser.get_node("%Empty").visible, "No match clears stale details and copy action")
		check(not browser.get_node("%AppearanceComparison").visible, "No match clears the appearance preview")
		search.text = ""
		choose(status, 0)
	choose(slots, 0)
	check(browser.visible_entries.size() == total, "All slots restores the entire equipment list")
	for category in ["appearance", "items"]:
		browser.select_category(category)
		choose(slots, 6)
		check(browser.visible_entries.size() == (21 if category == "appearance" else 30), "Slot filtering includes AI items in " + category)
	browser.select_category("maps")
	check(not slots.visible and slots.selected == 0 and not browser.visible_entries.is_empty(), "Switching category clears and hides irrelevant slot filter")
	browser.select_category("equipment")
	choose(slots, 6)
	await settle()
	for control in [search, slots, status, browser.get_node("%Inspector"), browser.get_node("%Copy"), browser.get_node("%Footer")]:
		check(get_viewport().get_visible_rect().grow(1).encloses(control.get_global_rect()), "Filter and details fit the desktop: " + control.name)
	check(not slots.get_global_rect().intersects(status.get_global_rect()), "Dropdowns never overlap")
	check(search.size.x >= 240, "Search remains usable on the 960px desktop")
	var capture := OS.get_environment("SSJX_SLOT_FILTER_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(capture) == OK, "Saved rendered filter preview")
	check(Game.player == player and Game.save_path == save_path and (FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else "") == save_hash, "Filtering never changes player state or saves")
	browser.queue_free()
	await settle()
	print("EQUIPMENT SLOT FILTER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
