extends RefCounted
## Reuse recovered corners, creation portraits and wood buttons. Layout is a
## reconstruction in the game's palette, not a claim of an original PK screen.
const INK := Color("654518")
const PAPER := Color("fff1b8")
const WOOD := preload("res://assets/ui/chat_wood_button.svg")
const CORNER := preload("res://assets/ui/chat_corner.png")

static func frame(parent: Node, rect: Rect2, title: String) -> Panel:
	var panel := OriginalSceneChrome.panel(parent, rect, Color("b97a24"), Color("654518"))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	OriginalSceneChrome.panel(panel, Rect2(2, 2, rect.size.x-4, rect.size.y-4), Color("bf842d"), Color("ffe69b"))
	OriginalSceneChrome.panel(panel, Rect2(7, 7, rect.size.x-14, rect.size.y-14), PAPER, INK)
	OriginalSceneChrome.panel(panel, Rect2(8, 8, rect.size.x-16, 25), Color("9e3b27"), Color("d8a64e"))
	var heading := OriginalSceneChrome.label(panel, title, Rect2(18, 8, rect.size.x-36, 25), 15, Color("fff0ae"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for i in 4:
		var corner := TextureRect.new()
		corner.texture = CORNER
		corner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		corner.size = Vector2(14, 14)
		corner.position = Vector2(0 if i%2==0 else rect.size.x-14, 0 if i<2 else rect.size.y-14)
		corner.flip_h = i%2==1
		corner.flip_v = i<2
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(corner)
	return panel

static func button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = WOOD
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_texture_margin(side, 5)
			style.set_content_margin(side, 5)
		style.modulate_color = {"normal":Color.WHITE, "hover":Color("ffe6a9"), "pressed":Color("cdb380"), "disabled":Color("b5a58e")}[state]
		b.add_theme_stylebox_override(state, style)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 12)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(state, Color("fff5c8") if state!="font_disabled_color" else Color("49341d"))
	b.add_theme_color_override("font_shadow_color", Color("654518"))
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(b)
	return b

static func placed_button(parent: Node, text: String, rect: Rect2) -> Button:
	var b := button(parent, text)
	b.position = rect.position
	b.size = rect.size
	return b
