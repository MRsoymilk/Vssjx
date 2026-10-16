class_name PlatformRuntimeConfigInterface
extends RefCounted
## Only named public client settings, never the server's .env or credentials.

func local_path(_kind: String, _explicit_path: String = "") -> PlatformResult:
	return PlatformResult.unsupported()
