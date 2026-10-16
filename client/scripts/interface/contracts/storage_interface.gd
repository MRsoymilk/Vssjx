class_name PlatformStorageInterface
extends RefCounted
## Game save operations use requests, including immediate native completions.
## A write may succeed only after its declared persistence boundary completes.

func initialize() -> PlatformStorageRequest:
	return PlatformStorageRequest.resolved(PlatformResult.unsupported())

func probe(_path: String) -> PlatformStorageRequest:
	return PlatformStorageRequest.resolved(PlatformResult.unsupported())

func read(_path: String, _maximum_bytes: int = 1048576) -> PlatformStorageRequest:
	return PlatformStorageRequest.resolved(PlatformResult.unsupported())

func write(_path: String, _text: String) -> PlatformStorageRequest:
	return PlatformStorageRequest.resolved(PlatformResult.unsupported())

## Native address preferences / native regression compatibility only.
## Web must not implement these by reporting an in-memory write as durable.

func exists(_path: String) -> bool:
	return false

func read_text(_path: String, _maximum_bytes: int = 1048576) -> PlatformResult:
	return PlatformResult.unsupported()

func write_text_atomic(_path: String, _text: String) -> PlatformResult:
	return PlatformResult.unsupported()
