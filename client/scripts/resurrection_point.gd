extends Node2D

func _draw() -> void:
	_draw_ground_ring()
	draw_line(Vector2(-9,-2),Vector2(-9,-17),Color("9da5b8"),3)
	draw_line(Vector2(9,-2),Vector2(9,-17),Color("9da5b8"),3)
	draw_line(Vector2(-11,-17),Vector2(11,-17),Color("d7dcd3"),3)
	draw_circle(Vector2(0,-16),3,Color("8adfc3"))

func _draw_ground_ring() -> void:
	var points:=PackedVector2Array()
	for index in 25:points.append(Vector2(cos(index*TAU/24.0)*14,sin(index*TAU/24.0)*6))
	draw_polyline(points,Color("96c9bd"),1)
