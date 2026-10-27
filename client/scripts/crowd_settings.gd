extends Control

func _ready() -> void:
	WorldDisplaySettings.initialize()
	$Toggle.pressed.connect(func() -> void:
		WorldDisplaySettings.set_mode(WorldDisplaySettings.MODES[(WorldDisplaySettings.MODES.find(WorldDisplaySettings.mode) + 1) % 3])
		_refresh()
	)
	visibility_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not is_node_ready(): return
	$Toggle.text = "其他玩家：%s（点击切换）" % WorldDisplaySettings.LABELS[WorldDisplaySettings.MODES.find(WorldDisplaySettings.mode)]
	$Status.text = "始终显示自己、队友、NPC和怪物。" if WorldDisplaySettings.last_error.is_empty() else "本次已生效，但未能保存。\n重启后可能恢复，请检查存储权限。"
	$Status.tooltip_text = WorldDisplaySettings.last_error
