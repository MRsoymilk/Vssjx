extends "res://scripts/interface/adapters/native/native_system_actions.gd"
var requests := 0
var blocked := false

func request_exit() -> PlatformResult:
	return PlatformResult.unsupported() if blocked else super.request_exit()

func _request_quit() -> void:
	requests += 1
