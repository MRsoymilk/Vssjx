class_name BattleMoveCallout
extends Control
## Pixel-edged move announcement; visual only, never drives battle resolution.
@onready var caption: Label = $Caption
var remaining := 0.0
var tail_x := 0.0
var _subject: WeakRef
const HEAD_OFFSET := Vector2(0, -88)

func present(text_value: String, anchor: Vector2, seconds: float) -> void:
	_subject = null
	caption.text = text_value
	var font := caption.get_theme_font("font")
	var width := clampf(ceilf(font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 16, 64, 156)
	size = Vector2(width, 35)
	caption.size = Vector2(width - 10, 21)
	remaining = maxf(0.1, seconds)
	_place(anchor)
	show()

func present_for(text_value: String, subject: Node2D, seconds: float) -> void:
	if not is_instance_valid(subject) or not subject.is_inside_tree():
		clear()
		return
	present(text_value, Vector2.ZERO, seconds)
	_subject = weakref(subject)
	update_anchor()

func update_anchor() -> void:
	if _subject == null: return
	var subject := _subject.get_ref() as Node2D
	if not is_instance_valid(subject) or not subject.is_inside_tree():
		clear()
		return
	# Convert through canvas coordinates: the bubble remains upright even if
	# the actor faces the other way or lives in a scaled/translated station.
	var parent_canvas := get_parent() as CanvasItem
	var anchor := parent_canvas.get_global_transform_with_canvas().affine_inverse() * subject.get_global_transform_with_canvas().origin
	_place(anchor + HEAD_OFFSET)

func _place(anchor: Vector2) -> void:
	position = Vector2(clampf(roundf(anchor.x - size.x / 2), 4, 316 - size.x), clampf(roundf(anchor.y - size.y), 30, 370))
	tail_x = clampf(anchor.x - position.x, 10, size.x - 10)
	queue_redraw()

func clear() -> void:
	_subject = null
	remaining = 0.0
	hide()

func _process(delta: float) -> void:
	if not visible: return
	update_anchor()
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0: clear()

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
