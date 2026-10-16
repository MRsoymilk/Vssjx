class_name OriginalInventory
extends Control
## Backpack reference: ten equipment positions, six columns, four visible rows.

signal back_requested
signal changed
const CELL_SCENE := preload("res://scenes/ui/inventory_cell.tscn")
const EQUIPMENT := ["武器", "腰佩", "衣服", "手腕", "腰带", "裤子", "鞋子", "戒指", "项链", "帽子"]
const WINDOW := Rect2(36, 63, 248, 353)
var palette: Dictionary
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
	$Level.text = "LV.%d" % int(Game.player.level)
	preview = OriginalArt.actor(Game.actor_key())
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
	refresh()

func _grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scrollbar.value += 6 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -6
		grid.accept_event()

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
	if Game.storage_busy: return
	if _selected().get("id", "") != "potion" or int(Game.player.potions) < 1 or int(Game.player.hp) >= int(Game.stats().hp): return
	Game.player.potions = int(Game.player.potions) - 1
	Game.player.hp = mini(int(Game.stats().hp), int(Game.player.hp) + 45)
	await _save_refresh()

func equip_item() -> void:
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
	if Game.storage_busy: return
	if not Game.bag_buy_potion(): description.text = "铜币不足或背包已满"; close_menu(); return
	await _save_refresh()

func sort_items() -> void:
	if Game.storage_busy: return
	Game.player.bag_order = ["sword", "potion"]
	selected_equipment = false
	selected_index = 0
	scrollbar.value = 0
	if await _save_refresh(): description.text = "整理完毕"

func confirm_discard() -> void:
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
	close_menu()
	tooltip.hide()
	refresh()
	var result := await Game.save_game()
	if not is_inside_tree() or result.status == PlatformResult.Status.CANCELLED: return false
	if not result.ok: description.text = "保存失败：" + result.message
	changed.emit()
	return result.ok

func _unhandled_key_input(event: InputEvent) -> void:
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
