class_name PlatformStorageRequest
extends RefCounted
## Completion means the declared operation finished, not that it was scheduled.
signal completed(result: PlatformResult)
var result: PlatformResult

func finish(value: PlatformResult) -> void:
	if result != null: return
	if value == null: value = PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_STORAGE_RESULT", "存档操作未返回有效结果。")
	result = value
	completed.emit(value)

func wait() -> PlatformResult:
	if result == null: await completed
	return result

static func resolved(value: PlatformResult) -> PlatformStorageRequest:
	var request := PlatformStorageRequest.new()
	request.finish(value)
	return request
