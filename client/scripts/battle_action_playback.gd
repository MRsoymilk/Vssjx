class_name BattleActionPlayback
extends RefCounted
## Native ANI state-5 target origin, per-step motion and event-mask timing.
signal impact
signal completed
var actor: AnimatedSprite2D
var action: StringName
var active := false
var impacted := false
var cancelled := false
var elapsed := 0.0
var duration := 0.0
var impact_time := 0.0
var home := Vector2.ZERO
var target := Vector2.ZERO
var _durations: Array[float] = []
var _x: Array = []

func start(subject: AnimatedSprite2D, info: Dictionary, target_position: Vector2, mode: StringName = &"attack") -> void:
	actor = subject
	action = mode
	home = actor.position
	target = target_position
	active = true
	impacted = false
	cancelled = false
	elapsed = 0.0
	duration = 0.0
	_durations.clear()
	var frames := actor.sprite_frames
	for index in frames.get_frame_count(action):
		var seconds := frames.get_frame_duration(action, index) / frames.get_animation_speed(action)
		_durations.append(seconds)
		duration += seconds
	var native: Dictionary = info.get("native_battle", {})
	_x = native.get("attack_x", []) if action == &"attack" else []
	var hits: Array = native.get("impact_steps", {}).get(String(action), [])
	impact_time = duration * 0.5 # Unrecovered skill payload: existing single-result presentation only.
	if not hits.is_empty():
		impact_time = 0.0
		for index in int(hits[0]): impact_time += _durations[index]
	actor.play(action)
	actor.pause()
	_sample()

func remaining() -> float:
	return maxf(0.0, duration - elapsed) if active else 0.0

func advance(delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		cancel()
		return
	elapsed = minf(duration, elapsed + maxf(0.0, delta))
	if not impacted and elapsed >= impact_time:
		_sample(impact_time)
		impacted = true
		impact.emit()
	if not active: return # An impact callback may replace/cancel the battle.
	_sample()
	if elapsed >= duration:
		active = false
		_restore()
		completed.emit()

func _sample(at: float = -1.0) -> void:
	var time := elapsed if at < 0 else at
	var step := 0
	while step < _durations.size() - 1 and time >= _durations[step]:
		time -= _durations[step]
		step += 1
	actor.set_frame_and_progress(step, clampf(time / _durations[step], 0.0, 1.0))
	if _x.size() == _durations.size():
		# Stable atlases remove head/root translation; restore the source center
		# at the native target basis, reflecting the entire actor with its side.
		# global_scale decomposes reflected X into rotation/negative Y in Godot;
		# use the signed transform basis so enemy-side attacks move inward too.
		actor.global_position = target + Vector2(float(_x[step]) * actor.global_transform.x.x, 0)

func _restore() -> void:
	if is_instance_valid(actor):
		actor.position = home
		actor.play("idle")

func cancel() -> void:
	if not active: return
	active = false
	cancelled = true
	_restore()
	# Release callers awaiting either stage. They must inspect cancelled/epoch.
	if not impacted: impact.emit()
	completed.emit()
