extends Control
signal dismissed
signal profile_requested(id:String)
var model:RefCounted
var rows:VBoxContainer
var hint:Label
var confirmation:Dictionary={}
const INK:=Color("654518")
func _ready()->void:
	z_index=20
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.6);shade.size=Vector2(320,480);add_child(shade)
	var paper:=OriginalSceneChrome.panel(self,Rect2(8,30,304,410),Color("fff1b8"),Color("bb7b25"));paper.mouse_filter=MOUSE_FILTER_STOP
	OriginalSceneChrome.label(paper,"队伍",Rect2(12,10,270,30),18,INK)
	var scroll:=ScrollContainer.new();scroll.position=Vector2(12,48);scroll.size=Vector2(280,280);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;paper.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",5);scroll.add_child(rows)
	hint=OriginalSceneChrome.label(paper,"",Rect2(12,334,280,32),11,INK);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var back:=_button(paper,"返回");back.position=Vector2(114,371);back.size=Vector2(76,28);back.pressed.connect(dismiss)
	for i in 4:
		var corner:=TextureRect.new();corner.texture=preload("res://assets/ui/chat_corner.png");corner.size=Vector2(14,14);corner.position=Vector2(0 if i%2==0 else 290,0 if i<2 else 396);corner.flip_h=i%2==1;corner.flip_v=i>=2;corner.mouse_filter=MOUSE_FILTER_IGNORE;paper.add_child(corner)
	model.changed.connect(refresh);model.message.connect(func(text:String)->void:hint.text=text)
	refresh()
func _button(parent:Node,text:String)->Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=30
	var style:=StyleBoxFlat.new();style.bg_color=Color("ac6b20");style.border_color=Color("e8c67b");style.set_border_width_all(1)
	b.add_theme_stylebox_override("normal",style);b.add_theme_color_override("font_color",Color("fff4bd"));b.add_theme_font_size_override("font_size",12);parent.add_child(b);return b
func _label(text:String)->void:
	var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size=Vector2(260,26);l.add_theme_font_size_override("font_size",12);l.add_theme_color_override("font_color",INK);rows.add_child(l)
func _actions(actions:Array)->void:
	var h:=HBoxContainer.new();rows.add_child(h)
	for a in actions:
		var b:=_button(h,a[0]);b.size_flags_horizontal=SIZE_EXPAND_FILL;b.disabled=model.pending() or model.inflight;b.pressed.connect(a[1])
func open()->void:show();model.refresh();refresh()
func dismiss()->void:confirmation={};hide();dismissed.emit()
func confirm(action:String,id:String,text:String)->void:confirmation={"action":action,"id":id,"text":text};refresh()
func refresh()->void:
	if not is_node_ready():return
	for c in rows.get_children():rows.remove_child(c);c.queue_free()
	if not confirmation.is_empty():
		_label(confirmation.text)
		_actions([["确认",func()->void:model.submit(confirmation.action,confirmation.id);confirmation={};refresh()],["取消",func()->void:confirmation={};refresh()]])
		return
	for offer in model.state.incoming:
		_label("%s 邀请你加入队伍"%offer.name)
		_actions([["同意",func()->void:model.submit("accept",offer.id)],["拒绝",func()->void:model.submit("reject",offer.id)]])
	var p:Dictionary=model.party()
	if p.is_empty():
		_label("尚未加入任何队伍。\n点击其他玩家资料中的“邀请组队”，或先创建队伍。")
		_actions([["创建队伍",func()->void:model.submit("create")],["刷新",func()->void:model.refresh()]])
		return
	_label("%d / 5人 · %s"%[p.members.size(),"你是队长" if p.leader else "队长发起战斗"])
	_label("全员同图、在队长附近集合并准备；队长靠近怪物后共同进入战斗。")
	for m in p.members:
		_label("%s Lv.%d%s\n%s · %s"%[m.display_name,int(m.level)," · 队长" if m.leader else "","在线" if m.online else "离线","已准备" if m.ready else "未准备"])
		var actions:Array=[["资料",func()->void:profile_requested.emit(m.id)]]
		if m.id==model.character_id:actions.append(["取消准备" if m.ready else "准备",func()->void:model.submit("ready","","",not m.ready)])
		elif p.leader:
			actions.append(["移交",func()->void:confirm("transfer",m.id,"将队长移交给%s？"%m.display_name)])
			actions.append(["移出",func()->void:confirm("kick",m.id,"将%s移出队伍？"%m.display_name)])
		_actions(actions)
	for offer in p.outgoing:
		_label("已邀请%s，等待确认"%offer.name)
		_actions([["取消邀请",func()->void:model.submit("cancel",offer.id)]])
	_actions([["解散队伍" if p.leader else "退出队伍",func()->void:confirm("disband" if p.leader else "leave","","确定%s当前队伍？"%("解散" if p.leader else "退出"))],["刷新",func()->void:model.refresh()]])
