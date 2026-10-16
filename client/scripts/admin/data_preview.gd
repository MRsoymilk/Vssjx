extends Control
## Preview resources without starting world simulation or changing cached animations.

var record: Dictionary = {}
var sprite: AnimatedSprite2D
var icon: Texture2D
var atlas: Texture2D
var show_blocked := false
var overview_icons: Array[Texture2D] = []
var hovered_node: Dictionary = {}

func display(entry: Dictionary) -> void:
	if is_instance_valid(sprite):
		remove_child(sprite)
		sprite.queue_free()
	sprite = null
	icon = null
	record = entry
	hovered_node = {}
	tooltip_text = ""
	var preview: Dictionary = entry.get("preview", {})
	mouse_filter = Control.MOUSE_FILTER_PASS if preview.get("kind") == "world_overview" else Control.MOUSE_FILTER_IGNORE
	match preview.get("kind", ""):
		"actor":
			if OriginalArt.has_actor(preview.art):
				sprite = OriginalArt.actor(preview.art)
				add_child(sprite)
				_place_sprite()
		"monster":
			var info: Dictionary = preview.animation
			var frames := SpriteFrames.new()
			frames.remove_animation("default")
			var texture: Texture2D = load(info.texture)
			for index in info.sequences.size():
				var steps: Array = info.sequences[index]
				if steps.is_empty(): continue
				var animation := "source_%d" % index
				frames.add_animation(animation)
				frames.set_animation_speed(animation, 10.0)
				for step in steps:
					var region := AtlasTexture.new()
					region.atlas = texture
					var frame := int(step[0])
					region.region = Rect2((frame % int(info.columns)) * int(info.width), (frame / int(info.columns)) * int(info.height), info.width, info.height)
					frames.add_frame(animation, region, maxf(1.0, float(step[1])))
			sprite = AnimatedSprite2D.new()
			sprite.centered = false
			sprite.sprite_frames = frames
			sprite.offset = Vector2(info.origin[0], info.origin[1])
			add_child(sprite)
			_place_sprite()
			if frames.get_animation_names().size() > 0: sprite.play(frames.get_animation_names()[0])
		"icon": icon = load(preview.path)
		"map": atlas = load("res://assets/tiles/original_tiles.png")
		"world_overview":
			if overview_icons.is_empty():
				for index in 3: overview_icons.append(load("res://assets/ui/worldmap_node_%d.png" % index))
	queue_redraw()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	resized.connect(func() -> void: _place_sprite(); queue_redraw())
	mouse_exited.connect(func() -> void: hovered_node = {}; tooltip_text = ""; queue_redraw())

func overview_transform() -> Transform2D:
	var world: Dictionary = record.get("preview", {}).get("world", {})
	# Some original route endpoints exceed the header grid. Include them without
	# changing the audited dimensions or inventing an additional named location.
	var extent := Vector2(float(world.get("grid_width", 1)) - 1, float(world.get("grid_height", 1)) - 1)
	for route in world.get("routes", []):
		for point in [route["from"], route["to"]]: extent = extent.max(Vector2(point[0], point[1]))
	var step := maxf(1, minf((size.x - 56) / maxf(extent.x, 1), (size.y - 68) / maxf(extent.y, 1)))
	var start := Vector2((size.x - extent.x * step) * 0.5, 24)
	return Transform2D(Vector2(step, 0), Vector2(0, step), start)

func overview_node_at(point: Vector2) -> Dictionary:
	var transform := overview_transform()
	var nearest: Dictionary = {}
	var distance := maxf(8, transform.x.x * 0.48)
	for node in record.get("preview", {}).get("world", {}).get("nodes", []):
		var position: Array = node.world_position
		var delta := point.distance_to(transform * Vector2(position[0], position[1]))
		if delta < distance:
			distance = delta
			nearest = node
	return nearest

func _gui_input(event: InputEvent) -> void:
	if record.get("preview", {}).get("kind") != "world_overview": return
	if event is InputEventMouseMotion:
		hovered_node = overview_node_at(event.position)
		tooltip_text = _node_description(hovered_node) if not hovered_node.is_empty() else "世界总图 · 非场景地形"
		queue_redraw()

func _node_description(node: Dictionary) -> String:
	return "%s · #%d · %s · 等级 %d～%d" % [node.name, int(node.original_map_id), node.location_type, int(node.level_min), int(node.level_max)]

func _draw_overview() -> void:
	var preview: Dictionary = record.preview
	var world: Dictionary = preview.world
	var transform := overview_transform()
	var step := transform.x.x
	var selected: Dictionary = {}
	var font := get_theme_default_font()
	for route in world.get("routes", []):
		var a: Array = route["from"]
		var b: Array = route["to"]
		var start: Vector2 = transform * Vector2(a[0], a[1])
		var end: Vector2 = transform * Vector2(b[0], b[1])
		draw_line(start, end, Color("678e83"), maxf(1, step / 12))
		if route.from_map_id == null: draw_circle(start, 2, Color("a8b4b9"))
		if route.to_map_id == null: draw_circle(end, 2, Color("a8b4b9"))
	for node in world.get("nodes", []):
		var position: Array = node.world_position
		var center: Vector2 = transform * Vector2(position[0], position[1])
		var dimensions := Vector2.ONE * clampf(step * 0.85, 7, 22)
		var kind := int(node.location_kind)
		if kind < overview_icons.size() and overview_icons[kind] != null:
			draw_texture_rect(overview_icons[kind], Rect2(center - dimensions * 0.5, dimensions), false)
		if node.original_map_id == preview.selected_map_id:
			selected = node
			draw_arc(center, dimensions.x * 0.65 + 2, 0, TAU, 24, Color("ffd56b"), 2)
		if step >= 18 and (kind != 0 or node.original_map_id == preview.selected_map_id):
			var label: String = node.name
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var at := center + Vector2(-width * 0.5, -dimensions.y * 0.6 - 3)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color("101923"))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f7e6b4"))
	var description := "世界总图（非场景地形）· 当前目录无总图位置" if selected.is_empty() else _node_description(selected)
	if not hovered_node.is_empty(): description = _node_description(hovered_node)
	draw_string(font, Vector2(12, size.y - 12), description, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, Color("ffd56b"))

func _place_sprite() -> void:
	if not is_instance_valid(sprite): return
	var info: Dictionary = record.preview.animation if record.preview.kind == "monster" else OriginalArt.actor_info(record.preview.art)
	var dimensions := Vector2(info.width, info.height)
	var zoom := maxf(0.25, minf(2.0, minf((size.x - 30) / dimensions.x, (size.y - 24) / dimensions.y)))
	sprite.scale = Vector2.ONE * zoom
	sprite.position = size * 0.5 - (sprite.offset + dimensions * 0.5) * zoom

func animations() -> PackedStringArray:
	if not is_instance_valid(sprite): return PackedStringArray()
	return sprite.sprite_frames.get_animation_names()

func play_animation(animation: String) -> void:
	if is_instance_valid(sprite) and sprite.sprite_frames.has_animation(animation):
		sprite.stop()
		sprite.play(animation)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101923"))
	for y in range(0, int(size.y), 20):
		for x in range(0, int(size.x), 20):
			if (x / 20 + y / 20) % 2 == 0: draw_rect(Rect2(x, y, 20, 20), Color("14202b"))
	if record.get("preview", {}).get("kind") == "world_overview":
		_draw_overview()
		return
	if icon != null:
		var zoom := minf(4, minf((size.x - 40) / icon.get_width(), (size.y - 30) / icon.get_height()))
		var dimensions := icon.get_size() * zoom
		draw_texture_rect(icon, Rect2((size - dimensions) * 0.5, dimensions), false)
	if record.get("preview", {}).get("kind") != "map" or atlas == null: return
	var data: Dictionary = record.data
	var width := int(data.get("width", 0))
	var height := int(data.get("height", 0))
	var tiles: Array = data.get("tiles", [])
	if width <= 0 or height <= 0 or tiles.size() != width * height: return
	var cell := minf((size.x - 16) / width, (size.y - 16) / height)
	var start := (size - Vector2(width, height) * cell) * 0.5
	var blocked: Array = data.get("blocked", [])
	for y in height:
		for x in width:
			var i := y * width + x
			var tile := int(tiles[i])
			var rect := Rect2(start + Vector2(x, y) * cell, Vector2.ONE * cell)
			draw_texture_rect_region(atlas, rect, Rect2((tile % 32) * 16, (tile / 32) * 16, 16, 16))
			if show_blocked and i < blocked.size() and blocked[i]: draw_rect(rect, Color(1, 0.25, 0.28, 0.55))
	if data.has("spawn"):
		var spawn: Array = data.spawn
		draw_circle(start + (Vector2(spawn[0], spawn[1]) + Vector2.ONE * 0.5) * cell, cell * 0.6, Color("77efba"))
