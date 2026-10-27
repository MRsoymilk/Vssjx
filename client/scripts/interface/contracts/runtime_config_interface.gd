class_name PlatformRuntimeConfigInterface
extends RefCounted
## Only named public client settings, never the server's .env or credentials.

func local_path(_kind: String, _explicit_path: String = "") -> PlatformResult:
	return PlatformResult.unsupported()

## Fixed Web endpoints bypass saved/native address preferences entirely.
func connection_options() -> PlatformResult:
	return PlatformResult.unsupported()

func check_network_target(_address: String) -> PlatformResult:
	return PlatformResult.unsupported()

func allows_remembered_login() -> bool:
	return false

## Non-secret device preference, independent of player saves and network targets.
func load_sound_enabled() -> PlatformResult:
	return PlatformResult.unsupported()

func save_sound_enabled(_enabled: bool) -> PlatformResult:
	return PlatformResult.unsupported()

func load_player_display() -> PlatformResult:
	return PlatformResult.unsupported()

func save_player_display(_mode: String) -> PlatformResult:
	return PlatformResult.unsupported()
