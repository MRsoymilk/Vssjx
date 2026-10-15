class_name OriginalBattleField
extends Node2D
## Original tile vocabulary, with hand-authored layouts matching the references.

var kind := "courtyard"
var terrain: TileMapLayer

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain = TileMapLayer.new()
	var set := TileSet.new()
	set.tile_size = Vector2i(16, 16)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/tiles/original_tiles.png")
	atlas.texture_region_size = Vector2i(16, 16)
	for i in 756: atlas.create_tile(Vector2i(i % 32, i / 32))
	set.add_source(atlas)
	terrain.tile_set = set
	add_child(terrain)
	for y in 25:
		for x in 20:
			var tile := 159
			match kind:
				"courtyard":
					var lawn := (x < 4 or x > 15) and (y < 7 or y > 17)
					tile = (14 if (x + y) % 4 else 13) if lawn else [157, 158, 159, 167, 168, 169][x % 3 + (y % 2) * 3]
					if lawn and (x * 13 + y * 7) % 23 == 0: tile = 3
				"wilderness":
					tile = 325 if (x * 13 + y * 7) % 37 else 329
				"snow": tile = 474 if (x * 5 + y * 3) % 29 else 456
				"ruins": tile = _ruins_tile(Vector2i(x, y))
			_put(Vector2i(x, y), tile)
	if kind == "courtyard":
		_house(Vector2i(0, 4))
		_house(Vector2i(15, 19))
	elif kind == "wilderness":
		_prop("map/m6", Vector2(26, 83))
		_prop("map/m1", Vector2(299, 349))
	elif kind == "snow":
		_prop("map/m7", Vector2(35, 112))
		_prop("map/m7", Vector2(297, 360))
	else:
		_prop("map/m9", Vector2(34, 99))
		_prop("map/m10", Vector2(302, 353))
	var wash := ColorRect.new()
	wash.color = Color(0.9, 0.88, 0.72, 0.22)
	wash.size = Vector2(320, 400)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

func _put(point: Vector2i, tile: int) -> void:
	terrain.set_cell(point, 0, Vector2i(tile % 32, tile / 32))

func _island(point: Vector2i) -> bool:
	return point.x >= 1 and point.x <= 18 and point.y >= 1 and point.y <= 23 and not (point.x < 5 and point.y < 6) and not (point.x > 15 and point.y < 7) and not (point.x < 4 and point.y > 19)

func _ruins_tile(point: Vector2i) -> int:
	if not _island(point): return 219
	var top := not _island(point + Vector2i.UP)
	var left := not _island(point + Vector2i.LEFT)
	var right := not _island(point + Vector2i.RIGHT)
	var bottom := not _island(point + Vector2i.DOWN)
	if top and left: return 247
	if top and right: return 249
	if bottom and left: return 267
	if bottom and right: return 269
	if top: return 248
	if left: return 257
	if right: return 259
	if bottom: return 268
	return 258 if (point.x * 13 + point.y * 7) % 31 else 222

func _house(start: Vector2i) -> void:
	var rows := [[150, 151, 152, 152, 153, 154], [155, 160, 160, 160, 164, 156], [165, 161, 162, 162, 163, 166]]
	for y in 3:
		for x in 6:
			if start.x + x < 20: _put(start + Vector2i(x, y), rows[y][x])

func _prop(key: String, point: Vector2) -> void:
	var sprite := OriginalArt.actor(key)
	sprite.position = point
	add_child(sprite)
