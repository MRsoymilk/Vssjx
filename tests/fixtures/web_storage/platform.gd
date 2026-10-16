extends Node
## Storage-only harness, never used by the game factory or game exports.
signal finished
class Context extends RefCounted:
	var storage := preload("res://scripts/interface/adapters/web/web_storage.gd").new()
	var runtime_config: PlatformRuntimeConfigInterface = preload("res://scripts/interface/adapters/web/web_runtime_config.gd").new()
var context := Context.new()
var result: PlatformResult

func _ready() -> void:
	result = await context.storage.initialize().wait()
	finished.emit()

func when_ready() -> PlatformResult:
	if result == null: await finished
	return result

func is_available() -> bool:
	return result != null and result.ok
