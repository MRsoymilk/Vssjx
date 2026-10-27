extends Control
## Shared local/online settings UI; never sends gameplay or account requests.

func _ready() -> void:
	GameAudio.initialize_settings()
	$Toggle.pressed.connect(_toggle_sound)
	visibility_changed.connect(_refresh)
	_refresh()

func _toggle_sound() -> void:
	GameAudio.set_sound_enabled(not GameAudio.sound_enabled)
	_refresh()

func _refresh() -> void:
	if not is_node_ready(): return
	$Toggle.text = "声音：开启（点击关闭）" if GameAudio.sound_enabled else "声音：关闭（点击开启）"
	$Status.text = "背景音乐与音效同时开关。" if GameAudio.settings_error.is_empty() else "当前设置已生效，但未能保存。\n重启后可能恢复，请检查存储权限。"
	$Status.tooltip_text = GameAudio.settings_error
