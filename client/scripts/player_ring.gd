class_name OriginalPlayerRing
extends Node2D
## Native dongtai1 ring: under the local character, with its own facing/size.
var _visual_actor: AnimatedSprite2D

func _ready() -> void:
	_sync_anchor()

func _process(_delta: float) -> void:
	_sync_anchor()

func _sync_anchor() -> void:
	var actor := get_parent() as Node2D
	if actor == null: return
	if not is_instance_valid(_visual_actor):
		_visual_actor = actor as AnimatedSprite2D
		if _visual_actor == null:
			for child in actor.get_children():
				if child is AnimatedSprite2D and child.has_meta("ground_pose_x"):
					_visual_actor = child
					break
	var anchor := actor.global_position
	if is_instance_valid(_visual_actor):
		var offset := Vector2.ZERO
		if not _visual_actor.get_meta("native_ground_anchor", false):
			var poses: Dictionary = _visual_actor.get_meta("ground_pose_x", {})
			var steps: Array = poses.get(String(_visual_actor.animation), poses.get("idle", []))
			if not steps.is_empty(): offset.x = -float(steps[mini(_visual_actor.frame, steps.size() - 1)])
		anchor = _visual_actor.to_global(offset)
	global_transform = Transform2D(0.0, anchor)
