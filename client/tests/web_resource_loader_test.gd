extends Node

class Queue:
	extends "res://scripts/interface/adapters/web/web_resource_loader.gd"
	var files: Dictionary = {}
	var loaded: Array[String] = []
	var clock := 0
	var load_cost := 0
	func _resource_exists(path: String) -> bool: return files.has(path)
	func _cached_resource(_path: String) -> Resource: return null
	func _now_msec() -> int: return clock
	func _load_resource(path: String) -> Resource:
		loaded.append(path)
		clock += load_cost
		return files[path]

const A := "res://%s.png" % "queue-a"
const B := "res://%s.png" % "queue-b"
var checks := 0

func check(value: bool, description: String) -> void:
	checks += 1
	assert(value, description)
	if not value: get_tree().quit(1)

func _ready() -> void:
	var loader := Queue.new()
	loader.files = {A: ImageTexture.new(), B: ImageTexture.new()}
	add_child(loader)
	var first := loader.prepare([A, B, A], self, 1)
	var shared := loader.prepare([A], self, 2)
	check(loader.loaded.is_empty() and not first.is_finished(), "Preparation returns before synchronous IO")
	loader._process(0)
	check(loader.loaded == [A] and shared.result.ok and not first.is_finished(), "One resource per frame with shared consumers")
	check(first.progress == 0.5, "Partial manifest progress")
	loader._process(0)
	check(first.result.ok and first.result.value.size() == 2 and loader.loaded == [A, B], "Complete unique manifest")
	check(loader._tasks.is_empty() and not loader.is_processing(), "No second cache/polling after completion")
	var cancelled := loader.prepare([A], self, 3)
	cancelled.cancel()
	loader._process(0)
	check(loader.loaded.size() == 2 and cancelled.result.code == "CANCELLED", "Cancelled queued loads do not execute")
	var owner := Node.new()
	add_child(owner)
	var orphan := loader.prepare([A], owner, 4)
	owner.free()
	loader._process(0)
	check(orphan.result.code == "CANCELLED" and loader.loaded.size() == 2, "Detached owner is never loaded")
	var timeout := loader.prepare([A], self, 5, "Texture2D", 10)
	var patient := loader.prepare([A], self, 6, "Texture2D", 100)
	loader.load_cost = 20
	loader._process(0)
	check(timeout.result.code == "RESOURCE_TIMEOUT" and patient.result.ok, "Blocking load cannot claim success after deadline; other consumer survives")
	loader.files[A] = Resource.new()
	var wrong := loader.prepare([A], self, 7)
	loader._process(0)
	check(wrong.result.code == "RESOURCE_TYPE_MISMATCH", "Actual resource type is validated")
	loader.files[A] = null
	var failed := loader.prepare([A], self, 8)
	loader._process(0)
	check(failed.result.code == "RESOURCE_LOAD_FAILED", "Null engine resource fails closed")
	check(loader.prepare(["user://outside.png"], self, 9).result.code == "INVALID_PATH", "Only packaged paths")
	check(loader.prepare(["res://%s.png" % "missing"], self, 10).result.code == "RESOURCE_MISSING", "Missing packaged resource")
	var pending := loader.prepare([B], self, 11)
	loader.free()
	check(pending.result.code == "CANCELLED", "Shutdown resolves pending requests")
	print("WEB RESOURCE LOADER: %d checks, 0 failures" % checks)
	get_tree().quit()
