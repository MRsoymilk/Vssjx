class_name LootPanel
extends Control
## Equipment instances use server UUIDs, never template IDs for online writes.
signal back_requested
signal changed
var online_model:OnlinePve
var list:ItemList
var details:Label
var summary:Label
var status:Label
var equip:Button
var claim:Button
var detail_header:Label
var detail_frame:Panel
var detail_scroll:ScrollContainer
var empty_hint:Label
var builds:Button
var palette:Dictionary
var _showing_builds:=false
var rows:Array=[]
var selected_id:=""
var busy:=false
const INK:=Color("fff8c5")
const GOLD:=Color("f8e14b")
const SCROLLBAR_WIDTH:=24.0
const SCROLLBAR_GRAB_MIN_HEIGHT:=28.0

func _frame(rect:Rect2,fill:Color,edge:Color,width:int=1)->Panel:
	var panel:=OriginalSceneChrome.panel(self,rect,fill,edge)
	(panel.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(width)
	return panel

func _skin_button(button:Button)->void:
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=palette.deep if state in ["pressed","disabled"] else (palette.body if state=="hover" else palette.main)
		style.border_color=palette.edge if state=="disabled" else GOLD
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color"]:button.add_theme_color_override(state,INK)
	button.add_theme_color_override("font_disabled_color",Color("83b6a0"))

func _skin_scrollbar(bar:VScrollBar)->void:
	bar.custom_minimum_size.x=SCROLLBAR_WIDTH
	bar.mouse_filter=Control.MOUSE_FILTER_STOP
	for state in ["scroll","scroll_focus","grabber","grabber_highlight","grabber_pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=palette.deep if state.begins_with("scroll") else palette.body
		style.border_color=GOLD if state=="grabber_pressed" else palette.edge
		style.set_border_width_all(1);style.content_margin_left=SCROLLBAR_WIDTH/2;style.content_margin_right=SCROLLBAR_WIDTH/2
		if state.begins_with("grabber"):
			style.content_margin_top=SCROLLBAR_GRAB_MIN_HEIGHT/2;style.content_margin_bottom=SCROLLBAR_GRAB_MIN_HEIGHT/2
		bar.add_theme_stylebox_override(state,style)

func _ready()->void:
	z_index=24;mouse_filter=Control.MOUSE_FILTER_STOP;size=Vector2(320,480)
	palette=OriginalUITheme.palette("bag")
	_frame(Rect2(12,57,296,372),palette.main,GOLD,2)
	_frame(Rect2(17,62,286,29),palette.deep,palette.edge)
	var title:=OriginalSceneChrome.label(self,"装 备 一 览",Rect2(32,64,256,24),15,GOLD);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	summary=OriginalSceneChrome.label(self,"",Rect2(22,99,171,23),10,INK)
	builds=OriginalSceneChrome.button(self,"流派",Rect2(251,99,47,23),11);builds.name="BuildOverview"
	builds.pressed.connect(func()->void:
		if _showing_builds:_describe()
		else:show_builds())
	var crafting:=OriginalSceneChrome.button(self,"养成",Rect2(198,99,47,23),11);crafting.name="Crafting";crafting.pressed.connect(open_crafting)
	list=ItemList.new();list.name="Instances";list.position=Vector2(20,128);list.size=Vector2(280,129)
	list.fixed_icon_size=Vector2i(24,24);list.max_columns=1;list.same_column_width=true
	list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	list.add_theme_font_size_override("font_size",11);list.add_theme_color_override("font_color",INK)
	list.add_theme_constant_override("v_separation",6);list.add_theme_constant_override("h_separation",8)
	list.add_theme_constant_override("icon_margin",8);list.add_theme_constant_override("line_separation",3)
	add_child(list)
	_skin_scrollbar(list.get_v_scroll_bar())
	var slot:=StyleBoxFlat.new();slot.bg_color=palette.deep;slot.border_color=palette.edge;slot.set_border_width_all(1);slot.set_content_margin_all(5)
	list.add_theme_stylebox_override("panel",slot)
	var selected:=StyleBoxFlat.new();selected.bg_color=palette.slot;selected.border_color=GOLD;selected.set_border_width_all(1)
	list.add_theme_stylebox_override("selected",selected);list.add_theme_stylebox_override("selected_focus",selected);list.add_theme_color_override("font_selected_color",GOLD)
	var hover:=selected.duplicate();hover.border_color=palette.edge;list.add_theme_stylebox_override("hovered",hover)
	list.item_selected.connect(func(index:int)->void:selected_id=rows[index].id;_describe())
	empty_hint=OriginalSceneChrome.label(self,"暂无装备\n可通过探索和战斗获取",Rect2(36,161,248,63),11,Color("a8ddc4"));empty_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	detail_frame=_frame(Rect2(20,264,280,109),palette.deep,palette.edge)
	detail_header=OriginalSceneChrome.label(self,"装备详情",Rect2(28,269,264,18),11,GOLD)
	detail_scroll=ScrollContainer.new();detail_scroll.name="DetailsScroll";detail_scroll.position=Vector2(28,291);detail_scroll.size=Vector2(264,76);detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(detail_scroll)
	_skin_scrollbar(detail_scroll.get_v_scroll_bar())
	var text_width:=detail_scroll.size.x-SCROLLBAR_WIDTH-4
	details=OriginalSceneChrome.label(detail_scroll,"",Rect2(0,0,text_width,76),10,INK);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=text_width;details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	equip=OriginalSceneChrome.button(self,"装备",Rect2(20,382,86,27),12);equip.name="Equip";equip.pressed.connect(_action.bind("toggle"))
	claim=OriginalSceneChrome.button(self,"领取暂存",Rect2(112,382,94,27),12);claim.name="Claim";claim.pressed.connect(_action.bind("gear_claim"))
	var back:=OriginalSceneChrome.button(self,"返回背包",Rect2(212,382,88,27),12);back.name="Back";back.pressed.connect(func()->void:back_requested.emit())
	for button in [equip,claim,back,builds,crafting]:_skin_button(button)
	status=OriginalSceneChrome.label(self,"选择装备可查看属性、穿戴或领取。",Rect2(22,413,276,13),9,Color("c3e7bd"));status.clip_text=true
	for point in [Vector2(12,57),Vector2(300,57),Vector2(12,421),Vector2(300,421)]:
		var corner:=TextureRect.new();corner.position=point;corner.size=Vector2(8,8);corner.texture=preload("res://assets/ui/bag_corner.png");corner.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;corner.mouse_filter=Control.MOUSE_FILTER_IGNORE
		corner.flip_h=point.x>160;corner.flip_v=point.y>240;add_child(corner)
	if online_model!=null:online_model.changed.connect(_online_changed)
	refresh()

func _state()->Dictionary:return Game.player.get("loot_state",{}) if online_model==null else online_model.state.get("loot",{}).get("state",{})
func _character()->Dictionary:return Game.player if online_model==null else online_model.state.get("character",{})
func _online_changed()->void:
	refresh()
	if not online_model.last_code.is_empty():status.text=OnlinePve.error_text(online_model.last_code)
func refresh()->void:
	var s:=_state();rows=s.get("items",[])+s.get("pending",[]);list.clear()
	var pending:Array=s.get("pending",[])
	for i in rows:
		var entry:=LootRules.bag_item(i)
		var place:="待领取" if pending.has(i) else ("已穿戴" if i.equipped else "未穿戴")
		var quality:String={"legacy":"固定","white":"普通","blue":"魔法","yellow":"稀有","orange":"传奇","green":"套装"}.get(i.quality,"")
		list.add_item("[%s] %s"%[place,entry.name],load(entry.icon))
		list.set_item_tooltip(list.item_count-1,"%s · %s · %d级\n编号 %s"%[entry.name,quality,int(i.level),String(i.id).right(8)])
		list.set_item_custom_fg_color(list.item_count-1,{"blue":Color("9de4ff"),"yellow":GOLD,"orange":Color("ffb65a"),"green":Color("8df0b0")}.get(i.quality,INK))
		if i.id==selected_id:list.select(list.item_count-1)
	if not rows.is_empty() and list.get_selected_items().is_empty():list.select(0);selected_id=rows[0].id
	empty_hint.visible=rows.is_empty()
	var gear:Dictionary=ShopRules.local_state(Game.player) if online_model==null else online_model.state.get("shop",{})
	var potions:int=int(Game.player.get("potions",0)) if online_model==null else int(online_model.state.get("potions",0))
	summary.text="背包 %d/60 · 暂存 %d/20"%[ShopRules.bag_slots(gear,potions)+LootRules.extra_bag(s),pending.size()] if not s.is_empty() else "当前服务尚未开放装备实例"
	_describe()
func open_crafting()->void:
	if has_node("CraftingPanel"):return
	var panel:Control=load("res://scripts/crafting_panel.gd").new();panel.name="CraftingPanel";panel.online_model=online_model;panel.selected_id=selected_id;add_child(panel)
	panel.changed.connect(func()->void:refresh();changed.emit())
	panel.back_requested.connect(func()->void:panel.queue_free();refresh())
func show_builds()->void:
	_showing_builds=true;builds.text="装备";detail_header.text="流派说明";detail_scroll.scroll_vertical=0
	list.hide();empty_hint.hide();detail_frame.position.y=128;detail_frame.size.y=245
	detail_header.position.y=135;detail_scroll.position.y=157;detail_scroll.size.y=210
	equip.disabled=true;claim.disabled=true
	var stats:Dictionary=Game.stats() if online_model==null else online_model.state.get("stats",{})
	var active:=BuildRules.describe(stats.get("balance",{}).get("builds",{}))
	var descriptions:Array[String]=["当前：\n"+("尚未激活流派。" if active.is_empty() else active),"\n职业流派（装备自动激活）"]
	for entry in BuildRules.rules.items:
		if int(entry.job)!=int(_character().get("job",0)):continue
		descriptions.append("\n"+entry.name+" · 传奇："+entry.legend_name)
		descriptions.append("2件："+BuildRules.two_text(entry)+"\n4件或传奇："+entry.description)
	details.text="\n".join(descriptions)
	status.text="2件加属性，4件或传奇启用特效，同穿升2阶。"
func _describe()->void:
	_showing_builds=false;builds.text="流派";detail_header.text="装备详情";detail_scroll.scroll_vertical=0
	list.show();empty_hint.visible=rows.is_empty();detail_frame.position.y=264;detail_frame.size.y=109
	detail_header.position.y=269;detail_scroll.position.y=291;detail_scroll.size.y=76
	status.text="选择装备可查看属性、穿戴或领取。"
	var selection:Dictionary={}
	for i in rows:
		if i.id==selected_id:selection=i;break
	var c:=_character()
	var locked:bool=busy or (Game.storage_busy or Game.local_battle_active() if online_model==null else not online_model.ready or online_model.pending() or online_model.active()) or c.get("corpse") is Dictionary
	equip.disabled=true;claim.disabled=true
	if selection.is_empty():details.text="探索地图、击败怪物可获取装备。\n选中装备查看属性，暂存装备可领取到背包。";return
	var lines:Array[String]=[]
	for line in LootRules.describe(selection).split("\n"):
		if not line.begins_with("编号 "):lines.append(line)
	details.text="\n".join(lines)
	var pending:bool=_state().get("pending",[]).has(selection)
	claim.disabled=locked or not pending
	equip.text="卸下" if selection.equipped else "装备"
	equip.disabled=locked or pending or (not selection.equipped and int(selection.level)>int(c.get("level",1)))
	var worn:=LootRules.equipped(_state(),ShopRules.item(selection.template).slot)
	if not worn.is_empty() and worn.id!=selection.id:
		details.text+="\n当前：%s · %s"%[ShopRules.item(worn.template).name,String(worn.id).right(6)]
func _action(action:String)->void:
	if busy:return
	var chosen:Dictionary={}
	for i in rows:
		if i.id==selected_id:chosen=i;break
	if chosen.is_empty():return
	if action=="toggle":
		if equip.disabled:return
		action="gear_unequip" if chosen.equipped else "gear_equip"
	elif action=="gear_claim" and claim.disabled:return
	if online_model!=null:
		if not online_model.submit(action,selected_id):status.text="当前不能提交，请等待同步。"
		return
	busy=true;_describe()
	var result:=await Game.loot_command(action,selected_id)
	if not is_inside_tree():return
	busy=false;refresh();status.text="装备已保存。" if result.ok else result.message;changed.emit()
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:back_requested.emit();get_viewport().set_input_as_handled()
