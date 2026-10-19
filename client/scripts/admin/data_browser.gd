extends Control
## Standalone project-data workbench. No editing, network calls or save loading.

const CATALOG := preload("res://scripts/admin/data_catalog.gd")
const LAYOUT := preload("res://scripts/admin/admin_window_layout.gd")
const DESKTOP_SIZE := Vector2i(960, 640)
var catalog := CATALOG.new()
var category := "weapons"
var current: Dictionary = {}
var configure_window := true
var visible_entries: Array[Dictionary] = []

func _ready() -> void:
	if configure_window:
		LAYOUT.configure_scene(self, "蜀山剑侠 · 项目数据管理", DESKTOP_SIZE)
	_apply_theme()
	resized.connect(_update_preview_height)
	%Fields.get_parent().set_tab_title(0, "字段详情")
	%Raw.get_parent().set_tab_title(1, "原始数据")
	%Texts.get_parent().set_tab_title(2, "文本摘录")
	%Records.set_column_title(0, "名称 / 标识")
	%Records.set_column_title(1, "状态")
	%Records.set_column_expand(1, false)
	%Records.set_column_custom_minimum_width(1, 76)
	%Fields.set_column_title(0, "字段")
	%Fields.set_column_title(1, "值")
	%Fields.set_column_expand_ratio(0, 2)
	%Fields.set_column_expand_ratio(1, 3)
	%Fields.add_theme_constant_override("v_separation", 4)
	%Categories.item_selected.connect(_category_selected)
	%Search.text_changed.connect(func(_text: String) -> void: _fill_list())
	%StatusFilter.item_selected.connect(func(_index: int) -> void: _fill_list())
	%EquipmentSlotFilter.item_selected.connect(func(_index: int) -> void: _fill_list())
	for index in ShopRules.SLOTS.size():
		%EquipmentSlotFilter.set_item_metadata(index + 1, ShopRules.SLOTS[index])
	%Records.item_selected.connect(_record_selected)
	%Refresh.pressed.connect(reload_data)
	%Copy.pressed.connect(func() -> void:
		if not current.is_empty():
			DisplayServer.clipboard_set(JSON.stringify(current.data, "  "))
			%Footer.text = "已复制当前条目数据 · " + String(current.id)
	)
	%Animations.item_selected.connect(_select_animation)
	%Replay.pressed.connect(func() -> void:
		if %Animations.item_count > 0: _select_animation(%Animations.selected)
	)
	%RawAnimations.toggled.connect(func(_value: bool) -> void: _fill_animations())
	%Collision.toggled.connect(func(value: bool) -> void: %Preview.show_blocked = value; %Preview.queue_redraw())
	reload_data()

func _apply_theme() -> void:
	var design := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	design.default_font = font
	design.default_font_size = 14
	for type in ["Label", "Button", "LineEdit", "Tree", "ItemList", "CheckBox", "CodeEdit", "TabContainer"]:
		design.set_color("font_color", type, Color("dbe7ef"))
		design.set_color("font_selected_color", type, Color("ffffff"))
	design.set_color("font_uneditable_color", "LineEdit", Color("9bb3c2"))
	for type in ["LineEdit", "Tree", "ItemList", "CodeEdit"]:
		design.set_stylebox("normal" if type == "LineEdit" else "panel", type, _box("101923", "293b4a", 8))
		design.set_color("selection_color", type, Color("254c61"))
		design.set_color("font_placeholder_color", type, Color("7e95a6"))
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus"]:
			design.set_stylebox(state, type, _box("243948" if state in ["hover", "pressed"] else "1a2a37", "4cbda3" if state == "focus" else "344c5c", 7))
	for state in ["tab_selected", "tab_hovered", "tab_unselected"]:
		design.set_stylebox(state, "TabContainer", _box("243948" if state == "tab_selected" else "15222e", "293b4a", 5))
	design.set_stylebox("panel", "TabContainer", _box("101923", "293b4a", 7))
	design.set_stylebox("selected", "ItemList", _box("23483f", "4cbda3", 6))
	design.set_stylebox("selected_focus", "ItemList", _box("23483f", "4cbda3", 6))
	design.set_stylebox("selected", "Tree", _box("254c61", "375d72", 4))
	design.set_stylebox("selected_focus", "Tree", _box("254c61", "4cbda3", 4))
	design.set_constant("v_separation", "Tree", 6)
	design.set_constant("v_separation", "ItemList", 9)
	design.set_constant("h_separation", "ItemList", 12)
	theme = design
	add_theme_stylebox_override("panel", _box("15222e", "293b4a", 0))
	%NavPanel.add_theme_stylebox_override("panel", _box("101923", "293b4a", 10))
	%Inspector.add_theme_stylebox_override("panel", _box("1a2a37", "293b4a", 10))

func _box(fill: String, border: String, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.border_color = Color(border)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func reload_data() -> void:
	var selected_id := String(current.get("id", ""))
	catalog.reload()
	%Categories.clear()
	for item in CATALOG.CATEGORIES:
		var count: int = catalog.find(item[0]).size()
		%Categories.add_item("%s    %d" % [item[1], count])
		%Categories.set_item_metadata(%Categories.item_count - 1, item[0])
		if item[0] == category: %Categories.select(%Categories.item_count - 1)
	%Total.text = "原包物品 %d 件 · 地图目录 %d 条 · %d 条索引" % [catalog.find("items", "", "原包资源").size(), catalog.original_map_names, catalog.entries.size()]
	_fill_list(selected_id)

func select_category(id: String) -> void:
	for index in %Categories.item_count:
		if %Categories.get_item_metadata(index) == id:
			%Categories.select(index)
			_category_selected(index)
			return

func _category_selected(index: int) -> void:
	category = %Categories.get_item_metadata(index)
	%Search.text = ""
	%StatusFilter.select(0)
	%EquipmentSlotFilter.select(0)
	_fill_list()

func _fill_list(preferred_id: String = "") -> void:
	for item in CATALOG.CATEGORIES:
		if item[0] == category: %Section.text = item[1]
	%Context.visible = category in ["appearance", "maps", "quests", "enemies", "effects", "archive"]
	if category == "appearance":
		%Context.text = "武器、衣服和帽子参与换装，其余槽位仅影响属性。可切换职业、性别和动作对照；衣帽对应为现行重建规则，具体部件与依据见字段详情。"
	elif category == "maps":
		%Context.text = "原包目录 %d 条（%d 个不同名称）；总图 %d 个位置 / %d 条连线已恢复。原版场景布局仍缺失；另有 %d 张AI生成场景，可用状态筛选查看。" % [catalog.original_map_names, catalog.original_distinct_map_names, int(catalog.original_overview.get("visible_location_count", 0)), int(catalog.original_overview.get("route_count", 0)), catalog.find("maps", "", "AI生成").size()]
	elif category == "quests":
		var stages: int = catalog.find("quests", "", "重建阶段").size()
		var ai_count: int = catalog.find("quests", "", "AI生成").size()
		%Context.text = "试炼：1 条任务链 / %d 阶段；AI生成：%d 个任务；原包：%d 组文案与引导线索。AI内容不是原版恢复。" % [stages, ai_count, catalog.find("quests").size() - stages - ai_count]
	elif category == "enemies":
		%Context.text = "已接入 %d 条重建定义；原包 %d 份怪物动画。素材条目不等于怪物种类，原版名称、等级与属性尚未恢复。" % [catalog.find("enemies", "", "已接入").size(), catalog.find("enemies", "", "原包资源").size()]
	elif category == "effects":
		%Context.text = "原包 %d 份特效动画，按原始序列播放；名称和技能对应关系尚未恢复，不等同于已接入技能。" % catalog.find("effects").size()
	elif category == "archive":
		%Context.text = "全部 %d 条：已解析 %d · 部分解析 %d · 未解析 %d · 解析失败 %d。只要有原始条目就保留，不因不能预览而省略。" % [catalog.find("archive").size(), catalog.find("archive", "", "已解析").size(), catalog.find("archive", "", "部分解析").size(), catalog.find("archive", "", "未解析").size(), catalog.find("archive", "", "解析失败").size()]
	%EquipmentSlotFilter.visible = category in ["equipment", "appearance", "weapons", "items"]
	var slot := ""
	if %EquipmentSlotFilter.visible and %EquipmentSlotFilter.selected > 0:
		slot = %EquipmentSlotFilter.get_item_metadata(%EquipmentSlotFilter.selected)
	visible_entries = catalog.find(category, %Search.text, %StatusFilter.get_item_text(%StatusFilter.selected), slot)
	%Count.text = "%d / %d 条" % [visible_entries.size(), catalog.find(category).size()]
	%Records.clear()
	var root: TreeItem = %Records.create_item()
	var selected: TreeItem
	for entry in visible_entries:
		var row: TreeItem = %Records.create_item(root)
		row.set_text(0, entry.name + "\n" + entry.id)
		row.set_text(1, entry.status)
		if entry.preview.get("kind") == "icon":
			row.set_icon(0, load(entry.preview.path))
			row.set_icon_max_width(0, 36)
		row.set_custom_color(1, Color("83dfbd") if entry.status == "已接入" else Color("dbbb78"))
		row.set_tooltip_text(0, entry.summary)
		row.set_metadata(0, entry)
		if selected == null or entry.id == preferred_id: selected = row
	%Empty.visible = visible_entries.is_empty()
	%Records.visible = not visible_entries.is_empty()
	if selected != null:
		selected.select(0)
		# select emits item_selected; call explicitly for non-interactive refresh too.
		_show_entry(selected.get_metadata(0))
	else:
		_show_entry({})
	%Footer.text = "只读浏览 · 本地项目定义 · 不连接数据库或读取玩家存档" if catalog.errors.is_empty() else "数据加载异常：" + "；".join(catalog.errors)

func _record_selected() -> void:
	var row: TreeItem = %Records.get_selected()
	if row != null: _show_entry(row.get_metadata(0))

func _show_entry(entry: Dictionary) -> void:
	current = entry
	%Fields.clear()
	%Raw.text = ""
	%Texts.text = ""
	%Animations.clear()
	%RawAnimations.set_pressed_no_signal(false)
	%RawAnimations.visible = false
	%AnimationHelp.text = ""
	%AnimationHelp.visible = false
	var equipment := ShopRules.item(entry.get("preview", {}).get("equipment_id", ""))
	%AppearanceComparison.set_equipment(equipment)
	%Preview.visible = equipment.is_empty()
	%Preview.display(entry if equipment.is_empty() else {})
	%Copy.disabled = entry.is_empty()
	%DetailTitle.text = entry.get("name", "未选择条目")
	%Summary.text = entry.get("summary", "当前分类没有匹配结果，请调整搜索或筛选条件。")
	%Source.text = entry.get("source", "")
	%AnimationBar.visible = entry.get("preview", {}).get("kind") in ["actor", "original_animation", "image_frames"]
	%Collision.visible = entry.get("preview", {}).get("kind") == "map"
	var preview_kind: String = entry.get("preview", {}).get("kind", "")
	%AudioPreview.display(entry)
	if preview_kind=="audio":%Preview.hide()
	%PreviewMessage.visible = preview_kind == "unavailable"
	%PreviewMessage.text = entry.get("preview", {}).get("message", "")
	_update_preview_height()
	var excerpts: Array = entry.get("data", {}).get("文本摘录", [])
	var was_reading_text: bool = %Texts.get_parent().current_tab == 2
	%Texts.get_parent().set_tab_hidden(2, excerpts.is_empty())
	if not excerpts.is_empty():
		%Texts.text = "\n\n".join(excerpts)
		%Texts.get_parent().current_tab = 2
	elif was_reading_text:
		%Texts.get_parent().current_tab = 0
	if entry.is_empty(): return
	var root: TreeItem = %Fields.create_item()
	_append_fields(root, entry.data)
	%Raw.text = JSON.stringify(entry.data, "  ")
	_fill_animations()

func _fill_animations() -> void:
	var previous := String(%Preview.sprite.animation) if is_instance_valid(%Preview.sprite) else ""
	%Animations.clear()
	var all_options: Array[Dictionary] = %Preview.animation_options(true)
	var known := 0
	var raw := 0
	for option in all_options:
		if option.id.begins_with("source_"): raw += 1
		elif not option.id.begins_with("frame_"): known += 1
	%RawAnimations.visible = known > 0 and raw > 0
	%RawAnimations.text = "显示原始序列（%d）" % raw
	var options: Array[Dictionary] = %Preview.animation_options(%RawAnimations.button_pressed)
	var selected := 0
	for option in options:
		%Animations.add_item(option.label)
		var index: int = %Animations.item_count - 1
		%Animations.set_item_metadata(index, option.id)
		%Animations.get_popup().set_item_tooltip(index, option.description)
		if option.id == previous: selected = index
	%AnimationHelp.visible = not options.is_empty()
	if not options.is_empty():
		%Animations.select(selected)
		_select_animation(selected)

func _select_animation(index: int) -> void:
	if index < 0 or index >= %Animations.item_count: return
	%Preview.play_animation(String(%Animations.get_item_metadata(index)))
	%AnimationHelp.text = %Animations.get_popup().get_item_tooltip(index)
	%AnimationHelp.tooltip_text = %AnimationHelp.text

func _update_preview_height() -> void:
	var minimum := 120.0 if current.get("preview", {}).get("kind") == "unavailable" else 96.0
	%Preview.custom_minimum_size.y = clampf(minimum + (get_viewport_rect().size.y - 540.0) * 0.35, minimum, 240.0)

func _append_fields(parent: TreeItem, data: Dictionary) -> void:
	for key in data:
		var row: TreeItem = %Fields.create_item(parent)
		row.set_text(0, String(key))
		var value: Variant = data[key]
		if value is Dictionary:
			row.set_text(1, "%d 个字段" % value.size())
			_append_fields(row, value)
		elif value is Array and value.size() > 12:
			row.set_text(1, "%d 项 · 完整内容见原始数据" % value.size())
		else:
			var text := JSON.stringify(value) if value is Array else ("—" if value == null else str(value))
			row.set_text(1, text)
			row.set_tooltip_text(1, text)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			reload_data()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and (event.ctrl_pressed or event.meta_pressed):
			%Search.grab_focus()
			get_viewport().set_input_as_handled()
