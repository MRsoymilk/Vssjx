extends "res://tests/shared_interface_test.gd"
var entries: Array = []

func _run() -> void:
	var old := Game.player.duplicate(true)
	var page: OriginalCharacterSelection = load("res://scenes/ui/character_selection.tscn").instantiate()
	add_child(page)
	page.enter_requested.connect(func(id: String) -> void: entries.append(id))
	check(page.enter_button.disabled and not page.previews[1].visible, "Empty selection cannot enter game")
	var records := [{"id":SELF,"display_name":"青云剑客","level":7,"job":1,"gender":0,"school":2,"map_id":"qingyun_trail"},{"id":PEER,"display_name":"花间修士","level":12,"job":2,"gender":1,"school":1,"map_id":"qingyun_trail"},{"id":EPOCH,"display_name":"峨眉力士","level":5,"job":0,"gender":0,"school":0,"zone":1}]
	page.display_characters(records)
	page.set_controls(false,false)
	check(page.get_node("Details/Name").text == "青云剑客" and page.get_node("Details/Level").text == "7" and page.get_node("Details/School").text == "昆仑派", "Details display selected character's actual values")
	var expected_look := ShopRules.appearance(ShopRules.local_state(records[0]))
	check(page.previews[1].sprite_frames == OriginalArt.cached[ShopRules.actor_key(1,0,expected_look)] and page.previews[1].is_playing(), "Authored AnimatedSprite2D plays actual avatar with current equipment appearance")
	check(page.previews[1] is NativeActorSprite and page.previews[1].scene_file_path==OriginalArt.scene_path(ShopRules.actor_key(1,0,expected_look)),"Character selection instances the corresponding native actor scene, not an empty sprite with copied frames")
	page.step(1)
	check(page.get_node("Details/Name").text == "花间修士" and page.get_node("Details/Gender").text == "女" and page.get_node("Details/Job").text == "隐者", "Paging changes selected data and gender")
	check(page.previews[0].visible and page.previews[1].visible and page.previews[2].visible, "Three real neighbors populate reference carousel")
	page.set_controls(true,false)
	page.step(1); page._enter()
	check(page.selected_index == 1 and entries.is_empty(), "Loading or expired session blocks changing or entering role")
	page.set_controls(false,false)
	output = OS.get_environment("SSJX_SELECTION_CAPTURE_PATH") if DisplayServer.get_name() != "headless" else ""
	await capture("character_selection_carousel")
	page.enter_button.pressed.emit(); page.enter_button.pressed.emit()
	check(entries == [PEER] and page.enter_button.disabled, "Only explicit Enter emits selected ID once")
	page.display_characters([records[1]])
	page.set_controls(false,false)
	check(not page.previews[0].visible and page.previews[1].visible and not page.previews[2].visible and page.get_node("Previous").disabled, "One-character account does not fabricate side characters")
	await capture("character_selection_single")
	var unjoined:Dictionary=records[1].duplicate(true);unjoined.school=SchoolRules.UNJOINED
	page.display_characters([unjoined])
	check(page.get_node("Details/School").text=="闲云野鹤","Unjoined identity is not clamped into an existing school")
	page.display_characters([])
	page.set_controls(false,true)
	check(page.enter_button.disabled and not page.get_node("Options/Create").disabled and page.get_node("Details/Name").text == "—", "Empty account offers creation and clears prior identity")
	check(Game.player == old, "Selection UI never installs online records into offline state")
	page.queue_free()
	await get_tree().process_frame
	print("CHARACTER SELECTION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
