class_name ShopPanel
extends Control
## Native shop: four tabs, two columns, 28x32 icons, five visible rows.
signal back_requested
signal changed
var online_model: OnlinePve
var selected := "weapon_2"
var busy := false
var section := "hot"
var category := "全部"
var preview: AnimatedSprite2D
var balance: Label
var summary: Label
var hint: Label
var total: Label
var buy_button: Button
var equip_button: Button
var preview_button: Button
var rows: Array[Button] = []
var goods: Array = []
var notice := ""
var tabs: Array[Button] = []
var category_box: OptionButton
var quantity_box: SpinBox
var scroll: ScrollContainer
var grid: GridContainer
var preview_window: Control
var _refreshing := false
const GOLD := Color("783426")

func _label(text: String, rect: Rect2, font_size: int=12, parent: Node=null) -> Label:
	var label := Label.new()
	label.text=text;label.position=rect.position;label.size=rect.size
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",GOLD)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	(parent if parent!=null else self).add_child(label)
	return label

func _style(color: Color, chosen: bool=false) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color;style.border_color=Color("fff840") if chosen else Color("d5b275")
	style.set_border_width_all(2 if chosen else 1)
	return style

func _button(text: String, rect: Rect2, callback: Callable, parent: Node=null) -> Button:
	var button:=Button.new()
	button.text=text;button.position=rect.position;button.size=rect.size;button.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(state,_style(Color("8a653a") if state=="disabled" else Color("eb9e36")))
	button.add_theme_color_override("font_color",GOLD)
	button.add_theme_color_override("font_hover_color",Color("734524"))
	button.add_theme_font_size_override("font_size",12)
	button.pressed.connect(callback)
	(parent if parent!=null else self).add_child(button)
	return button

func _ready() -> void:
	theme=preload("res://scenes/ui/online_pve_theme.tres")
	var panel:=Panel.new()
	panel.position=Vector2(12,36);panel.size=Vector2(296,410)
	panel.add_theme_stylebox_override("panel",_style(Color("fff6bc")))
	add_child(panel)
	var bar:=ColorRect.new()
	bar.position=Vector2(17,41);bar.size=Vector2(286,31);bar.color=Color("fe7d92");bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_label("商城",Rect2(31,45,70,22),16).name="Title"
	balance=_label("",Rect2(126,48,167,20))
	for i in ShopRules.catalog.tabs.size():
		var tab: Array=ShopRules.catalog.tabs[i]
		var button:=_button(tab[1],Rect2(0,0,70,24),func() -> void:section=tab[0];notice="";_filter(),%Tabs)
		button.custom_minimum_size.x=70
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tabs.append(button)
	category_box=%Category
	# PopupMenu is a separate Window; give it the authored theme explicitly.
	var category_popup:=category_box.get_popup()
	category_popup.theme=category_box.theme
	category_popup.prefer_native_menu=false
	category_popup.wrap_controls=false
	category_popup.max_size=Vector2i(286,230)
	category_popup.about_to_popup.connect(_fit_category_popup,CONNECT_DEFERRED)
	for label in ["全部","武器","帽子","衣服","手腕","腰带","裤子","鞋子","戒指","项链","腰佩","药品","药材","宝石","配方","材料","特殊"]:category_box.add_item(label)
	for family in GeneratedEquipment.FAMILIES: category_box.add_item(family.name+" · 本角色")
	# Keep the authored catalog above the dynamically added shop background.
	move_child(%Catalog,get_child_count()-1)
	category_box.item_selected.connect(func(index: int) -> void:category=category_box.get_item_text(index);notice="";_filter())
	scroll=%GoodsScroll
	grid=%Goods
	summary=_label("",Rect2(21,338,277,37),11)
	summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	total=_label("",Rect2(21,378,172,21),11)
	_label("数量",Rect2(198,378,30,21),10)
	quantity_box=SpinBox.new();quantity_box.position=Vector2(232,372);quantity_box.size=Vector2(67,23)
	quantity_box.min_value=1;quantity_box.max_value=99;quantity_box.value=1;quantity_box.step=1
	quantity_box.add_theme_font_size_override("font_size",11);add_child(quantity_box)
	var number_input:=quantity_box.get_line_edit()
	for state in ["normal","focus","read_only"]:number_input.add_theme_stylebox_override(state,_style(Color("f5df9b")))
	number_input.add_theme_color_override("font_color",GOLD)
	number_input.add_theme_color_override("font_uneditable_color",GOLD)
	buy_button=_button("购买",Rect2(20,405,66,26),func() -> void:_command("buy"))
	equip_button=_button("装备",Rect2(92,405,66,26),func() -> void:
		var entry:=ShopRules.item(selected)
		_command("unequip" if ShopRules.equipped_id(_gear(),entry.get("slot",""))==selected else "equip")
	)
	preview_button=_button("试穿",Rect2(164,405,66,26),func() -> void:preview_window.show())
	_button("返回",Rect2(236,405,66,26),func() -> void:back_requested.emit())
	hint=_label("",Rect2(20,433,282,12),8)
	preview_window=Control.new();preview_window.hide();preview_window.z_index=2;add_child(preview_window)
	var shade:=ColorRect.new();shade.size=Vector2(320,480);shade.color=Color(0,0,0,0.5);preview_window.add_child(shade)
	var paper:=Panel.new();paper.position=Vector2(48,146);paper.size=Vector2(224,193);paper.add_theme_stylebox_override("panel",_style(Color("fff6bc")));preview_window.add_child(paper)
	_label("试穿预览",Rect2(105,157,130,25),14,preview_window)
	preview=OriginalArt.actor(_appearance());preview.position=Vector2(160,293);preview.scale=Vector2(1.5,1.5);preview_window.add_child(preview)
	_button("关闭",Rect2(113,306,94,25),func() -> void:preview_window.hide(),preview_window)
	for point in [Vector2(12,36),Vector2(308,36),Vector2(12,446),Vector2(308,446)]:
		var corner:=Sprite2D.new();corner.texture=preload("res://assets/ui/chat_frame_corner.svg")
		corner.position=point+Vector2(6 if point.x<100 else -6,6 if point.y<100 else -6)
		corner.flip_h=point.x>100;corner.flip_v=point.y>100;add_child(corner)
	quantity_box.value_changed.connect(func(_value: float) -> void:if not _refreshing:refresh())
	if online_model!=null:online_model.changed.connect(_online_changed)
	_filter()

func _fit_category_popup() -> void:
	var popup:=category_box.get_popup()
	var popup_size:=Vector2i(ceili(category_box.size.x),230)
	popup.max_size=popup_size
	popup.min_size=popup_size
	popup.size=popup_size
	popup.scroll_to_item(category_box.selected)

func _gear() -> Dictionary:
	return ShopRules.local_state(Game.player) if online_model==null else online_model.state.get("shop",{})
func _character() -> Dictionary:
	return Game.player if online_model==null else online_model.state.get("character",{})
func _appearance() -> String:
	var character:=_character();var gear:=_gear().duplicate(true);var entry:=ShopRules.item(selected)
	if not gear.is_empty() and ShopRules.is_equipment(entry) and ShopRules.equipment_error(entry,int(character.get("job",0)),int(character.get("gender",0))).is_empty():
		if not gear.has("slots"):gear.slots={}
		gear.slots[entry.slot]=selected
		if entry.slot in ["weapon","armor"]:gear[entry.slot]=selected
	return ShopRules.actor_key(int(character.get("job",0)),int(character.get("gender",0)),ShopRules.appearance(gear))

func _filter() -> void:
	var character := _character()
	var family := GeneratedEquipment.family_for_category(category)
	goods=ShopRules.catalog.items.filter(func(item: Dictionary) -> bool:return item.sections.has(section) and (category=="全部" or item.category==category or (not family.is_empty() and item.get("set_id", "").begins_with(family+"/") and ShopRules.equipment_error(item,int(character.get("job",0)),int(character.get("gender",0))).is_empty())))
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	rows.clear();scroll.scroll_vertical=0
	if not goods.any(func(item: Dictionary) -> bool:return item.id==selected):selected=goods[0].id if not goods.is_empty() else ""
	for item in goods:
		var id: String=item.id
		var button:=_button("",Rect2(0,0,132,38),func() -> void:selected=id;quantity_box.value=1;notice="";refresh(),grid)
		button.custom_minimum_size=Vector2(132,38)
		button.set_meta("item_id",id)
		var icon:=TextureRect.new();icon.name="Icon";icon.position=Vector2(3,3);icon.size=Vector2(29,32)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		icon.texture=load(item.icon);button.add_child(icon)
		_label(item.name,Rect2(36,2,93,16),10,button).name="ItemName"
		_label("",Rect2(36,19,93,15),9,button).name="Price"
		button.tooltip_text=item.name+" · "+item.category+"\n"+ShopRules.description(id)
		rows.append(button)
	if goods.is_empty():_label("此分类暂无商品",Rect2(0,0,260,35),12,grid)
	refresh()

func refresh() -> void:
	if _refreshing:return
	_refreshing=true
	var gear:=_gear();var character:=_character();var entry:=ShopRules.item(selected)
	var locked: bool=(busy or Game.storage_busy) if online_model==null else (not online_model.ready or online_model.pending() or online_model.active() or gear.is_empty())
	var gold:=int(character.get("gold",0))
	balance.text="铜钱：%d"%gold
	for i in tabs.size():tabs[i].add_theme_stylebox_override("normal",_style(Color("fff840") if ShopRules.catalog.tabs[i][0]==section else Color("fe7d92")))
	for row in rows:
		var id: String=row.get_meta("item_id")
		var item:=ShopRules.item(id)
		var on: bool=ShopRules.equipped_id(gear,item.slot)==id
		row.get_node("Price").text="已装备" if on else ("已有%d · %d铜"%[ShopRules.quantity(gear,id),int(item.price)] if ShopRules.quantity(gear,id)>0 else "%d铜钱"%int(item.price))
		row.add_theme_stylebox_override("normal",_style(Color("f5df9b") if id==selected else Color("fff6bc"),id==selected))
	if entry.is_empty():
		summary.text="";total.text="";buy_button.disabled=true;equip_button.disabled=true;preview_button.disabled=true
		_refreshing=false;return
	var equipment:=ShopRules.is_equipment(entry)
	var count:=ShopRules.quantity(gear,selected)
	quantity_box.max_value=1 if equipment or (online_model!=null and gear.get("version")!="shop-v2") else 99
	quantity_box.editable=not locked and not equipment
	var amount:=int(quantity_box.value)
	summary.text=entry.name+" · "+entry.category+"\n"+ShopRules.description(selected)
	if int(entry.job)>=0:summary.text+=" · "+Game.JOBS[int(entry.job)]
	if int(entry.get("gender",-1))>=0:summary.text+=" · "+("男" if int(entry.gender)==0 else "女")
	total.text="物品总价：%d铜钱"%(int(entry.price)*amount)
	OriginalArt.apply_appearance(preview,_appearance())
	var version_locked: bool=online_model!=null and gear.get("version")!="shop-v2" and (selected.begins_with("original/") or selected.begins_with("ai/"))
	buy_button.disabled=locked or version_locked or gold<int(entry.price)*amount or (equipment and count>0) or (not equipment and count+amount>99)
	var incompatible := not ShopRules.equipment_error(entry,int(character.get("job",0)),int(character.get("gender",0))).is_empty()
	equip_button.disabled=locked or version_locked or not equipment or count==0 or incompatible
	equip_button.text="卸下" if ShopRules.equipped_id(gear,entry.slot)==selected else "装备"
	preview_button.disabled=not equipment or incompatible
	hint.text=notice if not notice.is_empty() else ("此商品需要更新服务端" if version_locked else (entry.get("set_name", "套装")+" · AI新设计 · 数值为重建规则" if entry.get("art_source")=="AI生成" else "原包图标 · 名称、数值和部分换装映射为重建规则"))
	_refreshing=false

func _online_changed() -> void:
	if not online_model.last_code.is_empty():notice=OnlinePve.error_text(online_model.last_code)
	elif not online_model.pending() and online_model.last_action in ["buy","equip","unequip"]:notice="操作已保存。"
	refresh()
func _command(action: String) -> void:
	if busy or selected.is_empty():return
	var count:=int(quantity_box.value) if action=="buy" else 1
	if online_model!=null:
		if online_model.submit(action,selected,[],count):notice="正在确认……";refresh()
		return
	busy=true;refresh()
	var result:=await Game.shop_command(action,selected,count)
	if not is_inside_tree():return
	busy=false;notice="已购买，可到背包查看。" if action=="buy" else "装备已保存。"
	if not result.ok:notice=result.message
	refresh();changed.emit()
