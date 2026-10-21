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
var rows:Array=[]
var selected_id:=""
var busy:=false
const INK:=Color("654518")

func _ready()->void:
	z_index=24;mouse_filter=Control.MOUSE_FILTER_STOP;size=Vector2(320,480)
	var paper:=Panel.new();paper.position=Vector2(8,61);paper.size=Vector2(304,363)
	var style:=StyleBoxFlat.new();style.bg_color=Color("fff0ba");style.border_color=Color("906329");style.set_border_width_all(3)
	paper.add_theme_stylebox_override("panel",style);add_child(paper)
	OriginalSceneChrome.label(self,"装备实例 · 独立编号／随机词缀",Rect2(16,69,288,24),14,INK)
	summary=OriginalSceneChrome.label(self,"",Rect2(16,94,288,22),11,INK)
	var builds:=OriginalSceneChrome.button(self,"流派",Rect2(255,94,49,21),11);builds.name="BuildOverview";builds.pressed.connect(show_builds)
	list=ItemList.new();list.name="Instances";list.position=Vector2(16,117);list.size=Vector2(288,117);list.add_theme_font_size_override("font_size",12);list.add_theme_color_override("font_color",INK);add_child(list)
	var slot:=StyleBoxFlat.new();slot.bg_color=Color("fff8d4");slot.border_color=Color("b18b48");slot.set_border_width_all(1);list.add_theme_stylebox_override("panel",slot)
	var selected:=slot.duplicate();selected.bg_color=Color("f1d16a");list.add_theme_stylebox_override("selected",selected);list.add_theme_stylebox_override("selected_focus",selected);list.add_theme_color_override("font_selected_color",INK)
	list.item_selected.connect(func(index:int)->void:selected_id=rows[index].id;_describe())
	var scroll:=ScrollContainer.new();scroll.position=Vector2(16,239);scroll.size=Vector2(288,109);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	details=OriginalSceneChrome.label(scroll,"",Rect2(0,0,272,109),11,INK);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=272;details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	equip=OriginalSceneChrome.button(self,"装备",Rect2(16,356,87,25),12);equip.name="Equip";equip.pressed.connect(_action.bind("toggle"))
	claim=OriginalSceneChrome.button(self,"领取暂存",Rect2(111,356,93,25),12);claim.name="Claim";claim.pressed.connect(_action.bind("gear_claim"))
	var back:=OriginalSceneChrome.button(self,"返回背包",Rect2(211,356,93,25),12);back.pressed.connect(func()->void:back_requested.emit())
	for button in [equip,claim,back,builds]:
		var normal:=StyleBoxFlat.new();normal.bg_color=Color("f6ce76");normal.border_color=Color("906329");normal.set_border_width_all(1)
		var hover:=normal.duplicate();hover.bg_color=Color("ffe5a2")
		var disabled:=normal.duplicate();disabled.bg_color=Color("d8cda6");disabled.border_color=Color("baa672")
		button.add_theme_stylebox_override("normal",normal);button.add_theme_stylebox_override("hover",hover);button.add_theme_stylebox_override("pressed",hover);button.add_theme_stylebox_override("disabled",disabled)
		button.add_theme_color_override("font_color",INK);button.add_theme_color_override("font_hover_color",INK);button.add_theme_color_override("font_pressed_color",INK);button.add_theme_color_override("font_disabled_color",Color("8e7949"))
	status=OriginalSceneChrome.label(self,"旧装备保留原属性；同底材不同编号独立管理。",Rect2(16,385,288,31),10,INK);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
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
		var prefix:="[暂存] " if pending.has(i) else ("[已穿] " if i.equipped else "")
		list.add_item(prefix+LootRules.bag_item(i).name+" · "+("固定" if i.legacy else "Lv.%d"%int(i.level))+" · "+String(i.id).right(6))
		if i.quality in ["orange","green"]:list.set_item_custom_fg_color(list.item_count-1,Color("a54b06") if i.quality=="orange" else Color("266522"))
		if i.id==selected_id:list.select(list.item_count-1)
	if not rows.is_empty() and list.get_selected_items().is_empty():list.select(0);selected_id=rows[0].id
	var gear:Dictionary=ShopRules.local_state(Game.player) if online_model==null else online_model.state.get("shop",{})
	var potions:int=int(Game.player.get("potions",0)) if online_model==null else int(online_model.state.get("potions",0))
	summary.text="背包 %d/60 · 暂存 %d/20"%[ShopRules.bag_slots(gear,potions)+LootRules.extra_bag(s),pending.size()] if not s.is_empty() else "当前服务尚未开放装备实例"
	_describe()
func show_builds()->void:
	var stats:Dictionary=Game.stats() if online_model==null else online_model.state.get("stats",{})
	var active:=BuildRules.describe(stats.get("balance",{}).get("builds",{}))
	var descriptions:Array[String]=["当前：\n"+("尚未激活流派。" if active.is_empty() else active),"\n职业流派（装备自动激活）"]
	for entry in BuildRules.rules.items:
		if int(entry.job)!=int(_character().get("job",0)):continue
		descriptions.append("\n"+entry.name+" · 传奇："+entry.legend_name)
		descriptions.append("2件："+BuildRules.two_text(entry)+"\n4件或传奇："+entry.description)
	details.text="\n".join(descriptions)
	status.text="2件提供属性；4件或传奇开启打法，二者同穿升为2阶。"
func _describe()->void:
	var selection:Dictionary={}
	for i in rows:
		if i.id==selected_id:selection=i;break
	var c:=_character()
	var locked:bool=busy or (Game.storage_busy if online_model==null else not online_model.ready or online_model.pending() or online_model.active()) or c.get("corpse") is Dictionary
	equip.disabled=true;claim.disabled=true
	if selection.is_empty():details.text="暂无装备实例。已有固定装备会迁移为独立编号，原属性不变。";return
	details.text=LootRules.describe(selection)
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
