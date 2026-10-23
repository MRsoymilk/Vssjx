class_name CraftingPanel
extends Control
signal back_requested
signal changed
var online_model:OnlinePve
var from_details:=false
var selected_id:=""
var status:Label
var materials:Label
var details:Label
var affix:OptionButton
var focus:OptionButton
var upgrade:Button
var reroll:Button
var salvage:Button
var confirmation:=""
var busy:=false
var refreshing:=false
var paper:Panel
var detail_scroll:ScrollContainer
var item_icon:TextureRect
var item_name:Label
var item_meta:Label
var reroll_cost:Label
var upgrade_cost:Label
var resource_counts:Array[Label]=[]
var back:Button
var palette:Dictionary
var _shown_id:=""
const INK:=Color("654518")
const SLOTS:={"weapon":"武器","pendant":"腰佩","armor":"衣服","wrist":"手腕","belt":"腰带","pants":"裤子","boots":"鞋子","ring":"戒指","necklace":"项链","hat":"帽子"}
func _frame(rect:Rect2,fill:Color,edge:Color,width:int=1)->Panel:
	var panel:=OriginalSceneChrome.panel(self,rect,fill,edge)
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(width)
	return panel
func _skin_button(button:Button,danger:bool=false)->void:
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("ead5a0") if state=="disabled" else (palette.deep if state=="pressed" else palette.main)
		style.border_color=Color("b89959") if state=="disabled" else Color("fff0a8")
		style.set_border_width_all(1);style.set_content_margin_all(2)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color"]:button.add_theme_color_override(state,Color("8d3027") if danger else INK)
	button.add_theme_color_override("font_pressed_color",Color("fff1b8"))
	button.add_theme_color_override("font_disabled_color",Color("978255"))
	button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
func _picker(name:String,rect:Rect2)->OptionButton:
	var box:=OptionButton.new();box.name=name;box.position=rect.position;box.size=rect.size;box.fit_to_longest_item=false;box.clip_text=true;box.focus_mode=Control.FOCUS_NONE
	box.add_theme_font_size_override("font_size",10);add_child(box)
	var popup:=box.get_popup();popup.theme=theme;popup.prefer_native_menu=false;popup.wrap_controls=false
	popup.max_size=Vector2i(276,210);popup.about_to_popup.connect(_fit_popup.bind(box),CONNECT_DEFERRED)
	return box
func _fit_popup(box:OptionButton)->void:
	var popup:=box.get_popup();var dimensions:=Vector2i(ceili(box.size.x),mini(210,box.item_count*25+12))
	popup.max_size=dimensions;popup.min_size=dimensions;popup.size=dimensions;popup.scroll_to_item(box.selected)
func _ready()->void:
	z_index=2;size=Vector2(320,480);mouse_filter=Control.MOUSE_FILTER_STOP
	palette=OriginalUITheme.palette("forge")
	if from_details:palette={"main":Color("faf4b5"),"deep":Color("79acd0"),"body":Color("fff4bf"),"edge":Color("d3bc73")}
	theme=preload("res://scenes/ui/shop_category_theme.tres").duplicate(true)
	var disabled:=StyleBoxFlat.new();disabled.bg_color=Color("ead5a0");disabled.border_color=Color("b89959");disabled.set_border_width_all(1);disabled.content_margin_left=8;disabled.content_margin_top=3;disabled.content_margin_right=8;disabled.content_margin_bottom=3
	theme.set_stylebox("disabled","OptionButton",disabled);theme.set_color("font_disabled_color","OptionButton",Color("978255"))
	if from_details:paper=preload("res://scripts/equipment_paper.gd").frame(self,Rect2(12,57,296,372),"装 备 养 成")
	else:
		paper=_frame(Rect2(12,57,296,372),palette.main,Color("ffe883"),2)
		_frame(Rect2(17,62,286,27),palette.deep,palette.edge)
		var title:=OriginalSceneChrome.label(self,"装 备 养 成",Rect2(32,63,256,24),15,Color("fff0a8"));title.name="Title";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	paper.name="ForgeFrame"
	materials=OriginalSceneChrome.label(self,"",Rect2(22,95,276,19),10,INK);materials.name="Materials"
	# 炼材使用加工后的金属锭造型，避免误用商城首项的矿石图标。
	var resource_icons:Array=["res://assets/ui/attribute_coin.png","res://assets/items/original/ix39.png","res://assets/ui/attribute_essence.png"]
	for i in 3:
		var badge:=OriginalSceneChrome.panel(materials,Rect2(i*94,0,88,19),palette.body,palette.edge)
		var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;badge.add_child(icon);icon.texture=load(resource_icons[i]);icon.position=Vector2(3,3);icon.size=Vector2(13,13)
		var count:=OriginalSceneChrome.label(badge,"",Rect2(19,1,66,17),10,INK);count.mouse_filter=Control.MOUSE_FILTER_PASS;resource_counts.append(count)
	_frame(Rect2(22,120,276,42),Color("fff0ba"),palette.deep)
	_frame(Rect2(27,124,34,34),palette.body,palette.deep)
	item_icon=TextureRect.new();item_icon.name="EquipmentIcon";item_icon.position=Vector2(29,126);item_icon.size=Vector2(30,30);item_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;item_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;add_child(item_icon)
	item_name=OriginalSceneChrome.label(self,"未选择装备",Rect2(70,122,220,18),12,INK);item_name.name="EquipmentName";item_name.mouse_filter=Control.MOUSE_FILTER_PASS;item_name.clip_text=true;item_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	item_meta=OriginalSceneChrome.label(self,"请先从装备列表中选择",Rect2(70,143,220,15),10,INK);item_meta.clip_text=true
	_frame(Rect2(22,168,276,94),Color("fff1bd"),palette.deep)
	detail_scroll=ScrollContainer.new();detail_scroll.name="DetailsScroll";detail_scroll.position=Vector2(28,174);detail_scroll.size=Vector2(264,82);detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(detail_scroll)
	details=OriginalSceneChrome.label(detail_scroll,"",Rect2(0,0,248,82),11,INK);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=248;details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	OriginalSceneChrome.label(self,"词条",Rect2(22,269,32,23),11,INK)
	affix=_picker("Affix",Rect2(58,268,240,24));affix.item_selected.connect(func(_i:int)->void:confirmation="")
	reroll=OriginalSceneChrome.button(self,"洗炼",Rect2(22,298,134,26),12);reroll.name="Reroll";reroll.pressed.connect(_action.bind("gear_reroll"))
	upgrade=OriginalSceneChrome.button(self,"强化+1",Rect2(164,298,134,26),12);upgrade.name="Upgrade";upgrade.pressed.connect(_action.bind("gear_upgrade"))
	reroll_cost=OriginalSceneChrome.label(self,"",Rect2(22,328,134,15),9,INK);reroll_cost.name="RerollCost"
	upgrade_cost=OriginalSceneChrome.label(self,"",Rect2(164,328,134,15),9,INK);upgrade_cost.name="UpgradeCost"
	salvage=OriginalSceneChrome.button(self,"分解装备",Rect2(22,349,134,25),11);salvage.name="Salvage";salvage.pressed.connect(_action.bind("gear_salvage"))
	focus=_picker("Focus",Rect2(164,349,134,25));focus.add_item("掉落：随缘")
	for slot in ShopRules.SLOTS:focus.add_item("掉落："+SLOTS[slot])
	focus.item_selected.connect(_focus_selected)
	status=OriginalSceneChrome.label(self,"强化不损毁装备，洗炼仅更改所选词条。",Rect2(22,379,276,23),10,INK);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	OriginalSceneChrome.label(self,"养成操作需再次确认",Rect2(22,405,190,16),9,INK)
	back=OriginalSceneChrome.button(self,"返回详情" if from_details else "返回装备",Rect2(222,402,76,21),11);back.name="Back";back.pressed.connect(func()->void:back_requested.emit())
	for button in [reroll,upgrade,back]:_skin_button(button)
	_skin_button(salvage,true)
	if from_details:
		for button in [reroll,upgrade,salvage,back]:preload("res://scripts/equipment_paper.gd").skin_button(button)
	for point in [Vector2(12,57),Vector2(300,57),Vector2(12,421),Vector2(300,421)]:
		var corner:=TextureRect.new();corner.texture=preload("res://assets/ui/bag_corner.png");corner.position=point;corner.size=Vector2(8,8);corner.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;corner.flip_h=point.x>160;corner.flip_v=point.y>240;corner.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(corner)
	if online_model!=null:online_model.changed.connect(_online_changed)
	refresh()
func _state()->Dictionary:return Game.player.get("loot_state",{}) if online_model==null else online_model.state.get("loot",{}).get("state",{})
func _character()->Dictionary:return Game.player if online_model==null else online_model.state.get("character",{})
func _item()->Dictionary:
	for item in _state().get("items",[]):
		if item.id==selected_id:return item
	return {}
func _locked()->bool:return busy or (Game.storage_busy or Game.local_battle_active() if online_model==null else not online_model.ready or online_model.pending() or online_model.active() or online_model.state.get("loot",{}).get("progression_sha256")!=ProgressionRules.catalog_hash) or _character().get("corpse") is Dictionary
func refresh()->void:
	refreshing=true
	var state:=_state();var item:=_item();var locked:=_locked();var selected:=affix.selected
	if selected_id!=_shown_id:detail_scroll.scroll_vertical=0;_shown_id=selected_id
	var amounts:Array=[int(_character().get("gold",0)),int(state.get("scrap",0)),int(state.get("essence",0))]
	materials.tooltip_text="铜钱%d · 炼材%d · 精华%d"%amounts
	for i in 3:
		resource_counts[i].text=str(amounts[i]);resource_counts[i].tooltip_text=["铜钱","炼材","精华"][i]+"："+str(amounts[i])
	focus.select(ShopRules.SLOTS.find(state.get("focus",""))+1);focus.disabled=locked or state.is_empty()
	affix.clear();affix.disabled=true;upgrade.disabled=true;reroll.disabled=true;salvage.disabled=true
	upgrade.text="强化+1";reroll.text="洗炼";reroll_cost.text="—";upgrade_cost.text="—"
	upgrade.tooltip_text="每级增加原始基础属性的2%，每项非零属性每级至少+1；词条不变。"
	if item.is_empty():
		item_icon.texture=null;item_name.text="未选择装备";item_meta.text="请先从装备列表中选择";affix.add_item("暂无可洗炼词条")
		details.text="请在装备列表选中一件，再打开养成。\n暂存装备需领取后才能养成。\n定向掉落：80%优先选定部位。";refreshing=false;return
	var definition:=ShopRules.item(item.template);var entry:=LootRules.bag_item(item)
	item_icon.texture=load(entry.icon);item_name.text=entry.name;item_name.tooltip_text=entry.name
	item_meta.text="%s · %s · 物等%d · +%d/6"%[{"legacy":"固定","white":"普通","blue":"魔法","yellow":"稀有","orange":"传奇","green":"套装"}[item.quality],SLOTS[definition.slot],int(item.level),int(item.upgrade)]
	var lines:Array[String]=[]
	for line in LootRules.describe(item).split("\n").slice(1):
		if not line.begins_with("编号 "):lines.append(line)
	details.text="\n".join(lines)
	for i in item.affixes.size():affix.add_item("词条%d：%s"%[i+1,LootRules.affix_text(item.affixes[i])])
	if not item.affixes.is_empty():affix.select(int(item.reroll_index) if item.get("reroll_index")!=null else clampi(selected,0,item.affixes.size()-1))
	else:affix.add_item("该装备没有随机词条")
	affix.disabled=locked or item.get("reroll_index")!=null or item.affixes.is_empty()
	affix.tooltip_text="已锁定第%d条，只可洗炼这一条。"%(int(item.reroll_index)+1) if item.get("reroll_index")!=null else "选择需要洗炼的词条，其余词条保持。"
	for action in ["gear_upgrade","gear_reroll"]:
		var quote:=ProgressionRules.quote(item,action);var button:Button=upgrade if action=="gear_upgrade" else reroll;var cost_label:Label=upgrade_cost if action=="gear_upgrade" else reroll_cost
		button.disabled=locked or quote.has("error");cost_label.add_theme_color_override("font_color",INK)
		if quote.has("cost"):
			var cost:Array=quote.cost
			cost_label.text="%d铜·%d炼材·%d精华"%cost
			var shortages:Array[String]=[]
			for i in 3:
				if amounts[i]<int(cost[i]):shortages.append(["铜钱","炼材","精华"][i]+"不足")
			button.disabled=button.disabled or not shortages.is_empty()
			button.tooltip_text="需要%d铜钱、%d炼材、%d精华。"%cost+("\n"+"、".join(shortages) if not shortages.is_empty() else "")
			cost_label.tooltip_text=button.tooltip_text
			if not shortages.is_empty():cost_label.add_theme_color_override("font_color",Color("9e3b27"))
		else:cost_label.text=OnlinePve.error_text(quote.error);button.tooltip_text=cost_label.text
		cost_label.clip_text=true;cost_label.mouse_filter=Control.MOUSE_FILTER_PASS
	salvage.disabled=locked or item.legacy or item.equipped
	if not item.legacy:
		salvage.tooltip_text="分解获得%d炼材、%d精华，保留外观解锁。"%[ProgressionRules.rules.salvage_scrap[item.quality],ProgressionRules.rules.salvage_essence[item.quality]]
		if item.equipped:salvage.tooltip_text="请先卸下装备，再分解。"
	else:salvage.tooltip_text=OnlinePve.error_text("LEGACY_CRAFT_LOCKED")
	refreshing=false
func _online_changed()->void:
	confirmation="";refresh();changed.emit()
	if not online_model.last_code.is_empty():status.text=OnlinePve.error_text(online_model.last_code)
func _focus_selected(index:int)->void:
	if refreshing or _locked():return
	confirmation="";_submit("gear_focus","any" if index==0 else ShopRules.SLOTS[index-1],1)
func _action(action:String)->void:
	if _locked() or _item().is_empty():return
	var button:Button={"gear_upgrade":upgrade,"gear_reroll":reroll,"gear_salvage":salvage}[action]
	if button.disabled:return
	var key:="%s:%d"%[action,affix.selected]
	if confirmation!=key:
		confirmation=key
		if action=="gear_salvage":status.text="再次点击确认分解，装备将永久消失。"
		else:
			var cost:Array=ProgressionRules.quote(_item(),action).cost
			status.text=("再次点击确认强化：%d铜／%d炼材／%d精华。"%cost) if action=="gear_upgrade" else ("确认洗炼第%d条：%d铜／%d炼材／%d精华。"%[affix.selected+1,cost[0],cost[1],cost[2]])
		return
	confirmation="";_submit(action,selected_id,affix.selected+1 if action=="gear_reroll" else 1)
func _submit(action:String,target:String,count:int)->void:
	if online_model!=null:
		status.text="正在等待服务端确认……" if online_model.submit(action,target,[],count) else "当前不能提交，请等待同步。";return
	busy=true;refresh()
	var result:=await Game.loot_command(action,target,count)
	if not is_inside_tree():return
	busy=false;refresh();status.text="已保存，材料与装备同步生效。" if result.ok else result.message;changed.emit()
func _unhandled_key_input(event:InputEvent)->void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		var input_viewport:=get_viewport();back_requested.emit();input_viewport.set_input_as_handled()
