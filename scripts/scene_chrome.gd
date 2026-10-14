class_name OriginalSceneChrome
extends Control
## Common blue HUD and message area measured from the supplied in-game views.

signal action_requested(action: String)
var in_battle := false
var log_label: Label
var round_label: Label
var clock_label: Label
var identity: Label
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var hint: Label
var toolbar: Control
var message_panel: Panel
var clock_hour: OriginalNumber
var clock_minute: OriginalNumber
var palette: Dictionary
var xp_bar: ProgressBar

func _ready() -> void:
	size = Vector2(320, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimHei", "Microsoft YaHei", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var skin := Theme.new()
	skin.default_font = font
	skin.default_font_size = 11
	theme = skin
	palette = OriginalUITheme.palette("scene")
	panel(self, Rect2(0, 0, 320, 28), palette.main, palette.edge)
	panel(self, Rect2(1, 1, 32, 26), palette.deep, palette.edge)
	identity = label(self, "LV.%d" % int(Game.player.level), Rect2(3, 2, 30, 12), 9, Color("fff7c8"))
	var properties := button(self, "+", Rect2(17, 13, 13, 12), 10)
	properties.add_theme_color_override("font_color", Color("48f993"))
	properties.pressed.connect(func() -> void: action_requested.emit("properties"))
	hp_bar = progress(self, Rect2(36, 3, 75, 7), Color("caef16"))
	mp_bar = progress(self, Rect2(36, 12, 75, 7), Color("40dfea"))
	xp_bar = progress(self, Rect2(36, 21, 75, 5), Color("d5d3a0"))
	clock_label = label(self, "", Rect2(133, 5, 62, 19), 14, Color("fffde0"))
	clock_label.add_theme_constant_override("outline_size", 2)
	clock_label.add_theme_color_override("font_outline_color", Color("26353b"))
	clock_label.hide()
	clock_hour = OriginalNumber.new()
	clock_hour.position = Vector2(134, 7)
	clock_hour.size = Vector2(23, 14)
	add_child(clock_hour)
	clock_minute = OriginalNumber.new()
	clock_minute.position = Vector2(168, 7)
	clock_minute.size = Vector2(23, 14)
	add_child(clock_minute)
	var colon := label(self, ":", Rect2(158, 4, 10, 20), 15, Color("fffde0"))
	colon.add_theme_constant_override("outline_size", 1)
	colon.add_theme_color_override("font_outline_color", Color("26353b"))
	if not in_battle:
		panel(self, Rect2(207, 5, 81, 19), palette.deep, palette.edge)
	round_label = label(self, "", Rect2(205 if in_battle else 210, 4, 113 if in_battle else 77, 21), 13, palette.deep if in_battle else Color("efe82e"))
	if not in_battle:
		var reward := TextureRect.new()
		reward.texture = load("res://assets/ui/scene_reward.png")
		reward.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		reward.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(reward)
		reward.position = Vector2(291, 0)
		reward.size = Vector2(28, 28)
		button(self, "", Rect2(290, 0, 30, 28), 1).pressed.connect(func() -> void: action_requested.emit("reward"))
	message_panel = panel(self, Rect2(0, 424 if in_battle else 403, 320, 56 if in_battle else 55), palette.main, Color("efe7a3"))
	log_label = label(message_panel, "", Rect2(5, 3, 306, 50), 10, Color("fff5dc"))
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.clip_text = true
	hint = label(self, "", Rect2(57, 408 if in_battle else 382, 210, 15), 10, Color("80d765"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_constant_override("outline_size", 1)
	hint.add_theme_color_override("font_outline_color", Color("355f38"))
	if not in_battle: _toolbar()
	update_header(int(Game.player.hp), int(Game.player.mp), 0)

func _toolbar() -> void:
	toolbar = panel(self, Rect2(0, 458, 320, 22), palette.main, palette.edge)
	var entries := ["menu", "quest", "map", "menu", "mail", "social", "bag"]
	var icons := [-1, 5, 6, 7, 8, 9, -1]
	for i in 7:
		var x := 1 + i * 45
		panel(toolbar, Rect2(x, 1, 44, 20), palette.main, palette.edge)
		if icons[i] >= 0:
			var icon := TextureRect.new()
			icon.texture = load("res://assets/ui/scene_icon_%d.png" % icons[i])
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			toolbar.add_child(icon)
			icon.position = Vector2(x + 9, 1)
			icon.size = Vector2(27, 20)
		var caption := "菜单" if i == 0 else ("背包" if i == 6 else "")
		var entry := button(toolbar, caption, Rect2(x, 1, 44, 20), 11)
		entry.add_theme_color_override("font_color", Color("f1e42c"))
		entry.add_theme_color_override("font_outline_color", Color("514a17"))
		entry.add_theme_constant_override("outline_size", 1)
		entry.pressed.connect(func() -> void: action_requested.emit(entries[i]))

func update_header(hp: int, mp: int, round_number: int) -> void:
	var values := Game.stats()
	hp_bar.max_value = values.hp
	hp_bar.value = hp
	mp_bar.max_value = values.mp
	mp_bar.value = mp
	xp_bar.max_value = int(Game.player.level) * 40
	xp_bar.value = int(Game.player.xp)
	var time := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [int(time.hour), int(time.minute)]
	clock_hour.value = "%02d" % int(time.hour)
	clock_minute.value = "%02d" % int(time.minute)
	clock_hour.queue_redraw()
	clock_minute.queue_redraw()
	round_label.text = "回合：%d/%d" % [round_number, ShushanBattle.MAX_ROUNDS] if in_battle else "常规模式"

static func panel(parent: Node, rect: Rect2, fill: Color, border: Color) -> Panel:
	var node := Panel.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

static func label(parent: Node, value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = value
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

static func button(parent: Node, value: String, rect: Rect2, font_size: int) -> Button:
	var node := Button.new()
	node.text = value
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("fff8c5"))
	for state in ["normal", "hover", "pressed", "focus"]: node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

static func progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var node := ProgressBar.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("456b90")
	bg.border_color = Color("739fd2")
	bg.set_border_width_all(1)
	var fill := bg.duplicate()
	fill.bg_color = color
	node.add_theme_stylebox_override("background", bg)
	node.add_theme_stylebox_override("fill", fill)
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node
