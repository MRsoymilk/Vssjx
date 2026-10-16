class_name OriginalPlayerRing
extends Node2D
## Native dongtai1 ring: under the local character, with its own facing/size.

func _ready() -> void:
	_sync_anchor()

func _process(_delta: float) -> void:
	_sync_anchor()

func _sync_anchor() -> void:
	var actor := get_parent() as Node2D
	if actor != null:
		global_transform = Transform2D(0.0, actor.global_position)
