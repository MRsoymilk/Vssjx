class_name OriginalNumber
extends Control
## Original bitmap glyph order: slash, zero, one ... nine.

var value := ""
var color_set := "white"
var align_right := true
var glyphs: Array[Texture2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 11:
		glyphs.append(load("res://assets/ui/digit_%s_%02d.png" % [color_set, index]))
	queue_redraw()

func _draw() -> void:
	if glyphs.is_empty(): return
	var indices: Array[int] = []
	var total := 0.0
	for ch in value:
		var index := 0 if ch == "/" else int(ch) + 1
		indices.append(index)
		total += glyphs[index].get_width() - 1
	total += 1
	var factor := minf(size.y / glyphs[1].get_height(), size.x / maxf(total, 1))
	var x := size.x - total * factor if align_right else 0.0
	for index in indices:
		var texture := glyphs[index]
		var dimensions := texture.get_size() * factor
		draw_texture_rect(texture, Rect2(Vector2(x, (size.y - dimensions.y) / 2), dimensions), false)
		x += (texture.get_width() - 1) * factor
