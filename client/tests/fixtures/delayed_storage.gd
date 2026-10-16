extends PlatformStorageInterface
## Deterministic completion barrier, not browser persistence emulation.
var operations: Array[Dictionary] = []

func _enqueue(kind: String, path: String, text: String = "") -> PlatformStorageRequest:
	var request := PlatformStorageRequest.new()
	operations.append({"kind": kind, "path": path, "text": text, "request": request})
	return request

func probe(path: String) -> PlatformStorageRequest:
	return _enqueue("probe", path)

func read(path: String, _maximum_bytes: int = 1048576) -> PlatformStorageRequest:
	return _enqueue("read", path)

func write(path: String, text: String) -> PlatformStorageRequest:
	return _enqueue("write", path, text)

func complete(result: PlatformResult) -> void:
	var operation: Dictionary = operations.pop_front()
	operation.request.finish(result)
