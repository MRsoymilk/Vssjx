extends PanelContainer

const LAYOUT := preload("res://scripts/admin/admin_window_layout.gd")
const CATALOG := preload("res://scripts/admin/data_catalog.gd")
const MINIMUM_CANVAS := LAYOUT.DESKTOP_SIZE

func _ready() -> void:
	var window := get_window()
	if window == get_tree().root:
		LAYOUT.configure_scene(self, "蜀山剑侠Online · 原版世界总图")
		var catalog := CATALOG.new()
		catalog.reload()
		var maps: Array[Dictionary] = catalog.find("maps", "", "原包目录")
		if not maps.is_empty(): display(maps[0])
	else:
		LAYOUT.adapt(window, MINIMUM_CANVAS)

func display(entry: Dictionary) -> void:
	%WorldPreview.display(entry)
	%Selection.text = "当前：%s · 原包编号 %d%s" % [entry.name, int(entry.preview.selected_map_id), "（原包未提供总图位置）" if entry.data["世界总图坐标（列x、行y）"] == null else ""]
