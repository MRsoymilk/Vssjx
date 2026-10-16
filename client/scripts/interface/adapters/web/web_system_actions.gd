extends PlatformSystemActionsInterface

func request_exit() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.UNSUPPORTED, "CLOSE_TAB_MANUALLY", "浏览器不能由游戏直接关闭，请使用系统菜单保存后手动关闭页面。")
