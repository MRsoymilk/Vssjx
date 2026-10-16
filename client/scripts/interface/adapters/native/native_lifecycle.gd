extends PlatformLifecycleInterface

func _ready() -> void:
	if DisplayServer.get_name() != "headless": focused = get_tree().root.has_focus()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if not focused: return
			focused = false
			changed.emit("focus_lost")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			if focused: return
			focused = true
			changed.emit("focus_gained")
		NOTIFICATION_APPLICATION_PAUSED:
			if suspended: return
			suspended = true
			changed.emit("suspended")
		NOTIFICATION_APPLICATION_RESUMED:
			if not suspended: return
			suspended = false
			changed.emit("resumed")
