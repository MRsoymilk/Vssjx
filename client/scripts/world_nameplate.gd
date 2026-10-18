extends RefCounted
## Scene text has its own readable font; pixel filtering remains on the art.
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const FONT_SIZE := 13
const GROUP := "world_nameplates"

static func apply(label: Label, color: Color, world_source: bool = true) -> void:
	if world_source:label.add_to_group(GROUP)
	label.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",FONT_SIZE)
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_outline_color",Color("14251d"))
	label.add_theme_constant_override("outline_size",1)
	label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var width:=ceilf(maxf(144,FONT.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE).x+8)/2.0)*2.0
	label.size=Vector2(width,22)
	label.position.x=-width/2.0
