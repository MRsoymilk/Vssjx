extends Node
## Export the ACTUAL Godot terrain and final AStar obstacles, including scenery.
func _ready() -> void:
	call_deferred("_export")

func _export() -> void:
	var game := get_tree().root.get_node("Game")
	game.new_player("地图导出", 0, 0)
	var world := ShushanWorld.new()
	add_child(world)
	world.enabled = false
	var tiles: Array = []
	var blocked: Array = []
	for y in 32:
		for x in 32:
			var cell := Vector2i(x, y)
			var tile := world.terrain.get_cell_atlas_coords(cell)
			tiles.append(tile.y * 32 + tile.x)
			blocked.append(world.astar.is_point_solid(cell))
	var scenery: Array = []
	for child in world.actors.get_children():
		if child is AnimatedSprite2D and child != world.hero and child.get_child_count() == 0:
			scenery.append({"art": "map/m2", "x": child.position.x, "y": child.position.y})
	var data := {"version": "qingyun-v1", "map_id": "qingyun_trail", "width": 32, "height": 32, "cell_size": 16, "spawn": [10,16], "tiles": tiles, "blocked": blocked, "scenery": scenery}
	var path := OS.get_environment("SSJX_MAP_EXPORT")
	if path.is_empty(): get_tree().quit(1); return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	world.queue_free()
	get_tree().quit()
