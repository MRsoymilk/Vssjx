class_name OriginalInventory
extends Control
## Backpack reference: ten equipment positions, six columns, four visible rows.

signal back_requested
signal changed
signal travel_requested(map_id: String)
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
var selected_slot := "weapon"
var armor_icon: TextureRect
var slot_icons: Dictionary = {}
var slot_levels: Dictionary = {}
var items: Array[Dictionary] = []
var loot_panel:Control
var material_bag:GatheringMaterialBag
var travel_picker:AIWorldPanel
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
	preview = OriginalArt.actor(ShopRules.actor_key(int(player.job),int(player.get("gender",0)),ShopRules.appearance(_gear())))
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
	for i in range(1,10):
		var button: Button = get_node("Equipment%d"%i)
		var icon := TextureRect.new()
		icon.position = button.position+Vector2(2,2)
		icon.size = button.size-Vector2(4,4)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		slot_icons[ShopRules.SLOTS[i]]=icon
		var number := OriginalNumber.new()
		number.position=button.position
		number.value="1";number.color_set="green"
		add_child(number)
		slot_levels[ShopRules.SLOTS[i]]=number
	armor_icon=slot_icons.armor
	refresh()

func _gear() -> Dictionary:
	if online_model == null: return ShopRules.local_state(Game.player)
	return online_model.state.get("shop", {"weapon":online_model.state.get("equipment",{}).get("weapon"),"armor":null,"owned":["sword"] if online_model.state.get("equipment",{}).get("weapon_owned",false) else []})

func _display_player() -> Dictionary:
	if online_model == null: return Game.player
	var character: Dictionary = online_model.state.get("character", {})
	var equipment: Dictionary = online_model.state.get("equipment", {})
	return {"job": character.get("job", 0), "gender": character.get("gender", 0), "level": character.get("level", 1),
		"gold": character.get("gold", 0), "hp": character.get("hp", 1), "mp": character.get("mp", 0),
		"potions": online_model.state.get("potions", 0), "equipped": _gear().get("weapon") != null,
		"weapon_owned": equipment.get("weapon_owned", false)}

func _display_stats() -> Dictionary:
	return Game.stats() if online_model == null else online_model.state.get("stats", {"hp": 1, "mp": 1})

func _loot()->Dictionary:
	return Game.player.get("loot_state",{}) if online_model==null else online_model.state.get("loot",{}).get("state",{})

func _slot_item(slot:String)->Dictionary:
	var instance:=LootRules.equipped(_loot(),slot)
	if not instance.is_empty() and not instance.legacy:return LootRules.bag_item(instance)
	var id:Variant=ShopRules.equipped_id(_gear(),slot)
	return {} if id==null else ShopRules.bag_item(id,int(_display_player().job))

func open_loot()->void:
	if is_instance_valid(loot_panel):return
	close_menu();tooltip.hide()
	loot_panel=load("res://scripts/loot_panel.gd").new();loot_panel.online_model=online_model
	add_child(loot_panel);set_process_unhandled_key_input(false)
	loot_panel.changed.connect(func()->void:refresh();changed.emit())
	loot_panel.back_requested.connect(func()->void:loot_panel.queue_free();loot_panel=null;set_process_unhandled_key_input(true);refresh())

func open_material_bag()->void:
	if is_instance_valid(material_bag):return
	close_menu();tooltip.hide();material_bag=GatheringMaterialBag.new();material_bag.online_model=online_model;add_child(material_bag);set_process_unhandled_key_input(false)
	material_bag.dismissed.connect(func()->void:material_bag.queue_free();material_bag=null;set_process_unhandled_key_input(true))

func _display_items() -> Array[Dictionary]:
	if online_model == null: return Game.bag_items()
	var player := _display_player()
	var result: Array[Dictionary] = []
	if int(player.potions) > 0:
		var dose:=ShopRules.bag_item("potion")
		dose.count=int(player.potions)
		result.append(dose)
	var gear := _gear()
	for id in gear.get("owned",[]):
		var on := false
		for slot in ShopRules.SLOTS:
			if ShopRules.equipped_id(gear,slot)==id: on=true
		if not on:
			var entry := ShopRules.bag_item(id,int(player.job))
			entry.count=ShopRules.quantity(gear,id)
			result.append(entry)
	for i in _loot().get("items",[]):
		if not i.legacy and not i.equipped:result.append(LootRules.bag_item(i))
	if _online_sorted: result.reverse()
	return result

func _online_changed() -> void:
	close_menu()
	tooltip.hide()
	refresh()
	if not online_model.ready: description.text = "连接中断，正在同步装备……"
	elif online_model.pending(): description.text = "正在确认装备操作……"
	elif not online_model.state.has("equipment"): description.text = "当前服务器尚未开放装备功能"
	elif online_model.last_action in ["equip", "unequip", "use", "discard"] and not online_model.last_code.is_empty(): description.text = OnlinePve.error_text(online_model.last_code)

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
	var gear := _gear()
	OriginalArt.apply_appearance(preview,ShopRules.actor_key(int(player.job),int(player.get("gender",0)),LootRules.look(_loot(),ShopRules.appearance(gear))))
	var weapon:=_slot_item("weapon")
	if not weapon.is_empty():equipment_icon.texture=load(weapon.icon)
	for slot in slot_icons:
		var entry:=_slot_item(slot)
		slot_icons[slot].visible=not entry.is_empty();slot_levels[slot].visible=not entry.is_empty()
		if not entry.is_empty():slot_icons[slot].texture=load(entry.icon);slot_levels[slot].value=str(int(entry.get("level",1)));slot_levels[slot].queue_redraw()
	equipment_icon.visible=not weapon.is_empty();equipment_level.visible=not weapon.is_empty()
	equipment_level.value=str(int(weapon.get("level",1)));equipment_level.queue_redraw()
	if _slot_item(selected_slot).is_empty(): selected_equipment = false
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
		_gourd_tooltip(items[selected_index])
		tooltip.show()
		move_child(tooltip, get_child_count() - 1)
	else: tooltip.hide()

func _select_equipment(index: int) -> void:
	if index<0 or index>=10: return
	selected_slot=ShopRules.SLOTS[index]
	if _slot_item(selected_slot).is_empty(): return
	selected_equipment = true
	cursor.hide()
	tooltip.hide()
	_description()
	open_menu()

func _selected() -> Dictionary:
	if selected_equipment and not _slot_item(selected_slot).is_empty():return _slot_item(selected_slot)
	if selected_index >= 0 and selected_index < items.size(): return items[selected_index]
	return {}

func _description() -> void:
	var item := _selected()
	description.text = "" if item.is_empty() else "%s  ×%d" % [item.name, int(item.count)]
	if item.get("slot")=="gourd":description.text=item.name+" · "+GourdRules.status(item.id,_gourds())

func _gourds()->Dictionary:
	return Game.player.get("gourds",{}) if online_model==null else online_model.state.get("gourds",{})

func toggle_gourd()->void:
	var item:=_selected()
	if item.get("slot")!="gourd" or not _gourds().has(item.id):return
	var action:="gourd_disable" if _gourds()[item.id].enabled else "gourd_enable"
	if online_model!=null:online_model.submit(action,item.id);return
	var result:=await Game.shop_command(action,item.id)
	if not is_inside_tree():return
	close_menu();refresh()
	if not result.ok:description.text=result.message
	changed.emit()

func open_menu() -> void:
	if item_menu != null and is_instance_valid(item_menu): close_menu(); return
	tooltip.hide()
	item_menu = _box(Rect2(85, 246, 150, 140), Color("fff2af"), Color("765322"), 1)
	item_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var item := _selected()
	var actions: Array[Dictionary] = []
	if not item.is_empty():
		actions.append({"name": "查看", "call": show_item})
		if item.slot=="consumable":
			if online_model==null or online_model.state.get("shop",{}).get("version")=="shop-v2": actions.append({"name":"使用","call":use_item})
		elif ShopRules.is_equipment(item): actions.append({"name":"卸下" if selected_equipment else "装备","call":equip_item})
		elif item.slot=="gourd":actions.append({"name":"关闭自动补给" if _gourds().get(item.id,{}).get("enabled",false) else "开启自动补给","call":toggle_gourd})
		if not item.has("instance_id") and (online_model==null or online_model.state.get("shop",{}).get("version")=="shop-v2"): actions.append({"name":"丢弃","call":confirm_discard})
	actions.append({"name":"装备实例","call":open_loot})
	if online_model==null or online_model.state.has("gathering"):actions.append({"name":"采集材料袋","call":open_material_bag})
	actions.append({"name": "整理背包", "call": sort_items})
	if online_model == null: actions.append({"name": "购药 · 8 铜钱", "call": buy_potion})
	for i in actions.size():
		var button := _button(String(actions[i].name), Rect2(3, 3 + i * 26, 144, 25), false, item_menu)
		button.add_theme_color_override("font_color", Color("705321"))
		button.pressed.connect(actions[i].call)
		if online_model != null and (button.text in ["装备", "卸下", "使用", "丢弃"] or button.text.ends_with("自动补给")): button.disabled = not online_model.ready or online_model.pending() or online_model.active() or online_model.is_soul()
		if button.text=="使用":
			var stats := _display_stats()
			var player := _display_player()
			button.disabled=button.disabled or not ShopRules.use_error(item,player,stats,_allocated_points()).is_empty()
		if button.text=="装备" and int(item.get("job",-1))>=0 and int(item.job)!=int(_display_player().job): button.disabled=true
		if button.text.begins_with("购药"): button.disabled = int(Game.player.gold) < 8
	item_menu.size.y = 6 + actions.size() * 26
	item_menu.position.y=minf(item_menu.position.y,416-item_menu.size.y)

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
	tooltip_label.text=LootRules.describe(item.instance) if item.has("instance_id") else "%s  等级：1\n%s" % [item.name, ShopRules.description(item.id,_display_stats())]
	_gourd_tooltip(item)
	tooltip.show()
	move_child(tooltip, get_child_count() - 1)

func _gourd_tooltip(item:Dictionary)->void:
	var gourd:bool=item.get("slot")=="gourd"
	tooltip.size=Vector2(194,86) if gourd else Vector2(141,41)
	tooltip_label.size=Vector2(184,78) if gourd else Vector2(132,35)
	tooltip_label.add_theme_font_size_override("font_size",11 if gourd else 12)
	if gourd:
		tooltip.position.x=minf(tooltip.position.x,120)
		tooltip_label.text="%s\n%s\n仅战斗外补给，空瓶保留。\n找清微道人／各地图巡山人免费补充。"%[item.name,GourdRules.status(item.id,_gourds())]

func use_item() -> void:
	var item := _selected()
	if item.is_empty() or item.get("slot")!="consumable": return
	var code:=ShopRules.use_error(item,_display_player(),_display_stats(),_allocated_points())
	if not code.is_empty(): description.text=OnlinePve.error_text(code);return
	if item.get("effect")=="teleport":
		_open_travel_picker()
		return
	if item.get("effect")=="reset_attributes":
		close_menu()
		item_menu=_box(Rect2(59,248,203,119),Color("fff2af"),Color("765322"),1)
		item_menu.mouse_filter=Control.MOUSE_FILTER_STOP
		_text("使用%s？\n返还全部已分配属性点，消耗1颗。"%item.name,Rect2(8,7,187,65),12,Color("705321"),false,item_menu).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var yes:=_button("确定",Rect2(18,86,64,24),true,item_menu)
		yes.name="ConfirmAttributeReset"
		yes.pressed.connect(_use_item_id.bind(String(item.id)))
		_button("取消",Rect2(121,86,64,24),true,item_menu).pressed.connect(close_menu)
		return
	await _use_item_id(item.id)

func _open_travel_picker()->void:
	if is_instance_valid(travel_picker):return
	close_menu();tooltip.hide();set_process_unhandled_key_input(false)
	travel_picker=AIWorldPanel.new();travel_picker.name="TravelPicker";travel_picker.travel_action="scroll_travel"
	travel_picker.allow_ruins=int(Game.player.get("quest",0) if online_model==null else online_model.state.character.quest_stage)>=3
	var current:String=AIWorld.local_map_id() if online_model==null else online_model.state.character.map_id
	travel_picker.present(current,{},int(_display_player().level));add_child(travel_picker)
	travel_picker.back_requested.connect(func()->void:
		travel_picker.queue_free();travel_picker=null;set_process_unhandled_key_input(true))
	travel_picker.requested.connect(func(_action:String,destination:String)->void:
		if travel_picker.busy:return
		travel_picker.busy=true;travel_picker.notice="正在确认传送……";travel_picker.refresh()
		if online_model!=null:
			if not online_model.submit("scroll_travel",destination):finish_scroll_travel("暂时无法传送，请确认神行符数量和角色状态。")
		else:travel_requested.emit(destination))

func finish_scroll_travel(message:String)->void:
	if not is_instance_valid(travel_picker):return
	travel_picker.busy=false;travel_picker.notice=message;travel_picker.refresh()

func _allocated_points() -> Array:
	return Game.allocated_attributes() if online_model==null else online_model.state.get("attributes",{}).get("allocated",[0,0,0,0,0])

func _use_item_id(id: String) -> void:
	var item:=ShopRules.item(id)
	if item.is_empty(): return
	var code:=ShopRules.use_error(item,_display_player(),_display_stats(),_allocated_points())
	if not code.is_empty(): description.text=OnlinePve.error_text(code);return
	if online_model!=null:
		if online_model.state.get("shop",{}).get("version")=="shop-v2": online_model.submit("use",id)
		return
	if Game.storage_busy: return
	var result := await Game.shop_command("use",id)
	if not is_inside_tree(): return
	close_menu();refresh()
	if not result.ok: description.text=result.message
	changed.emit()

func equip_item() -> void:
	var item := _selected()
	if item.is_empty() or not ShopRules.is_equipment(item): return
	var action := "unequip" if selected_equipment else "equip"
	if item.has("instance_id"):action="gear_"+action
	var target:String=item.get("instance_id",item.id)
	if online_model != null:
		online_model.submit(action,target)
		return
	if Game.storage_busy: return
	var result:PlatformResult=await Game.loot_command(action,target) if item.has("instance_id") else await Game.shop_command(action,target)
	if not is_inside_tree(): return
	close_menu()
	selected_equipment = false
	refresh()
	if not result.ok: description.text = result.message
	changed.emit()

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
	if online_model!=null and online_model.state.get("shop",{}).get("version")!="shop-v2": return
	var item := _selected().duplicate()
	if item.is_empty(): return
	if item.has("instance_id"):open_loot();return
	close_menu()
	item_menu=_box(Rect2(65,264,191,89),Color("fff2af"),Color("765322"),1)
	item_menu.mouse_filter=Control.MOUSE_FILTER_STOP
	_text("确定丢弃“%s”？"%item.name,Rect2(8,7,178,37),12,Color("705321"),false,item_menu).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var yes:=_button("确定",Rect2(17,57,57,23),true,item_menu)
	yes.pressed.connect(func() -> void:
		if online_model!=null:
			online_model.submit("discard",item.id,[],int(item.count))
			return
		if Game.storage_busy:return
		var result:=await Game.shop_command("discard",item.id,int(item.count))
		if not is_inside_tree():return
		selected_equipment=false;close_menu();refresh()
		if not result.ok:description.text=result.message
		changed.emit()
	)
	_button("取消",Rect2(113,57,57,23),true,item_menu).pressed.connect(close_menu)

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
