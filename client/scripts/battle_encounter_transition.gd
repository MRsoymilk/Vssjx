class_name BattleEncounterTransition
extends Control
## Encounter warning and local preparation progress, not a network loading claim.
const BAR_RECT := Rect2(48, 370, 224, 20)
var progress := 0.0
var warning_anchor := Vector2(134, 160)
@onready var warning: Label = $Warning
@onready var caption: Label = $Caption
@onready var detail: Label = $Detail

func configure(enemy_name: String, hero_point: Vector2) -> void:
	set_hero_point(hero_point)
	caption.text = "遭遇%s！" % enemy_name
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func set_hero_point(hero_point: Vector2) -> void:
	warning_anchor = Vector2(clampf(roundf(hero_point.x - 25), 25, 295), clampf(roundf(hero_point.y - 45), 60, 310))
	warning.position = warning_anchor - Vector2(5, 21)
	queue_redraw()

func set_progress(value: float, text_value: String) -> void:
	progress = maxf(progress, clampf(value, 0.0, 1.0))
	detail.text = text_value
	queue_redraw()

func _draw() -> void:
	# Keep the map visible, with a readable white burst beside the character.
	var burst := PackedVector2Array()
	for index in 16:
		var angle := -PI / 2 + index * TAU / 16
		var radius := 23.0 if index % 2 == 0 else 13.0
		burst.append((warning_anchor + Vector2(cos(angle), sin(angle)) * radius).round())
	draw_colored_polygon(burst, Color("fffbe7"))
	var outline := burst.duplicate()
	outline.append(burst[0])
	draw_polyline(outline, Color("302b22"), 2.0)
	# Gold/white stepped border, blue track and segmented cyan-green fill.
	draw_rect(BAR_RECT, Color("38372d"))
	draw_rect(BAR_RECT.grow(-1), Color("e0d489"))
	draw_rect(BAR_RECT.grow(-3), Color("fff5c0"))
	draw_rect(BAR_RECT.grow(-4), Color("1f4b70"))
	var track := BAR_RECT.grow(-6)
	var filled := floorf(track.size.x * progress)
	if filled <= 0: return
	draw_rect(Rect2(track.position, Vector2(filled, track.size.y)), Color("49b9d1"))
	draw_rect(Rect2(track.position, Vector2(filled, 2)), Color("a6edf0"))
	for offset in range(0, mini(int(filled), 27), 9):
		draw_rect(Rect2(track.position + Vector2(offset, 2), Vector2(minf(4, filled - offset), track.size.y - 2)), Color("a7de3c"))
