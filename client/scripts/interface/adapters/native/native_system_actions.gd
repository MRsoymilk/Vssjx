extends PlatformSystemActionsInterface

func request_exit() -> PlatformResult:
	if not is_inside_tree():
		return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "PLATFORM_NOT_READY", "平台尚未就绪，暂时无法退出。")
	_request_quit()
	return PlatformResult.success()

func _request_quit() -> void:
	get_tree().quit()
