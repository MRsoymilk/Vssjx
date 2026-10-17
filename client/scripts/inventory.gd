class_name OriginalInventory
extends Control
## Backpack reference: ten equipment positions, six columns, four visible rows.

signal back_requested
signal changed
const CELL_SCENE := preload("res://scenes/ui/inventory_cell.tscn")
const EQUIPMENT := ["武器", "腰佩", "衣服", "手腕", "腰带", "裤子", "鞋子", "戒指", "项链", "帽子"]
const WINDOW := Rect2(36, 63, 248, 353)
var palette: Dictionary
var online_model: OnlinePve
var _online_sorted := false
@onready var header: Label = $Header
var preview: AnimatedSprite2D
@onready var grid: Control = $Grid
var cells: Array[Button] = []
@onready var scrollbar: VScrollBar = $Scrollbar
var offset := 0
var selected_index := 0
var selected_equipment := false
var items: Array[Dictionary] = []
@onready var description: Label = $Description
@onready var tooltip: Panel = $Tooltip
@onready var tooltip_label: Label = $Tooltip/TooltipLabel
@onready var cursor: TextureRect = $Cursor
var item_menu: Panel
@onready var equipment_icon: TextureRect = $EquipmentIcon
@onready var equipment_level: OriginalNumber = $EquipmentLevel
@onready var money: OriginalNumber = $Money
@onready var hp_bar: ProgressBar = $HpBar
@onready var mp_bar: ProgressBar = $MpBar

func _ready() -> void:
	palette = OriginalUITheme.palette("bag")
	var player := _display_player()
	$Level.text = "LV.%d" % int(player.level)
	var keys := ["mzs", "mck", "mfs"] if int(player.get("gender", 0)) == 0 else ["wzs", "wck", "wfs"]
	preview = OriginalArt.actor("hero/" + keys[int(player.job)])
	preview.position = Vector2(80, 185)
	preview.scale = Vector2(1.3, 1.3)
	add_child(preview)
	move_child(preview, hp_bar.get_index())
	for i in 10: get_node("Equipment%d" % i).pressed.connect(_select_equipment.bind(i))
	grid.gui_input.connect(_grid_input)
	scrollbar.value_changed.connect(func(value: float) -> void: offset = roundi(value / 6.0) * 6; _render_grid())
	$Sort.pressed.connect(sort_items)
	$Menu.pressed.connect(open_menu)
	$Back.pressed.connect(func() -> void: back_requested.emit())
	if online_model != null: online_model.changed.connect(_online_changed)
	refresh()

func _display_player() -> Dictionary:
	if online_model == null: return Game.player
	var character: Dictionary = online_model.state.get("character", {})
	var equipment: Dictionary = online_model.state.get("equipment", {})
	return {"job": character.get("job", 0), "gender": character.get("gender", 0), "level": character.get("level", 1),
		"gold": character.get("gold", 0), "hp": character.get("hp", 1), "mp": character.get("mp", 0),
		"potions": online_model.state.get("potions", 0), "equipped": equipment.get("weapon") == "sword",
		"weapon_owned": equipment.get("weapon_owned", false)}

func _display_stats() -> Dictionary:
	return Game.stats() if online_model == null else online_model.state.get("stats", {"hp": 1, "mp": 1})

func _display_items() -> Array[Dictionary]:
	if online_model == null: return Game.bag_items()
	var player := _display_player()
	var result: Array[Dictionary] = []
	if int(player.potions) > 0:
		result.append({"id": "potion", "name": "回春散", "count": int(player.potions), "level": 1, "icon": "res://assets/ui/bag_potion.png"})
	if player.weapon_owned and not player.equipped:
		result.append({"id": "sword", "name": "青锋剑", "count": 1, "level": 1, "icon": "res://assets/ui/bag_sword.png"})
	if _online_sorted: result.reverse()
	return result

func _online_changed() -> void:
	close_menu()
	tooltip.hide()
	refresh()
	if not online_model.ready: description.text = "连接中断，正在同步装备……"
	elif online_model.pending(): description.text = "正在确认装备操作……"
	elif not online_model.state.has("equipment"): description.text = "当前服务器尚未开放装备功能"
	elif online_model.last_action in ["equip", "unequip"] and not online_model.last_code.is_empty(): description.text = OnlinePve.error_text(online_model.last_code)

func _grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.value += 6 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -6
		grid.accept_event()

func refresh() -> void:
	var player := _display_player()
	items = _display_items()
	header.text = "背包(%d/60)" % items.size()
	money.value = str(int(player.gold))
	money.queue_redraw()
	var values := _display_stats()
	hp_bar.max_value = values.hp
	hp_bar.value = int(player.hp)
	mp_bar.max_value = values.mp
	mp_bar.value = int(player.mp)
	equipment_icon.visible = bool(player.equipped)
	equipment_level.visible = bool(player.equipped)
	if not player.equipped: selected_equipment = false
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
		var cell: Control = CELL_SCENE.instantiate()
		cell.position = Vector2(i % 6 * 37, (i / 6) * 37)
		grid.add_child(cell)
		var panel: Panel = cell.get_node("Panel")
		var chosen := index == selected_index and not selected_equipment and index < items.size()
		panel.add_theme_stylebox_override("panel", _style(palette.slot, Color("d8e630") if chosen else palette.main, 2 if chosen else 1))
		var icon: TextureRect = cell.get_node("Panel/Icon")
		var count: OriginalNumber = cell.get_node("Panel/Count")
		icon.visible = index < items.size()
		count.visible = index < items.size()
		if index < items.size():
			var item: Dictionary = items[index]
			icon.texture = load(String(item.icon))
			count.value = str(int(item.count))
			count.queue_redraw()
		var button: Button = cell.get_node("Button")
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
		var slot: Panel = grid.get_child(i).get_node("Panel")
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
	if index != 0 or not _display_player().equipped: return
	selected_equipment = true
	cursor.hide()
	tooltip.hide()
	_description()
	open_menu()

func _selected() -> Dictionary:
	if selected_equipment and _display_player().equipped:
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
		if item.id == "potion":
			if online_model == null: actions.append({"name": "使用", "call": use_item})
		else: actions.append({"name": "卸下" if _display_player().equipped else "装备", "call": equip_item})
		if online_model == null: actions.append({"name": "丢弃", "call": confirm_discard})
	actions.append({"name": "整理背包", "call": sort_items})
	if online_model == null: actions.append({"name": "购药 · 8 铜钱", "call": buy_potion})
	for i in actions.size():
		var button := _button(String(actions[i].name), Rect2(3, 3 + i * 26, 144, 25), false, item_menu)
		button.add_theme_color_override("font_color", Color("705321"))
		button.pressed.connect(actions[i].call)
		if online_model != null and button.text in ["装备", "卸下"]: button.disabled = not online_model.ready or online_model.pending() or online_model.active()
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
	if online_model != null: return
	if Game.storage_busy: return
	if _selected().get("id", "") != "potion" or int(Game.player.potions) < 1 or int(Game.player.hp) >= int(Game.stats().hp): return
	Game.player.potions = int(Game.player.potions) - 1
	Game.player.hp = mini(int(Game.stats().hp), int(Game.player.hp) + 45)
	await _save_refresh()

func equip_item() -> void:
	if online_model != null:
		if _selected().get("id", "") != "sword": return
		online_model.submit("unequip" if _display_player().equipped else "equip", "sword")
		return
	if Game.storage_busy: return
	if _selected().get("id", "") != "sword" or not Game.player.get("weapon_owned", true): return
	if Game.player.equipped and items.size() >= 60:
		description.text = "背包已满"
		close_menu()
		return
	Game.player.equipped = not Game.player.equipped
	selected_equipment = bool(Game.player.equipped)
	await _save_refresh()

func buy_potion() -> void:
	if online_model != null: return
	if Game.storage_busy: return
	if not Game.bag_buy_potion(): description.text = "铜币不足或背包已满"; close_menu(); return
	await _save_refresh()

func sort_items() -> void:
	if online_model != null:
		_online_sorted = true
		selected_index = 0
		scrollbar.value = 0
		close_menu()
		refresh()
		return
	if Game.storage_busy: return
	Game.player.bag_order = ["sword", "potion"]
	selected_equipment = false
	selected_index = 0
	scrollbar.value = 0
	if await _save_refresh(): description.text = "整理完毕"

func confirm_discard() -> void:
	if online_model != null: return
	var item := _selected().duplicate()
	if item.is_empty(): return
	close_menu()
	item_menu = _box(Rect2(65, 264, 191, 89), Color("fff2af"), Color("765322"), 1)
	item_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_text("确定丢弃“%s”？" % item.name, Rect2(8, 7, 178, 37), 12, Color("705321"), false, item_menu).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var yes := _button("确定", Rect2(17, 57, 57, 23), true, item_menu)
	yes.pressed.connect(func() -> void:
		if Game.storage_busy: return
		if item.id == "potion": Game.player.potions = maxi(0, int(Game.player.potions) - int(item.count))
		else: Game.player.equipped = false; Game.player.weapon_owned = false
		selected_equipment = false
		await _save_refresh()
	)
	_button("取消", Rect2(113, 57, 57, 23), true, item_menu).pressed.connect(close_menu)

func _save_refresh() -> bool:
	if online_model != null: return false
	close_menu()
	tooltip.hide()
	refresh()
	var result := await Game.save_game()
	if not is_inside_tree() or result.status == PlatformResult.Status.CANCELLED: return false
	if not result.ok: description.text = "保存失败：" + result.message
	changed.emit()
	return result.ok

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if Game.storage_busy: return
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
	var node: Panel = preload("res://scenes/ui/dynamic_panel.tscn").instantiate()
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
