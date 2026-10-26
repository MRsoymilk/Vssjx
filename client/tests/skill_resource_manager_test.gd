extends Node

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	await Game.when_ready()
	var browser = load("res://scenes/admin/data_browser.tscn").instantiate()
	add_child(browser)
	browser.select_category("skills")
	browser.get_node("%Search").text = "雷霆一击"
	browser._fill_list()
	check(browser.visible_entries.size() == 4, "Skill search includes base and three stages")
	var stages: Array = browser.visible_entries.filter(func(entry: Dictionary) -> bool: return entry.data["阶段"] == 3)
	check(stages.size() == 1, "Final stage is unique")
	if not stages.is_empty():
		for row in browser.get_node("%Records").get_root().get_children():
			if row.get_metadata(0).id == stages[0].id:
				row.select(0)
				browser._record_selected()
		var preview = browser.get_node("%Preview")
		check(is_instance_valid(preview.sprite) and preview.record.preview.art == "effect/t174", "Final stage loads its native animation")
		check(browser.current.data["阶段起始技能等级"] == 15, "Final stage displays level 15")
	for frame in 4: await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png("res://../work/skill-resource-manager.png") == OK, "Resource manager screenshot")
	browser.select_category("effects")
	browser.get_node("%Search").text = "万剑归宗"
	browser._fill_list()
	check(not browser.visible_entries.is_empty(), "Effect search resolves current skill usage")
	browser.select_category("skills")
	browser.get_node("%Search").text = "清风荣新"
	browser._fill_list()
	check(browser.visible_entries.size() == 4, "New skill exposes base and three stages")
	print("SKILL RESOURCE MANAGER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
