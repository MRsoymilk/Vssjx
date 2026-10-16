class_name PlatformResourceRequest
extends RefCounted
## Pollable async operation: no scene callbacks are retained by the loader.
## Cancellation stops this consumer, not necessarily the engine's IO task.

static var _next_id := 0
var _id: int
var _generation: int
var _owner: WeakRef
var _progress := 0.0
var _result: PlatformResult
var _paths := PackedStringArray()
var _prepared: Dictionary = {}
var _type_hint: String
var _deadline_msec: int

var request_id: int:
	get: return _id
var generation: int:
	get: return _generation
var progress: float:
	get: return _progress
var result: PlatformResult:
	get: return _result

func _init(owner: Node, caller_generation: int) -> void:
	_next_id += 1
	_id = _next_id
	_generation = caller_generation
	if is_instance_valid(owner): _owner = weakref(owner)

func is_finished() -> bool:
	return _result != null

func cancel() -> void:
	_complete(PlatformResult.new(PlatformResult.Status.CANCELLED, "CANCELLED", "资源准备已取消。"))

func _owner_available() -> bool:
	var owner: Node = _owner.get_ref() if _owner != null else null
	return is_instance_valid(owner) and owner.is_inside_tree() and not owner.is_queued_for_deletion()

func _set_progress(amount: float) -> void:
	if not is_finished() and is_finite(amount): _progress = maxf(_progress, clampf(amount, 0.0, 0.999))

func _complete(outcome: PlatformResult) -> void:
	if is_finished(): return
	_result = outcome
	if outcome.ok: _progress = 1.0
	_prepared.clear()
