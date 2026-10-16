extends "res://scripts/interface/adapters/common/resource_queue.gd"
## Single-threaded Web: at most one uncached packaged resource per frame.
## One engine load is synchronous; this is not interruptible streaming IO.
func _ensure_task(path: String) -> void:
	if _tasks.has(path): return
	var cached := _cached_resource(path)
	_tasks[path] = {"progress": 0.0, "result": PlatformResult.success(cached) if cached != null else null}

func _process(_delta: float) -> void:
	_expire_requests()
	for path: String in _tasks.keys():
		if _tasks[path].result != null: continue
		var needed := false
		for request: PlatformResourceRequest in _requests.values():
			if not request.is_finished() and request._paths.has(path): needed = true; break
		if not needed:
			_tasks.erase(path)
			continue
		var resource := _load_resource(path)
		_tasks[path].result = PlatformResult.success(resource) if resource != null else _load_failure()
		_expire_requests()
		break
	_collect_results()

func _load_resource(path: String) -> Resource:
	return ResourceLoader.load(path)
