class_name OriginalInventory
extends Control
## Backpack reference: ten equipment positions, six columns, four visible rows.

signal back_requested
signal changed
const EQUIPMENT := ["武器", "腰佩", "衣服", "手腕", "腰带", "裤子", "鞋子", "戒指", "项链", "帽子"]
const WINDOW := Rect2(36, 63, 248, 353)
var palette: Dictionary
var header: Label
var preview: AnimatedSprite2D
var grid: Control
var cells: Array[Button] = []
var scrollbar: VScrollBar
var offset := 0
var selected_index := 0
var selected_equipment := false
var items: Array[Dictionary] = []
var description: Label
var tooltip: Panel
var tooltip_label: Label
var cursor: TextureRect
var item_menu: Panel
var equipment_icon: TextureRect
var equipment_level: OriginalNumber
var money: OriginalNumber
var hp_bar: ProgressBar
var mp_bar: ProgressBar

func _ready() -> void:
	size = Vector2(320, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	palette = OriginalUITheme.palette("bag")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimHei", "Microsoft YaHei", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var skin := Theme.new()
	skin.default_font = font
	skin.default_font_size = 11
	theme = skin
	_box(WINDOW, palette.body, Color("77521a"), 2)
	_box(Rect2(38, 65, 244, 349), palette.body, Color("f5d963"), 1)
	_box(Rect2(40, 68, 240, 28), palette.main, Color("e7e8b7"), 1)
	_picture("create_header_end", Rect2(41, 69, 11, 26))
	_picture("create_header_end", Rect2(268, 69, 11, 26), true)
	header = _text("", Rect2(69, 73, 183, 19), 14, Color("f8e12f"), true)
	for corner in [Vector2(35, 62), Vector2(277, 62), Vector2(35, 409), Vector2(277, 409)]:
		var picture := _picture("bag_corner", Rect2(corner, Vector2(8, 8)), corner.x > 100)
		picture.flip_v = corner.y > 100
	_box(Rect2(43, 103, 72, 101), Color("c3e440"), palette.deep, 1)
	var level := _text("LV.%d" % int(Game.player.level), Rect2(46, 106, 64, 14), 9, Color("fffbe1"))
	level.add_theme_color_override("font_outline_color", Color("27322c"))
	level.add_theme_constant_override("outline_size", 1)
	preview = OriginalArt.actor(Game.actor_key())
	preview.position = Vector2(80, 185)
	preview.scale = Vector2(1.3, 1.3)
	add_child(preview)
	hp_bar = OriginalSceneChrome.progress(self, Rect2(46, 190, 65, 5), Color("cced18"))
	mp_bar = OriginalSceneChrome.progress(self, Rect2(46, 196, 65, 5), Color("38d8ee"))
	for i in 10:
		var x := 118 + i % 5 * 32
		var y := 103 + (i / 5) * 51
		_box(Rect2(x, y, 32, 49), palette.body, palette.main, 1)
		_box(Rect2(x, y, 32, 15), palette.main, palette.main, 0)
		_text(EQUIPMENT[i], Rect2(x, y, 32, 16), 11, palette.bright, true)
		if i == 0:
			equipment_icon = _picture("bag_sword", Rect2(x + 3, y + 17, 26, 29))
			equipment_level = OriginalNumber.new()
			equipment_level.color_set = "green"
			equipment_level.value = "1"
			equipment_level.position = Vector2(x + 1, y + 16)
			equipment_level.size = Vector2(10, 9)
			add_child(equipment_level)
		var slot := _button("", Rect2(x, y + 16, 32, 33), false)
		slot.pressed.connect(_select_equipment.bind(i))
	_box(Rect2(42, 209, 238, 151), palette.body, palette.main, 1)
	grid = Control.new()
	grid.position = Vector2(44, 211)
	grid.size = Vector2(221, 148)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scrollbar.value += 6 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -6
			grid.accept_event()
	)
	add_child(grid)
	scrollbar = VScrollBar.new()
	scrollbar.min_value = 0
	scrollbar.max_value = 60
	scrollbar.page = 24
	scrollbar.step = 6
	scrollbar.focus_mode = Control.FOCUS_NONE
	var rail := _style(Color("716529"), palette.main, 1)
	var thumb := _style(Color("e9ef28"), Color("c8d925"), 0)
	scrollbar.add_theme_stylebox_override("scroll", rail)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]: scrollbar.add_theme_stylebox_override(state, thumb)
	scrollbar.value_changed.connect(func(value: float) -> void: offset = roundi(value / 6.0) * 6; _render_grid())
	add_child(scrollbar)
	scrollbar.position = Vector2(269, 211)
	scrollbar.size = Vector2(8, 148)
	_box(Rect2(43, 364, 193, 24), Color("dfef50"), palette.edge, 1)
	description = _text("", Rect2(46, 367, 187, 19), 11, Color("71601c"))
	description.clip_text = true
	var sort := _button("整理", Rect2(239, 364, 40, 24), true)
	sort.add_theme_color_override("font_color", Color("654518"))
	sort.pressed.connect(sort_items)
	var menu := _button("菜单", Rect2(41, 391, 34, 21), true)
	menu.pressed.connect(open_menu)
	_picture("attribute_coin", Rect2(102, 395, 9, 11))
	_box(Rect2(118, 392, 110, 19), palette.main, palette.main, 0)
	money = OriginalNumber.new()
	money.position = Vector2(121, 395)
	money.size = Vector2(103, 12)
	add_child(money)
	var back := _button("返回", Rect2(245, 391, 34, 21), true)
	back.pressed.connect(func() -> void: back_requested.emit())
	cursor = _picture("create_cursor", Rect2(70, 235, 14, 14))
	tooltip = _box(Rect2(46, 249, 141, 41), Color("ffdb6d"), Color("765322"), 1)
	tooltip_label = _text("", Rect2(5, 4, 132, 35), 12, Color("ad621f"), false, tooltip)
	tooltip.hide()
	refresh()

func refresh() -> void:
	items = Game.bag_items()
	header.text = "背包(%d/60)" % items.size()
	money.value = str(int(Game.player.gold))
	money.queue_redraw()
	var values := Game.stats()
	hp_bar.max_value = values.hp
	hp_bar.value = int(Game.player.hp)
	mp_bar.max_value = values.mp
	mp_bar.value = int(Game.player.mp)
	equipment_icon.visible = bool(Game.player.equipped)
	equipment_level.visible = bool(Game.player.equipped)
	scrollbar.max_value = maxi(60, items.size())
	_render_grid()
	_description()

func _render_grid() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	cells.clear()
	for i in 24:
		var index := offset + i
		var rect := Rect2(i % 6 * 37, (i / 6) * 37, 34, 35)
		var fill: Color = palette.slot
		var chosen := index == selected_index and not selected_equipment and index < items.size()
		var panel := _box(rect, fill, Color("d8e630") if chosen else palette.main, 2 if chosen else 1, grid)
		if index < items.size():
			var item: Dictionary = items[index]
			var icon := TextureRect.new()
			icon.texture = load(String(item.icon))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(icon)
			icon.position = Vector2(2, 1)
			icon.size = Vector2(30, 31)
			var count := OriginalNumber.new()
			count.value = str(int(item.count))
			count.position = Vector2(14, 25)
			count.size = Vector2(19, 9)
			panel.add_child(count)
		var button := _button("", rect, false, grid)
		button.pressed.connect(func() -> void: close_menu(); select_item(index); open_menu())
		button.mouse_entered.connect(func() -> void: select_item(index, true))
		button.mouse_exited.connect(func() -> void: tooltip.hide())
		cells.append(button)
	cursor.visible = not selected_equipment and selected_index >= offset and selected_index < offset + 24 and selected_index < items.size()
	if cursor.visible:
		var local := selected_index - offset
		cursor.position = grid.position + Vector2(local % 6 * 37 + 23, (local / 6) * 37 + 24)

func select_item(index: int, hover: bool = false) -> void:
	if hover and item_menu != null: return
	selected_equipment = false
	selected_index = clampi(index, 0, maxi(59, items.size() - 1))
	# Updating only the styles avoids replacing a button while its mouse
	# enter/exit signals are being dispatched.
	for i in cells.size():
		var slot: Panel = grid.get_child(i * 2)
		var chosen := offset + i == selected_index and selected_index < items.size()
		slot.add_theme_stylebox_override("panel", _style(palette.slot, Color("d8e630") if chosen else palette.main, 2 if chosen else 1))
	var local := selected_index - offset
	cursor.visible = local >= 0 and local < 24 and selected_index < items.size()
	cursor.position = grid.position + Vector2(posmod(local, 6) * 37 + 23, floori(local / 6.0) * 37 + 24)
	_description()
	if hover and selected_index < items.size():
		tooltip.position = Vector2(clampf(cursor.position.x - 18, 44, 139), clampf(cursor.position.y + 8, 212, 318))
		tooltip_label.text = "%s\n等级：%d" % [items[selected_index].name, int(items[selected_index].level)]
		tooltip.show()
		move_child(tooltip, get_child_count() - 1)
	else: tooltip.hide()

func _select_equipment(index: int) -> void:
	if index != 0 or not Game.player.equipped: return
	selected_equipment = true
	cursor.hide()
	tooltip.hide()
	_description()
	open_menu()

func _selected() -> Dictionary:
	if selected_equipment and Game.player.equipped:
		return {"id": "sword", "name": "青锋剑", "count": 1, "level": 1}
	if selected_index >= 0 and selected_index < items.size(): return items[selected_index]
	return {}

func _description() -> void:
	var item := _selected()
	description.text = "" if item.is_empty() else "%s  ×%d" % [item.name, int(item.count)]

func open_menu() -> void:
	if item_menu != null and is_instance_valid(item_menu): close_menu(); return
	tooltip.hide()
	item_menu = _box(Rect2(85, 246, 150, 140), Color("fff2af"), Color("765322"), 1)
	item_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var item := _selected()
	var actions: Array[Dictionary] = []
	if not item.is_empty():
		actions.append({"name": "查看", "call": show_item})
		if item.id == "potion": actions.append({"name": "使用", "call": use_item})
		else: actions.append({"name": "卸下" if Game.player.equipped else "装备", "call": equip_item})
		actions.append({"name": "丢弃", "call": confirm_discard})
	actions.append({"name": "整理背包", "call": sort_items})
	actions.append({"name": "购药 · 8 铜钱", "call": buy_potion})
	for i in actions.size():
		var button := _button(String(actions[i].name), Rect2(3, 3 + i * 26, 144, 25), false, item_menu)
		button.add_theme_color_override("font_color", Color("705321"))
		button.pressed.connect(actions[i].call)
		if button.text == "使用": button.disabled = int(Game.player.hp) >= int(Game.stats().hp)
		if button.text.begins_with("购药"): button.disabled = int(Game.player.gold) < 8
	item_menu.size.y = 6 + actions.size() * 26

func close_menu() -> void:
	if item_menu != null and is_instance_valid(item_menu):
		remove_child(item_menu)
		item_menu.queue_free()
	item_menu = null

func show_item() -> void:
	close_menu()
	var item := _selected()
	if item.is_empty(): return
	tooltip.position = Vector2(61, 284)
	tooltip_label.text = "%s  等级：1\n%s" % [item.name, "恢复45点气血" if item.id == "potion" else "装备后攻击+5"]
	tooltip.show()
	move_child(tooltip, get_child_count() - 1)

func use_item() -> void:
	if _selected().get("id", "") != "potion" or int(Game.player.potions) < 1 or int(Game.player.hp) >= int(Game.stats().hp): return
	Game.player.potions = int(Game.player.potions) - 1
	Game.player.hp = mini(int(Game.stats().hp), int(Game.player.hp) + 45)
	_save_refresh()

func equip_item() -> void:
	if _selected().get("id", "") != "sword" or not Game.player.get("weapon_owned", true): return
	if Game.player.equipped and items.size() >= 60:
		description.text = "背包已满"
		close_menu()
		return
	Game.player.equipped = not Game.player.equipped
	selected_equipment = bool(Game.player.equipped)
	_save_refresh()

func buy_potion() -> void:
	if not Game.bag_buy_potion(): description.text = "铜币不足或背包已满"; close_menu(); return
	_save_refresh()

func sort_items() -> void:
	Game.player.bag_order = ["sword", "potion"]
	selected_equipment = false
	selected_index = 0
	scrollbar.value = 0
	_save_refresh()
	description.text = "整理完毕"

func confirm_discard() -> void:
	var item := _selected().duplicate()
	if item.is_empty(): return
	close_menu()
	item_menu = _box(Rect2(65, 264, 191, 89), Color("fff2af"), Color("765322"), 1)
	item_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_text("确定丢弃“%s”？" % item.name, Rect2(8, 7, 178, 37), 12, Color("705321"), false, item_menu).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var yes := _button("确定", Rect2(17, 57, 57, 23), true, item_menu)
	yes.pressed.connect(func() -> void:
		if item.id == "potion": Game.player.potions = maxi(0, int(Game.player.potions) - int(item.count))
		else: Game.player.equipped = false; Game.player.weapon_owned = false
		selected_equipment = false
		_save_refresh()
	)
	_button("取消", Rect2(113, 57, 57, 23), true, item_menu).pressed.connect(close_menu)

func _save_refresh() -> void:
	close_menu()
	tooltip.hide()
	refresh()
	if not Game.save_game(): description.text = "保存失败：" + Game.last_save_error
	changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE and item_menu != null:
		close_menu()
		get_viewport().set_input_as_handled()
		return
	var step := 0
	match event.keycode:
		KEY_LEFT: step = -1
		KEY_RIGHT: step = 1
		KEY_UP: step = -6
		KEY_DOWN: step = 6
		KEY_ENTER: open_menu(); get_viewport().set_input_as_handled(); return
	if step == 0: return
	selected_index = clampi(selected_index + step, 0, 59)
	if selected_index < offset: scrollbar.value = floori(selected_index / 6.0) * 6
	elif selected_index >= offset + 24: scrollbar.value = (floori(selected_index / 6.0) - 3) * 6
	select_item(selected_index)
	get_viewport().set_input_as_handled()

func _style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style

func _box(rect: Rect2, fill: Color, border: Color, width: int, parent: Node = null) -> Panel:
	var node := Panel.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", _style(fill, border, width))
	(parent if parent != null else self).add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

func _text(value: String, rect: Rect2, font_size: int, color: Color, centered: bool = false, parent: Node = null) -> Label:
	var node := OriginalSceneChrome.label(parent if parent != null else self, value, rect, font_size, color)
	if centered: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node

func _button(value: String, rect: Rect2, wood: bool, parent: Node = null) -> Button:
	var node := OriginalSceneChrome.button(parent if parent != null else self, value, rect, 12)
	node.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	node.add_theme_color_override("font_disabled_color", Color("b7a365"))
	if wood:
		for state in ["normal", "hover", "pressed"]: node.add_theme_stylebox_override(state, _style(Color("c59132"), Color("7f4019"), 2))
		var inner := _box(Rect2(3, 3, rect.size.x - 6, rect.size.y - 6), Color.TRANSPARENT, Color("f5dea0"), 1, node)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _picture(key: String, rect: Rect2, mirrored: bool = false) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load("res://assets/ui/%s.png" % key)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.flip_h = mirrored
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node
