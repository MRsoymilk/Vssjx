extends Node
## Fixed page layouts must exist before _ready(), so the editor can inspect them.
var checks := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var scenes := {
		"original_cover": ["Original320x480Artwork", "Rows0", "Confirm"],
		"server_login": ["ServerAddress", "Username", "Password", "Discovery"],
		"online_characters": ["OnlineNickname", "Job", "Gender", "School"],
		"character_creation": ["Nickname", "Slots0/PortraitButtons0", "Create"],
		"character_attributes": ["Pages", "Signature", "Back"],
		"attributes_regular": ["NameValue", "BarsHp", "NumbersLevel"],
		"attributes_extended": ["StatValue5", "StatValue11"],
		"attributes_skills": ["SkillName", "Description"],
		"attributes_inner": ["Label0"],
		"inventory": ["Grid", "Scrollbar", "Equipment0", "Tooltip/TooltipLabel"],
		"inventory_cell": ["Panel/Icon", "Panel/Count", "Button"],
		"scene_chrome": ["HpBar", "MessagePanel/LogLabel", "Toolbar/Bag"],
		"battle_chrome": ["HpBar", "RoundLabel", "MessagePanel/LogLabel"],
		"world_hud": ["Minimap", "MapName"],
		"battle_hud": ["BattleHeroHp", "ActionMenu/BattleButtons0", "HeroHit"],
		"battle_move_callout": ["Caption"],
		"battle_encounter_transition": ["Warning", "Caption", "Detail"],
		"online_world_view": ["Viewport/Scene/Camera", "ChatPanel/ChatInput", "Network"],
		"modal_overlay": ["Shade"],
		"dialog_frame": ["Title"],
		"battle_inspect": ["NameValue", "Hp", "Secondary", "Tertiary"]
	}
	for scene_name in scenes:
		var packed: PackedScene = load("res://scenes/ui/%s.tscn" % scene_name)
		check(packed != null and packed.can_instantiate(), "Page can be instantiated: " + scene_name)
		var page := packed.instantiate()
		for path in scenes[scene_name]:
			check(page.has_node(path), "Layout exists before ready: %s/%s" % [scene_name, path])
		if scene_name == "inventory":
			check(page.get_node("EquipmentLevel").value == "1" and page.get_node("EquipmentLevel").color_set == "green", "Bitmap number settings survive scene serialization")
		if scene_name == "battle_chrome": check(page.in_battle, "Battle chrome mode is saved in the scene")
		if scene_name == "online_characters":
			check(page.get_node("Job").item_count == 3 and page.get_node("Gender").item_count == 2 and page.get_node("School").item_count == 3, "Lobby choices are available without runtime construction")
		page.free()
	var actor_scene: PackedScene = load("res://scenes/actors/original_actor.tscn")
	var actor := actor_scene.instantiate()
	check(actor is AnimatedSprite2D and not actor.centered and actor.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Actor template uses Godot AnimatedSprite2D with the original pixel alignment")
	actor.free()
	print("UI SCENES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
