extends MarginContainer
const MAPPING := preload("res://scripts/admin/equipment_appearance.gd")

func _ready() -> void:
	preload("res://scripts/admin/admin_window_layout.gd").configure_scene(self,"骨甲幽光 · 游戏内动画核对",Vector2i(1100,760))
	var design := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","sans-serif"])
	design.default_font = font
	theme = design
	for index in BoneglowEquipment.manifest().sets.size():
		var definition: Dictionary = BoneglowEquipment.manifest().sets[index]
		var card := %Grid.get_child(index)
		card.get_node("Title").text = definition.name+" · "+["力士","侠客","隐者"][int(definition.job)]+("男" if int(definition.gender)==0 else "女")
		var mapping := MAPPING.variant(ShopRules.item("ai/"+definition.id+"/armor"),int(definition.job),int(definition.gender),true)
		card.get_node("Compare/Before").display({"preview":{"kind":"actor","art":mapping["装备前动画"]}})
		card.get_node("Compare/After").display({"preview":{"kind":"actor","art":mapping["装备后动画"]}})
	%Action.item_selected.connect(_action)
	if not OS.get_environment("SSJX_BONEGLOW_REVIEW_CAPTURE").is_empty(): _capture.call_deferred()

func _action(index: int) -> void:
	for card in %Grid.get_children():
		for side in ["Before","After"]: card.get_node("Compare/"+side).play_animation(["idle","walk","attack","cast","hurt"][index])

func _capture() -> void:
	for frame in 5: await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SSJX_BONEGLOW_REVIEW_CAPTURE"))
	get_tree().quit()
