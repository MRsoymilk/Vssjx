class_name PlatformStorageInterface
extends RefCounted
## Native calls are synchronous. Web persistence needs a separate async contract;
## do not substitute an in-memory write for this receipt's native-file guarantee.

func exists(_path: String) -> bool:
	return false

func read_text(_path: String, _maximum_bytes: int = 1048576) -> PlatformResult:
	return PlatformResult.unsupported()

func write_text_atomic(_path: String, _text: String) -> PlatformResult:
	return PlatformResult.unsupported()
