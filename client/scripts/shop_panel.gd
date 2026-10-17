class_name ShopPanel
extends Control
signal back_requested
signal changed
var online_model: OnlinePve
var selected := "weapon_2"
var busy := false
var preview: AnimatedSprite2D
var balance: Label
var summary: Label
var hint: Label
var buy_button: Button
var equip_button: Button
var rows: Array[Button] = []
var notice := ""

func _label(text: String, rect: Rect2, font_size: int = 12) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("705021"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("aa671d")
	style.border_color = Color("f5d586")
	style.set_border_width_all(2)
	for state in ["normal","hover","pressed","disabled"]:
		var box := style.duplicate()
		box.bg_color = Color("6e614a") if state == "disabled" else (Color("c1842c") if state == "hover" else style.bg_color)
		button.add_theme_stylebox_override(state,box)
	button.add_theme_color_override("font_color",Color("fff0a0"))
	button.add_theme_color_override("font_hover_color",Color("ffffff"))
	button.add_theme_font_size_override("font_size",12)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _ready() -> void:
	theme = preload("res://scenes/ui/online_pve_theme.tres")
	var panel := Panel.new()
	panel.position = Vector2(18,38)
	panel.size = Vector2(284,404)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("fff2be")
	paper.border_color = Color("bd8022")
	paper.set_border_width_all(4)
	panel.add_theme_stylebox_override("panel",paper)
	add_child(panel)
	for pos in [Vector2(18,38),Vector2(302,38),Vector2(18,442),Vector2(302,442)]:
		var corner := Sprite2D.new()
		corner.texture = preload("res://assets/ui/chat_frame_corner.svg")
		corner.position = pos + Vector2(7 if pos.x < 100 else -7,7 if pos.y < 100 else -7)
		corner.flip_h = pos.x > 100
		corner.flip_v = pos.y > 100
		add_child(corner)
	_label("商店",Rect2(34,49,70,22),16)
	balance = _label("",Rect2(122,51,158,20))
	preview = OriginalArt.actor(_appearance())
	preview.position = Vector2(79,151)
	add_child(preview)
	summary = _label("",Rect2(128,85,154,76))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in ShopRules.catalog.items.size():
		var id: String = ShopRules.catalog.items[i].id
		rows.append(_button("",Rect2(33,170+i*29,254,27),func() -> void: selected=id;notice="";refresh()))
	hint = _label("",Rect2(33,347,254,32),10)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy_button = _button("购买",Rect2(33,381,76,28),func() -> void: _command("buy"))
	equip_button = _button("装备",Rect2(117,381,76,28),func() -> void:
		var gear := _gear()
		_command("unequip" if gear.get(ShopRules.item(selected).slot) == selected else "equip")
	)
	_button("返回",Rect2(201,381,86,28),func() -> void: back_requested.emit())
	_label("原包部件 · 售价/属性暂定",Rect2(33,413,254,16),10)
	if online_model != null: online_model.changed.connect(_online_changed)
	refresh()

func _gear() -> Dictionary:
	return ShopRules.local_state(Game.player) if online_model == null else online_model.state.get("shop",{})

func _character() -> Dictionary:
	return Game.player if online_model == null else online_model.state.get("character",{})

func _appearance() -> String:
	var character := _character()
	var gear := _gear().duplicate(true)
	var entry := ShopRules.item(selected)
	if not gear.is_empty() and entry.get("slot") in ["weapon","armor"]: gear[entry.slot] = selected
	return ShopRules.actor_key(int(character.get("job",0)),int(character.get("gender",0)),ShopRules.appearance(gear))

func refresh() -> void:
	var gear := _gear()
	var character := _character()
	var owned: Array = gear.get("owned",[])
	var locked := busy or Game.storage_busy if online_model == null else (not online_model.ready or online_model.pending() or online_model.active() or gear.is_empty())
	var entry := ShopRules.item(selected)
	var gold := int(character.get("gold",0))
	balance.text = "铜钱：%d" % gold
	for i in rows.size():
		var row: Dictionary = ShopRules.catalog.items[i]
		var status := "已装备" if gear.get(row.slot) == row.id else ("已拥有" if owned.has(row.id) else "%d铜钱" % int(row.price))
		rows[i].text = ("▶ " if row.id == selected else "") + row.name + " · " + status
		summary.text = "%s\n%s\n试穿预览" % [entry.name,ShopRules.description(selected)]
	OriginalArt.apply_appearance(preview,_appearance())
	buy_button.disabled = locked or gold < int(entry.price) or (selected != "potion" and owned.has(selected))
	if selected == "potion": buy_button.disabled = buy_button.disabled or int(character.get("potions",0) if online_model == null else online_model.state.get("potions",0)) >= 99
	equip_button.disabled = locked or entry.slot == "consumable" or not owned.has(selected)
	equip_button.text = "卸下" if gear.get(entry.slot) == selected else "装备"
	hint.text = notice if not notice.is_empty() else ("购买后可装备，兵器随职业变化。" if not locked else "请等待同步或当前操作完成。")

func _online_changed() -> void:
	if not online_model.last_code.is_empty(): notice = OnlinePve.error_text(online_model.last_code)
	elif not online_model.pending() and online_model.last_action in ["buy","equip","unequip"]: notice = "操作已保存。"
	refresh()

func _command(action: String) -> void:
	if busy: return
	if online_model != null:
		if online_model.submit(action,selected): notice="正在确认……";refresh()
		return
	busy = true
	refresh()
	var result := await Game.shop_command(action,selected)
	if not is_inside_tree(): return
	busy = false
	notice = "已购买，可点击装备。" if action == "buy" else "装备已保存。"
	if not result.ok: notice = result.message
	refresh()
	changed.emit()
