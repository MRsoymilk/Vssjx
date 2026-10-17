class_name BattleDeathPlayback
extends RefCounted
## Original ssjx.mrp/death.ani, native sequence 0. Hold its tombstone until leaving.
signal completed
const ART_KEY := "main/death"
var actor: AnimatedSprite2D
var sprite: AnimatedSprite2D
var active := false
var cancelled := false
var duration := 0.0
var elapsed := 0.0
var _actor_visible := true
var _durations: Array[float] = []

func start(subject: AnimatedSprite2D) -> void:
	cancel()
	actor = subject
	_actor_visible = actor.visible
	cancelled = false
	elapsed = 0.0
	duration = 0.0
	_durations.clear()
	sprite = OriginalArt.actor(ART_KEY)
	sprite.name = "HeroDeath"
	actor.get_parent().add_child(sprite)
	actor.get_parent().move_child(sprite, actor.get_index() + 1)
	sprite.transform = actor.transform
	sprite.play("source_0")
	sprite.pause()
	var frames := sprite.sprite_frames
	frames.set_animation_loop("source_0", false)
	for index in frames.get_frame_count("source_0"):
		var seconds := frames.get_frame_duration("source_0", index) / frames.get_animation_speed("source_0")
		_durations.append(seconds)
		duration += seconds
	actor.hide()
	active = true
	_sample()

func remaining() -> float:
	return maxf(0.0, duration - elapsed) if active else 0.0

func advance(delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not is_instance_valid(sprite):
		cancel()
		return
	elapsed = minf(duration, elapsed + maxf(0.0, delta))
	# Engine scalar helpers may round the ten 0.1-second steps below their sum.
	if elapsed >= duration - 0.000001: elapsed = duration
	_sample()
	if elapsed >= duration:
		active = false
		completed.emit()

func _sample() -> void:
	var time := elapsed
	var step := 0
	while step < _durations.size() - 1 and time >= _durations[step]:
		time -= _durations[step]
		step += 1
	sprite.set_frame_and_progress(step, clampf(time / _durations[step], 0.0, 1.0))

func cancel() -> void:
	var was_active := active
	active = false
	cancelled = true
	if is_instance_valid(sprite):
		sprite.hide()
		sprite.queue_free()
	sprite = null
	if is_instance_valid(actor): actor.visible = _actor_visible
	actor = null
	if was_active: completed.emit()
