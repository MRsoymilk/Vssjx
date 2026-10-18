extends Node2D

var ground: Sprite2D
var gate: Dictionary = {}
const TILE := preload("res://assets/ui/portal_tile.png")

func _ready() -> void:
	# neverpic frame 0 is the original cyan spiral transfer tile. select.ani
	# belongs to selection/move targets and is not a map portal.
	for point in gate.get("cells",[gate.get("cell",[0,0])]):
		var tile := Sprite2D.new()
		tile.name = "NativeTransferTile"
		tile.texture = TILE
		tile.position=Vector2(point[0]-gate.get("cell",[0,0])[0],point[1]-gate.get("cell",[0,0])[1])*16.0
		tile.z_index = 0
		add_child(tile,false,Node.INTERNAL_MODE_BACK)
		if ground==null:ground=tile
