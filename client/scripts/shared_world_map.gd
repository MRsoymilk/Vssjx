class_name SharedWorldMap
extends RefCounted
## Mode-independent terrain, collision and scenery. The server validates MAP_PATH's bytes.
const MAP_PATH := "res://assets/data/qingyun-v1.json"
const POPULATION_PATH := "res://assets/data/qingyun-population-v1.json"

static func load_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))

static func population() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(POPULATION_PATH))

static func build(terrain: TileMapLayer, grid: AStarGrid2D, data: Dictionary) -> void:
	var width := int(data.width)
	var cell_size := int(data.cell_size)
	grid.region = Rect2i(0, 0, width, int(data.height))
	grid.cell_size = Vector2(cell_size, cell_size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(cell_size, cell_size)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/tiles/original_tiles.png")
	atlas.texture_region_size = tiles.tile_size
	for index in 756: atlas.create_tile(Vector2i(index % 32, index / 32))
	tiles.add_source(atlas, 0)
	terrain.clear()
	terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain.tile_set = tiles
	for index in data.tiles.size():
		var point := Vector2i(index % width, index / width)
		var tile := int(data.tiles[index])
		terrain.set_cell(point, 0, Vector2i(tile % 32, tile / 32))
		grid.set_point_solid(point, data.blocked[index])

static func add_scenery(parent: Node2D, data: Dictionary) -> void:
	for prop in data.scenery:
		var actor := OriginalArt.actor(prop.art)
		actor.position = Vector2(prop.x, prop.y)
		parent.add_child(actor)
