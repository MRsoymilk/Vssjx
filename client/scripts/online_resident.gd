class_name OnlineResident
extends Node2D
var data: Dictionary = {}
var sprite: AnimatedSprite2D
var motion := OnlineActorMotion.new()
var distance := 0.0

func set_quest_stage(stage: int, description: String = "") -> void:
	$QuestMarker.set_stage(stage if data.get("kind") == "npc" else -1)
	if not description.is_empty():$QuestMarker.tooltip_text=description

func receive(value: Dictionary, grid: AStarGrid2D) -> void:
	# NPCs remain above player sprites and their team flags (z=5).
	z_index = 10 if value.kind == "npc" else 8
	if sprite == null:
		sprite = OriginalArt.actor(value.art)
		$Sprite.add_child(sprite)
		$Name.text = "%d级 %s" % [int(value.level), String(value.name)] if value.kind!="npc" else value.name + (" · AI" if not AIWorld.resident(value.id).is_empty() else "")
		$Name.position.y=-74
		preload("res://scripts/world_nameplate.gd").apply($Name,Color("ff3030") if value.kind!="npc" else Color("ffe095"))
		var definition := AIWorld.resident(value.id)
		if value.kind=="npc" and not String(definition.get("service_label","")).is_empty():
			$QuestMarker.position.y=-114
			var service := Label.new()
			service.name="ServiceLabel";service.text=definition.service_label;service.position.y=-92
			preload("res://scripts/world_nameplate.gd").apply(service,Color("c2f7f4"))
			add_child(service)
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
	return WorldSpriteHit.hit(sprite, get_parent().to_global(point))
