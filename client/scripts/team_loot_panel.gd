class_name TeamLootPanel
extends Control
signal dismissed
var model:OnlineTeamModel
var list:ItemList
var details:Label
var results:Label
var clock:Label
var roll:Button
var pass_button:Button
var hint:Label
var selected_id:=""
const INK:=Color("654518")
func _ready()->void:
	z_index=90;size=Vector2(320,480);mouse_filter=MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.size=size;shade.color=Color(0,0,0,.65);add_child(shade)
	var paper:=Panel.new();paper.position=Vector2(8,61);paper.size=Vector2(304,363);var style:=StyleBoxFlat.new();style.bg_color=Color("fff0ba");style.border_color=Color("906329");style.set_border_width_all(3);paper.add_theme_stylebox_override("panel",style);add_child(paper)
	OriginalSceneChrome.label(self,"队伍战利品 · ROLL骰子",Rect2(16,69,288,24),15,INK)
	clock=OriginalSceneChrome.label(self,"",Rect2(16,96,288,18),11,INK)
	list=ItemList.new();list.name="Drops";list.position=Vector2(16,118);list.size=Vector2(288,52);list.add_theme_font_size_override("font_size",11);list.add_theme_color_override("font_color",INK);add_child(list)
	var box:=StyleBoxFlat.new();box.bg_color=Color("fff8d4");list.add_theme_stylebox_override("panel",box)
	var selected:=box.duplicate();selected.bg_color=Color("f1d16a");list.add_theme_stylebox_override("selected",selected);list.add_theme_stylebox_override("selected_focus",selected);list.add_theme_color_override("font_selected_color",INK)
	list.item_selected.connect(func(index:int)->void:selected_id=model.loot_pool().drops[index].item.id;_describe())
	var scroll:=ScrollContainer.new();scroll.position=Vector2(16,177);scroll.size=Vector2(288,69);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	details=OriginalSceneChrome.label(scroll,"",Rect2(0,0,272,69),11,INK);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=272;details.size_flags_horizontal=SIZE_EXPAND_FILL
	var board:=ScrollContainer.new();board.position=Vector2(16,252);board.size=Vector2(288,91);board.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(board)
	results=OriginalSceneChrome.label(board,"",Rect2(0,0,272,91),11,INK);results.custom_minimum_size.x=272;results.size_flags_horizontal=SIZE_EXPAND_FILL;results.add_theme_constant_override("line_spacing",-2)
	roll=OriginalSceneChrome.button(self,"ROLL点 · 1～100",Rect2(16,347,140,26),12);roll.name="Roll";roll.pressed.connect(_choose.bind("loot_roll"))
	pass_button=OriginalSceneChrome.button(self,"放弃",Rect2(164,347,140,26),12);pass_button.name="Pass";pass_button.pressed.connect(_choose.bind("loot_pass"))
	hint=OriginalSceneChrome.label(self,"最高点获得；同点加骰；满包暂存。",Rect2(16,376,288,16),10,INK)
	var back:=OriginalSceneChrome.button(self,"返回（未选仍会计时）",Rect2(16,397,288,20),11);back.pressed.connect(func()->void:dismissed.emit();queue_free())
	for button in [roll,pass_button,back]:
		var normal:=StyleBoxFlat.new();normal.bg_color=Color("f6ce76");normal.border_color=Color("906329");normal.set_border_width_all(1)
		var disabled:=normal.duplicate();disabled.bg_color=Color("d8cda6")
		for key in ["normal","hover","pressed"]:button.add_theme_stylebox_override(key,normal)
		button.add_theme_stylebox_override("disabled",disabled)
		for key in ["font_color","font_hover_color","font_pressed_color"]:button.add_theme_color_override(key,INK)
		button.add_theme_color_override("font_disabled_color",Color("8e7949"))
	model.changed.connect(refresh);model.message.connect(func(text:String)->void:hint.text=text);refresh()
func refresh()->void:
	var pool:=model.loot_pool();list.clear()
	for d in pool.get("drops",[]):
		list.add_item(("[已分配] " if d.delivered else "[待选择] ")+LootRules.bag_item(d.item).name+" · Lv.%d"%int(d.item.level))
		if d.item.id==selected_id:list.select(list.item_count-1)
	if list.item_count>0 and list.get_selected_items().is_empty():list.select(0);selected_id=pool.drops[0].item.id
	_describe()
func _process(_delta:float)->void:
	var pool:=model.loot_pool();var now:=model.server_time+Time.get_ticks_msec()-model.received_at
	clock.text="全部战利品已分配" if not model.loot_pending() else "剩余%d秒 · 超时自动放弃（独立于战斗回合）"%maxi(0,(int(pool.get("deadline_ms",now))-now+999)/1000)
	if now>=int(pool.get("deadline_ms",0)):roll.disabled=true;pass_button.disabled=true
func _drop()->Dictionary:
	for d in model.loot_pool().get("drops",[]):
		if d.item.id==selected_id:return d
	return {}
func _describe()->void:
	var d:=_drop();roll.disabled=true;pass_button.disabled=true
	if d.is_empty():details.text="本场没有装备掉落。";results.text="";return
	details.text=LootRules.describe(d.item);var lines:Array[String]=[];var names:={}
	for f in model.battle().fighters:
		names[f.id]=f.name
		var choice:="等待选择"
		if d.choices.has(f.id):choice="放弃" if d.choices[f.id]==null else "ROLL %d点"%int(d.choices[f.id])
		if f.id not in d.eligible:choice="不适用 · 自动放弃"
		if d.tie_scores.has(f.id):choice+=" → 加骰%d"%int(d.tie_scores[f.id])
		lines.append(f.name+"："+choice)
	if d.resolved:lines.append("获得："+names.get(d.winner,"无人（全员放弃）"))
	results.text="\n".join(lines)
	var locked:bool=model.pending() or d.resolved or model.character_id not in d.eligible or d.choices.has(model.character_id)
	roll.disabled=locked;pass_button.disabled=locked
func _choose(action:String)->void:
	if (roll.disabled if action=="loot_roll" else pass_button.disabled):return
	if not model.submit(action,selected_id):hint.text="正在同步，请稍后重试。"
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:dismissed.emit();queue_free();get_viewport().set_input_as_handled()
