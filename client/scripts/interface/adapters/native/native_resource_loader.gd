extends PlatformResourceLoaderInterface
## Share engine IO per path, but keep cancellation/deadlines/results per caller.
## Finished orphan jobs are drained without ever calling a disposed scene.

const MAX_RESOURCES := 128
var _requests: Dictionary = {}
var _tasks: Dictionary = {}

func _ready() -> void:
	set_process(false)

func prepare(paths: PackedStringArray, owner: Node, generation: int,
		type_hint: String = "Texture2D", timeout_msec: int = 15000) -> PlatformResourceRequest:
	var request := PlatformResourceRequest.new(owner, generation)
	if not is_inside_tree() or not request._owner_available():
		request.cancel()
		return request
	if paths.is_empty() or paths.size() > MAX_RESOURCES or timeout_msec < 1 or generation < 0:
		_fail(request, "INVALID_REQUEST", "资源准备请求无效。", PlatformResult.Status.INVALID_DATA)
		return request
	if not ClassDB.class_exists(type_hint) or not ClassDB.is_parent_class(type_hint, "Resource"):
		_fail(request, "INVALID_TYPE", "资源类型无效。", PlatformResult.Status.INVALID_DATA)
		return request
	request._type_hint = type_hint
	request._deadline_msec = _now_msec() + timeout_msec
	# Validate the whole manifest before scheduling any engine work.
	for path in paths:
		if not path.begins_with("res://") or path.simplify_path() != path:
			_fail(request, "INVALID_PATH", "只能准备包内资源。", PlatformResult.Status.INVALID_DATA)
			return request
		if not _resource_exists(path):
			_fail(request, "RESOURCE_MISSING", "游戏资源不存在，请检查游戏文件。")
			return request
		if not request._paths.has(path): request._paths.append(path)
	for path in request._paths: _ensure_task(path)
	_requests[request.request_id] = request
	_refresh_request(request)
	set_process(true)
	return request

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
	for request: PlatformResourceRequest in _requests.values():
		if request.is_finished(): continue
		if not request._owner_available(): request.cancel()
		elif _now_msec() >= request._deadline_msec:
			_fail(request, "RESOURCE_TIMEOUT", "资源准备超时，请重试。")
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
	for request: PlatformResourceRequest in _requests.values():
		if not request.is_finished(): _refresh_request(request)
		if request.is_finished(): _requests.erase(request.request_id)
	# Requests hold their own prepared resources; no unbounded second cache.
	for path: String in _tasks.keys():
		if _tasks[path].result != null: _tasks.erase(path)
	set_process(not _tasks.is_empty() or not _requests.is_empty())

func _refresh_request(request: PlatformResourceRequest) -> void:
	var done := 0.0
	for path in request._paths:
		if request._prepared.has(path):
			done += 1.0
			continue
		var task: Dictionary = _tasks[path]
		var outcome: PlatformResult = task.result
		if outcome == null:
			done += task.progress
		elif not outcome.ok:
			request._complete(outcome)
			return
		elif not outcome.value is Resource or not outcome.value.is_class(request._type_hint):
			_fail(request, "RESOURCE_TYPE_MISMATCH", "资源类型与请求不符。", PlatformResult.Status.INVALID_DATA)
			return
		else:
			request._prepared[path] = outcome.value
			done += 1.0
	request._set_progress(done / request._paths.size())
	if request._prepared.size() == request._paths.size():
		request._complete(PlatformResult.success(request._prepared.duplicate()))

func _exit_tree() -> void:
	for request: PlatformResourceRequest in _requests.values(): request.cancel()
	_requests.clear()
	_tasks.clear()

func _fail(request: PlatformResourceRequest, code: String, message: String,
		status: PlatformResult.Status = PlatformResult.Status.TEMPORARY_FAILURE) -> void:
	request._complete(PlatformResult.new(status, code, message))

func _load_failure() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "RESOURCE_LOAD_FAILED", "本地资源准备失败，请检查游戏文件后重试。")

# Narrow engine boundary; deterministic tests override it without real IO faults.
func _resource_exists(path: String) -> bool:
	return ResourceLoader.exists(path)

func _cached_resource(path: String) -> Resource:
	return ResourceLoader.load(path) if ResourceLoader.has_cached(path) else null

func _thread_status(path: String, progress: Array) -> int:
	return ResourceLoader.load_threaded_get_status(path, progress)

func _thread_request(path: String) -> Error:
	return ResourceLoader.load_threaded_request(path)

func _thread_get(path: String) -> Resource:
	return ResourceLoader.load_threaded_get(path)

func _now_msec() -> int:
	return Time.get_ticks_msec()
