extends Node
## Environment facade. Must not depend on Game, OnlineAccount or game scenes.
signal initialization_finished(result: PlatformResult)

enum State { UNINITIALIZED, INITIALIZING, READY, DEGRADED, FAILED }
const FACTORY := preload("res://scripts/interface/platform_factory.gd")
var state := State.UNINITIALIZED
var context: PlatformContext
var last_result: PlatformResult

func _ready() -> void:
	initialize()

func initialize(target: String = "") -> void:
	if state != State.UNINITIALIZED: return
	state = State.INITIALIZING
	context = FACTORY.create(target)
	if context == null:
		state = State.FAILED
		last_result = PlatformResult.new(PlatformResult.Status.UNSUPPORTED, "PLATFORM_UNSUPPORTED", "此构建尚未接入当前运行平台，请使用原生客户端。")
	else:
		add_child(context.display)
		add_child(context.lifecycle)
		add_child(context.resource_loader)
		state = State.READY
		last_result = PlatformResult.success()
	initialization_finished.emit(last_result)

func is_available() -> bool:
	return state in [State.READY, State.DEGRADED]

func when_ready() -> PlatformResult:
	if state == State.UNINITIALIZED: initialize()
	if state == State.INITIALIZING: await initialization_finished
	return last_result
