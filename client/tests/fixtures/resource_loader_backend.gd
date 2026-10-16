extends "res://scripts/interface/adapters/native/native_resource_loader.gd"
## Deterministic IO/clock faults; never changes native production behavior.

var files: Dictionary = {}
var cached: Dictionary = {}
var statuses: Dictionary = {}
var amounts: Dictionary = {}
var starts: Dictionary = {}
var gets: Dictionary = {}
var start_error: Error = OK
var clock := 0

func _resource_exists(path: String) -> bool:
	return files.has(path)

func _cached_resource(path: String) -> Resource:
	return cached.get(path)

func _thread_status(path: String, progress: Array) -> int:
	progress.append(amounts.get(path, 0.0))
	return statuses.get(path, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)

func _thread_request(path: String) -> Error:
	starts[path] = starts.get(path, 0) + 1
	if start_error != OK: return start_error
	statuses[path] = ResourceLoader.THREAD_LOAD_IN_PROGRESS
	return OK

func _thread_get(path: String) -> Resource:
	gets[path] = gets.get(path, 0) + 1
	statuses.erase(path)
	cached[path] = files[path]
	return files[path]

func _now_msec() -> int:
	return clock
