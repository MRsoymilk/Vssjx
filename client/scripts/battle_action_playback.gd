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
var _front_root: Node
var _front_parent: Node
var _front_index := -1

func start(subject: AnimatedSprite2D, info: Dictionary, target_position: Vector2, mode: StringName = &"attack", receiver: AnimatedSprite2D = null) -> void:
	if active: cancel()
	actor = subject
	action = mode
	home = actor.position
	target = target_position
	active = true
	impacted = false
	cancelled = false
	elapsed = 0.0
	duration = 0.0
	impact_time = 0.0
	_durations.clear()
	_x = []
	var frames := actor.sprite_frames
	# A missing/empty animation must not leave a permanent active playback token.
	if frames==null or not frames.has_animation(action) or frames.get_frame_count(action)==0:
		action=&"idle"
	if frames==null or not frames.has_animation(action) or frames.get_frame_count(action)==0 or frames.get_animation_speed(action)<=0:return
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
		for index in mini(int(hits[0]),_durations.size()): impact_time += _durations[index]
	actor.play(action)
	actor.pause()
	_layer_attacker(receiver)
	_sample()

func _layer_attacker(receiver: AnimatedSprite2D) -> void:
	if not is_instance_valid(receiver) or receiver == actor: return
	# Offline actors are siblings; online actors sit in separate station roots.
	# Native 2f28..2f40 selects the acting side as list +48; 3174..317e
	# renders +4c first and +48 last. Keep effects/HUD above both branches.
	var parent := actor.get_parent()
	while parent != null and not parent.is_ancestor_of(receiver): parent = parent.get_parent()
	if parent == null: return
	var back: Node = receiver
	var front: Node = actor
	while back.get_parent() != parent: back = back.get_parent()
	while front.get_parent() != parent: front = front.get_parent()
	if back == front or front.get_index() > back.get_index(): return
	_front_root = front
	_front_parent = parent
	_front_index = front.get_index()
	parent.move_child(front, back.get_index())

func remaining() -> float:
	return maxf(0.0, duration - elapsed) if active else 0.0

func advance(delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		cancel()
		return
	elapsed = minf(duration, elapsed + maxf(0.0, delta))
	# Some engine/platform scalar paths round the clamped sum below duration.
	if elapsed>=duration-0.000001:elapsed=duration
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
	if _durations.is_empty():return
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

func _restore(restore_order: bool = false) -> void:
	# 2c24/2ea4 restore coordinates and state, leaving the acting-side draw
	# lists unchanged until the next action. Abandoned presentations roll back.
	if restore_order and is_instance_valid(_front_parent) and is_instance_valid(_front_root) and _front_root.get_parent() == _front_parent:
		_front_parent.move_child(_front_root, mini(_front_index, _front_parent.get_child_count() - 1))
	_front_root = null
	_front_parent = null
	_front_index = -1
	if is_instance_valid(actor):
		actor.position = home
		if actor.sprite_frames!=null and actor.sprite_frames.has_animation("idle"):actor.play("idle")

func cancel() -> void:
	if not active: return
	active = false
	cancelled = true
	_restore(true)
	# Release callers awaiting either stage. They must inspect cancelled/epoch.
	if not impacted: impact.emit()
	completed.emit()
