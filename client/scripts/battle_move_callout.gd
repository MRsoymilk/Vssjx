class_name BattleMoveCallout
extends Control
## Pixel-edged move announcement; visual only, never drives battle resolution.
@onready var caption: Label = $Caption
var remaining := 0.0
var tail_x := 0.0

func present(text_value: String, anchor: Vector2, seconds: float) -> void:
	caption.text = text_value
	var font := caption.get_theme_font("font")
	var width := clampf(ceilf(font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 16, 64, 156)
	size = Vector2(width, 35)
	position = Vector2(clampf(roundf(anchor.x - width / 2), 4, 316 - width), clampf(roundf(anchor.y - size.y), 30, 370))
	tail_x = clampf(anchor.x - position.x, 10, width - 10)
	caption.size = Vector2(width - 10, 21)
	remaining = maxf(0.1, seconds)
	show()
	queue_redraw()

func clear() -> void:
	remaining = 0.0
	hide()

func _process(delta: float) -> void:
	if not visible: return
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0: hide()

func _draw() -> void:
	var body := Rect2(0, 0, size.x, 25)
	draw_rect(Rect2(1, 2, size.x, 25), Color("786b3c"))
	draw_rect(body, Color("58421d"))
	draw_rect(body.grow(-1), Color("eee19c"))
	draw_rect(body.grow(-3), Color("fff1b0"))
	draw_rect(Rect2(4, 3, size.x - 8, 1), Color("fffbd1"))
	var edge := PackedVector2Array([Vector2(tail_x - 7, 23), Vector2(tail_x + 2, 35), Vector2(tail_x + 5, 23)])
	draw_colored_polygon(edge, Color("58421d"))
	draw_colored_polygon(PackedVector2Array([Vector2(tail_x - 4, 23), Vector2(tail_x + 1, 31), Vector2(tail_x + 3, 23)]), Color("fff1b0"))
