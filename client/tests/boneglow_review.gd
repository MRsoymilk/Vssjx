extends MarginContainer
const MAPPING := preload("res://scripts/admin/equipment_appearance.gd")
@export var family := "boneglow"
var capture_path := ""

func _ready() -> void:
	var config: Dictionary = GeneratedEquipment.FAMILIES.filter(func(value: Dictionary)->bool:return value.id==family)[0]
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.path))
	preload("res://scripts/admin/admin_window_layout.gd").configure_scene(self,config.name+" · 游戏内动画核对",Vector2i(1100,760))
	$Layout/Title.text = config.name+" · 原生分层动画"
	$Layout/Hint.text = "原生 ANI 动作 · 头部 / 衣服 / 武器独立换装 · 商城分类："+config.name+" · 本角色"
	var design := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","sans-serif"])
	design.default_font = font
	theme = design
	for index in definitions.sets.size():
		var definition: Dictionary = definitions.sets[index]
		var card := %Grid.get_child(index)
		card.get_node("Title").text = definition.name+" · "+["力士","侠客","隐者"][int(definition.job)]+("男" if int(definition.gender)==0 else "女")
		var mapping := MAPPING.variant(ShopRules.item("ai/"+definition.id+"/armor"),int(definition.job),int(definition.gender),true)
		card.get_node("Compare/Before").display({"preview":{"kind":"actor","art":mapping["装备前动画"]}})
		card.get_node("Compare/After").display({"preview":{"kind":"actor","art":mapping["装备后动画"]}})
	%Action.item_selected.connect(_action)
	capture_path = OS.get_environment("SSJX_EQUIPMENT_REVIEW_CAPTURE")
	if capture_path.is_empty(): capture_path = OS.get_environment("SSJX_BONEGLOW_REVIEW_CAPTURE")
	if not capture_path.is_empty(): _capture.call_deferred()

func _action(index: int) -> void:
	for card in %Grid.get_children():
		for side in ["Before","After"]: card.get_node("Compare/"+side).play_animation(["idle","walk","attack","cast","hurt"][index])

func _capture() -> void:
	var action := OS.get_environment("SSJX_EQUIPMENT_REVIEW_ACTION")
	var index := ["idle","walk","attack","cast","hurt"].find(action)
	if index >= 0:
		%Action.select(index)
		_action(index)
	for frame in 5: await get_tree().process_frame
	var requested_frame := OS.get_environment("SSJX_EQUIPMENT_REVIEW_FRAME")
	if not requested_frame.is_empty():
		for card in %Grid.get_children():
			for side in ["Before","After"]:
				var sprite: AnimatedSprite2D = card.get_node("Compare/"+side).sprite
				sprite.set_frame_and_progress(mini(int(requested_frame),sprite.sprite_frames.get_frame_count(sprite.animation)-1),0)
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(capture_path)
	get_tree().quit()
