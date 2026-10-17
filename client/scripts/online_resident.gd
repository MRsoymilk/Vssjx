class_name OnlineResident
extends Node2D
var data: Dictionary = {}
var sprite: AnimatedSprite2D
var motion := OnlineActorMotion.new()
var distance := 0.0

func set_quest_stage(stage: int) -> void:
	$QuestMarker.set_stage(stage if data.get("kind") == "npc" else -1)

func receive(value: Dictionary, grid: AStarGrid2D) -> void:
	if sprite == null:
		sprite = OriginalArt.actor(value.art)
		$Sprite.add_child(sprite)
		$Name.text = value.name
		if value.kind != "npc": $Name.add_theme_color_override("font_color", Color("ffb29a"))
		motion.speed = 28.0
	data = value.duplicate(true)
	motion.receive(value, grid)
	position = motion.position

func advance(delta: float) -> void:
	var before := position
	motion.advance(delta)
	position = motion.position
	if motion.travelled > 0.001:
		distance += motion.travelled
		if absf(position.x - before.x) > 0.001: sprite.scale.x = 1.0 if position.x < before.x else -1.0
		sprite.animation = "walk"
		sprite.pause()
		var count := sprite.sprite_frames.get_frame_count("walk")
		var phase := distance / 24.0 * count
		sprite.set_frame_and_progress(int(phase) % count, fposmod(phase, 1.0))
	elif not motion.has_motion():
		distance = 0.0
		if sprite.animation != "idle" or not sprite.is_playing(): sprite.play("idle")

func hit(point: Vector2) -> bool:
	return Rect2(position + Vector2(-25, -60), Vector2(50, 64)).has_point(point)
