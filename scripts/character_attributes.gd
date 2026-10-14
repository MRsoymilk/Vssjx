class_name OriginalCharacterAttributes
extends Control
## Layout follows the game area of the supplied properties screenshot.

signal back_requested
const BROWN := Color("654518")
const TABS := ["常规", "扩展", "武功", "心法"]
var selected_tab := 0
var content: Control
var signature: LineEdit
var preview: AnimatedSprite2D
var tab_buttons: Array[Button] = []
var bars: Dictionary = {}
var numbers: Dictionary = {}
var snapshot: Dictionary = {}
var cursor: TextureRect
var palette: Dictionary

func _ready() -> void:
	size = Vector2(320, 480)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimHei", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var skin := Theme.new()
	skin.default_font = font
	skin.default_font_size = 15
	theme = skin
	palette = OriginalUITheme.palette("attributes")
	_panel(self, Rect2(0, 0, 320, 480), palette.body, palette.main)
	_panel(self, Rect2(1, 1, 318, 34), palette.deep, Color("ffd990"), 2)
	_panel(self, Rect2(16, 5, 288, 25), palette.deep, Color("ddba76"))
	_picture("create_header_end", Rect2(1, 1, 16, 34))
	_picture("create_header_end", Rect2(303, 1, 16, 34), true)
	_text(self, "人物属性", Rect2(68, 7, 184, 24), 18, true, Color("e8de90"))
	var spiral_shader := Shader.new()
	spiral_shader.code = "shader_type canvas_item; void fragment() { vec4 pixel = texture(TEXTURE, UV); float shade = dot(pixel.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(mix(vec3(0.76, 0.46, 0.23), vec3(1.0, 0.85, 0.49), step(0.45, shade)), pixel.a); }"
	var spiral_material := ShaderMaterial.new()
	spiral_material.shader = spiral_shader
	_picture("attribute_spiral", Rect2(44, 49, 23, 24)).material = spiral_material
	_picture("attribute_spiral", Rect2(255, 49, 23, 24), true).material = spiral_material
	for i in 4:
		var button := _button(self, TABS[i], Rect2(73 + i * 45, 41, 45, 35), 17)
		button.pressed.connect(select_tab.bind(i))
		tab_buttons.append(button)
	_panel(self, Rect2(3, 76, 314, 365), Color("fff0b4"), Color("dc9b5e"), 1)
	content = Control.new()
	content.name = "AttributeContent"
	add_child(content)
	cursor = _picture("create_cursor", Rect2(105, 64, 17, 17))
	_text(self, "签名", Rect2(15, 449, 36, 24), 16)
	signature = LineEdit.new()
	signature.name = "Signature"
	signature.text = String(Game.player.get("signature", ""))
	signature.max_length = 40
	signature.add_theme_font_size_override("font_size", 12)
	signature.add_theme_color_override("font_color", BROWN)
	signature.add_theme_color_override("caret_color", BROWN)
	var input_skin := _style(Color("ffe4a0"), Color("f3c87a"))
	input_skin.content_margin_left = 3
	input_skin.content_margin_right = 3
	signature.add_theme_stylebox_override("normal", input_skin)
	signature.add_theme_stylebox_override("focus", input_skin)
	add_child(signature)
	signature.position = Vector2(52, 446)
	signature.size = Vector2(192, 29)
	signature.text_changed.connect(func(value: String) -> void: Game.player.signature = value)
	signature.text_submitted.connect(func(_value: String) -> void: signature.release_focus())
	_picture("create_edit", Rect2(249, 450, 15, 18))
	var edit := _button(self, "", Rect2(245, 446, 24, 29), 1)
	for state in ["normal", "hover", "pressed", "focus"]: edit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	edit.pressed.connect(func() -> void: signature.grab_focus(); signature.caret_column = signature.text.length())
	var back := _button(self, "返回", Rect2(271, 446, 46, 31), 16)
	for state in ["normal", "hover", "pressed"]:
		back.add_theme_stylebox_override(state, _style(Color("b77c32"), Color("77380e"), 2))
	back.add_theme_color_override("font_color", Color("fff9d2"))
	back.add_theme_color_override("font_outline_color", BROWN)
	back.add_theme_constant_override("outline_size", 1)
	var inset := _panel(back, Rect2(3, 3, 40, 25), Color.TRANSPARENT, Color("f7da90"))
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.pressed.connect(func() -> void: back_requested.emit())
	select_tab(0)

func select_tab(index: int) -> void:
	selected_tab = posmod(index, 4)
	for i in 4:
		var fill: Color = Color("bef38b") if i == selected_tab else palette.main
		for state in ["normal", "hover", "pressed"]:
			tab_buttons[i].add_theme_stylebox_override(state, _style(fill, Color("e3ee9d") if i == selected_tab else fill))
		tab_buttons[i].add_theme_color_override("font_color", Color("507030") if i == selected_tab else palette.deep)
	cursor.position.x = 105 + selected_tab * 45
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	preview = null
	bars.clear()
	numbers.clear()
	if selected_tab == 0: _regular()
	elif selected_tab == 1: _extended()
	else: _skills()
	move_child(cursor, get_child_count() - 1)

func _regular() -> void:
	var stats := Game.stats()
	snapshot = Game.player.duplicate(true)
	snapshot["max_hp"] = stats.hp
	snapshot["max_mp"] = stats.mp
	snapshot["next_xp"] = int(Game.player.level) * 40
	_panel(content, Rect2(14, 88, 116, 124), Color("ffe49b"), Color("fff3ba"), 2)
	_panel(content, Rect2(136, 88, 172, 124), Color("ffe49b"), Color("fff3ba"), 2)
	preview = OriginalArt.actor(Game.actor_key())
	preview.position = Vector2(76, 193)
	preview.scale = Vector2(1.8, 1.8)
	content.add_child(preview)
	var labels := ["名称", "等级", "职业", "门派", "称号"]
	var values := [String(Game.player.name), "", Game.JOBS[int(Game.player.job)], Game.SCHOOLS[int(Game.player.school)] + "派", String(Game.player.get("title", ""))]
	if values[4].is_empty(): values[4] = "无"
	for i in 5:
		var y := 94 + i * 22
		if i == 4: _panel(content, Rect2(145, y, 40, 21), Color("f76046"), Color("c6502b"))
		_text(content, labels[i], Rect2(149, y, 43, 23), 16)
		if i == 1:
			_number("level", str(int(Game.player.level)), Rect2(202, y + 2, 26, 16), "green", false)
		else:
			var label := _text(content, values[i], Rect2(202, y, 103, 23), 16)
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel(content, Rect2(14, 216, 294, 107), Color("ffe49b"), Color("fff3ba"), 2)
	_resource("hp", "气血", int(Game.player.hp), int(stats.hp), 226, Color("cbea11"))
	_resource("mp", "灵力", int(Game.player.mp), int(stats.mp), 257, Color("51d7db"))
	_resource("xp", "经验", int(Game.player.xp), int(snapshot.next_xp), 288, Color("bd8a53"))
	_panel(content, Rect2(14, 327, 294, 104), Color("ffe49b"), Color("fff3ba"), 2)
	var keys := ["gold", "ingots", "guild_contribution", "essence"]
	var captions := ["铜币", "金锭", "帮贡", "精元"]
	var icons := ["coin", "ingot", "guild", "essence"]
	for i in 4:
		var y := 333 + i * 24
		_text(content, captions[i], Rect2(21, y, 54, 23), 16)
		var texture: Texture2D = load("res://assets/ui/attribute_%s.png" % icons[i])
		_picture("attribute_" + icons[i], Rect2(Vector2(80, y + 1), texture.get_size() * 1.3), false, content)
		_number(keys[i], str(int(Game.player.get(keys[i], 0))), Rect2(118, y + 4, 179, 16), "white", false)

func _resource(key: String, caption: String, current: int, maximum: int, y: int, fill: Color) -> void:
	_text(content, caption, Rect2(21, y + 1, 54, 26), 17)
	_number(key, "%d/%d" % [current, maximum], Rect2(103, y - 2, 187, 14))
	var bar := ProgressBar.new()
	bar.name = key + "Bar"
	bar.max_value = maximum
	bar.value = current
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color("a37d45"), BROWN, 1))
	bar.add_theme_stylebox_override("fill", _style(fill, BROWN, 1))
	content.add_child(bar)
	bar.position = Vector2(67, y + 13)
	bar.size = Vector2(225, 10)
	bars[key] = bar

func _extended() -> void:
	var stats := Game.stats()
	var fields := ["体质", "灵性", "力量", "敏捷", "定力", "物攻", "法攻", "物暴", "法暴", "命中", "法命", "物防", "法防", "物闪", "法闪", "减伤"]
	for i in fields.size():
		var column := i % 2
		var y := 96 + (i / 2) * 33
		_text(content, fields[i], Rect2(22 + column * 145, y, 59, 25), 16)
		var value := "—"
		# Only expose formulas present in the offline game; other server stats
		# have not been recovered from the original client.
		if fields[i] == "物攻" and int(Game.player.job) != 2: value = str(int(stats.attack))
		if fields[i] == "法攻" and int(Game.player.job) == 2: value = str(int(stats.attack))
		if fields[i] == "物防": value = str(int(stats.defense))
		_text(content, value, Rect2(87 + column * 145, y, 56, 25), 15)
	_text(content, "属性点  0", Rect2(22, 371, 270, 25), 15)
	_text(content, "— 暂无属性信息", Rect2(22, 407, 280, 20), 11)

func _skills() -> void:
	if selected_tab == 3:
		_text(content, "暂无已修习心法", Rect2(20, 115, 280, 25), 15, true)
		return
	var names := ["破山诀", "御剑诀", "摄灵诀"]
	_text(content, names[int(Game.player.job)], Rect2(22, 99, 260, 25), 17)
	_text(content, "（消耗灵力9）", Rect2(22, 132, 260, 25), 15)
	var descriptions := ["重击敌人，并造成额外伤害。", "剑气攻击敌人，并造成额外伤害。", "攻击敌人，同时恢复自身气血。"]
	_text(content, descriptions[int(Game.player.job)], Rect2(22, 171, 273, 52), 14).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text(content, "技能点  0", Rect2(22, 371, 270, 25), 15)

func _number(key: String, value: String, rect: Rect2, color: String = "white", right: bool = true) -> OriginalNumber:
	var node := OriginalNumber.new()
	node.value = value
	node.color_set = color
	node.align_right = right
	node.position = rect.position
	node.size = rect.size
	content.add_child(node)
	numbers[key] = node
	return node

func _style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style

func _panel(parent: Node, rect: Rect2, fill: Color, border: Color, width: int = 1) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", _style(fill, border, width))
	parent.add_child(node)
	return node

func _text(parent: Node, value: String, rect: Rect2, font_size: int, center: bool = false, color: Color = BROWN) -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	if center: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(node)
	return node

func _button(parent: Node, caption: String, rect: Rect2, font_size: int) -> Button:
	var node := Button.new()
	node.text = caption
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed"]: node.add_theme_stylebox_override(state, _style(Color("ff6e55"), Color("ff6e55")))
	node.add_theme_color_override("font_color", BROWN)
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

func _picture(key: String, rect: Rect2, mirrored: bool = false, parent: Node = null) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load("res://assets/ui/%s.png" % key)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.flip_h = mirrored
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node
