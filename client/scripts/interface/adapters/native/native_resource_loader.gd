extends "res://scripts/interface/adapters/common/resource_queue.gd"
## Share engine IO per path, but keep cancellation/deadlines/results per caller.
## Finished orphan jobs are drained without ever calling a disposed scene.

func _ensure_task(path: String) -> void:
	if _tasks.has(path): return
	var cached := _cached_resource(path)
	var task := {"progress": 0.0, "result": null}
	_tasks[path] = task
	if cached != null:
		task.result = PlatformResult.success(cached)
		return
	var status := _thread_status(path, [])
	if status not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED] and _thread_request(path) != OK:
		task.result = PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "RESOURCE_REQUEST_FAILED", "无法启动资源准备，请重试。")

func _process(_delta: float) -> void:
	_expire_requests()
	for path: String in _tasks:
		var task: Dictionary = _tasks[path]
		if task.result != null: continue
		var amount: Array = []
		var status := _thread_status(path, amount)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := _thread_get(path)
			task.result = PlatformResult.success(resource) if resource != null else _load_failure()
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			# A different engine consumer may already have claimed its result.
			var cached := _cached_resource(path)
			task.result = PlatformResult.success(cached) if cached != null else _load_failure()
		elif not amount.is_empty() and (amount[0] is float or amount[0] is int) and is_finite(float(amount[0])):
			task.progress = maxf(task.progress, clampf(float(amount[0]), 0.0, 0.999))
	_collect_results()

func _thread_status(path: String, progress: Array) -> int:
	return ResourceLoader.load_threaded_get_status(path, progress)

func _thread_request(path: String) -> Error:
	return ResourceLoader.load_threaded_request(path)

func _thread_get(path: String) -> Resource:
	return ResourceLoader.load_threaded_get(path)
