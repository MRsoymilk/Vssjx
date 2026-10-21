extends Control
signal dismissed
signal profile_requested(id:String)
var model:RefCounted
var rows:VBoxContainer
var hint:Label
var confirmation:Dictionary={}
var summary:Label
var footer:HBoxContainer
var member_scroll:ScrollContainer
var tip:Label
const Chrome=preload("res://scripts/social_chrome.gd")
const INK:=Color("654518")
const TeamMarker=preload("res://scripts/team_marker.gd")
func _ready()->void:
	z_index=20
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.6);shade.size=Vector2(320,480);add_child(shade)
	var paper:=Chrome.frame(self,Rect2(8,28,304,418),"队　伍")
	summary=OriginalSceneChrome.label(paper,"",Rect2(14,38,276,22),13,INK)
	tip=OriginalSceneChrome.label(paper,"",Rect2(14,62,276,30),11,INK)
	tip.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var scroll:=ScrollContainer.new();scroll.name="Members";scroll.position=Vector2(14,96);scroll.size=Vector2(276,212);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;paper.add_child(scroll)
	member_scroll=scroll
	var track:=StyleBoxFlat.new();track.bg_color=Color("e4cd8b");track.content_margin_left=6
	var thumb:=StyleBoxFlat.new();thumb.bg_color=Color("a36b22");thumb.border_color=Color("f4d68c");thumb.set_border_width_all(1)
	var bar:=scroll.get_v_scroll_bar();bar.add_theme_stylebox_override("scroll",track)
	for state in ["grabber","grabber_highlight","grabber_pressed"]:bar.add_theme_stylebox_override(state,thumb)
	rows=VBoxContainer.new();rows.size_flags_horizontal=SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",5);scroll.add_child(rows)
	footer=HBoxContainer.new();footer.position=Vector2(14,314);footer.size=Vector2(276,30);paper.add_child(footer)
	hint=OriginalSceneChrome.label(paper,"",Rect2(14,347,276,20),10,INK);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	OriginalSceneChrome.panel(paper,Rect2(8,369,288,41),Color("b97a24"),Color("d8a64e"))
	var back:=Chrome.placed_button(paper,"返回",Rect2(110,374,84,30));back.name="Back";back.pressed.connect(dismiss)
	model.changed.connect(refresh);model.message.connect(func(text:String)->void:hint.text=text)
	refresh()
func _button(parent:Node,text:String)->Button:
	return Chrome.button(parent,text)
func _label(text:String)->void:
	var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size=Vector2(260,26);l.add_theme_font_size_override("font_size",12);l.add_theme_color_override("font_color",INK);rows.add_child(l)
func _member(m:Dictionary)->void:
	var card:=PanelContainer.new();card.name="MemberCard";card.custom_minimum_size=Vector2(260,58);rows.add_child(card)
	var style:=StyleBoxFlat.new();style.bg_color=Color("f9e8aa") if m.id!=model.character_id else Color("f5dda0");style.border_color=Color("bd923f");style.set_border_width_all(1);card.add_theme_stylebox_override("panel",style)
	var content:=Control.new();card.add_child(content)
	OriginalSceneChrome.panel(content,Rect2(5,6,44,44),Color("d6b96e"),INK)
	var portrait:=TextureRect.new();portrait.name="Portrait";portrait.texture=load("res://assets/ui/create_portrait_%d.png"%(clampi(int(m.job),0,2)*2+clampi(int(m.gender),0,1)));portrait.texture_filter=TEXTURE_FILTER_NEAREST;portrait.position=Vector2(7,8);portrait.size=Vector2(40,40);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.mouse_filter=MOUSE_FILTER_IGNORE;content.add_child(portrait)
	var flag:=TextureRect.new();flag.name="Flag";flag.texture=TeamMarker.texture_for(m);flag.material=TeamMarker.material_for(m);flag.texture_filter=TEXTURE_FILTER_NEAREST;flag.position=Vector2(55,5);flag.size=Vector2(15,18);flag.mouse_filter=MOUSE_FILTER_IGNORE;content.add_child(flag)
	var title:=OriginalSceneChrome.label(content,m.display_name+("（你）" if m.id==model.character_id else ""),Rect2(74,3,180,22),13,INK);title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.tooltip_text=m.display_name
	OriginalSceneChrome.label(content,"Lv.%d　%s"%[int(m.level),["力士","侠客","隐者"][clampi(int(m.job),0,2)]],Rect2(55,24,122,16),11,INK)
	OriginalSceneChrome.label(content,"离线" if not m.online else "队长" if m.leader else "跟随中" if m.get("following",true) else "暂离",Rect2(55,40,122,16),11,INK)
	var participating:bool=m.online and (m.leader or m.get("following",true))
	var prepared:bool=participating and (m.leader or m.ready)
	var ready:=OriginalSceneChrome.panel(content,Rect2(180,29,73,22),Color("d8e0a1") if prepared else Color("ead6a0"),Color("9c8442"))
	var status:=OriginalSceneChrome.label(ready,"不参战" if not participating else "带队迎战" if m.leader else "已准备" if m.ready else "未准备",Rect2(0,0,73,22),11,Color("36562a") if prepared else INK);status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
func _actions(actions:Array,parent:Node=null)->void:
	var h:=HBoxContainer.new();(rows if parent==null else parent).add_child(h)
	h.size_flags_horizontal=SIZE_EXPAND_FILL
	for a in actions:
		var b:=_button(h,a[0]);b.size_flags_horizontal=SIZE_EXPAND_FILL;b.disabled=not model.can_submit();b.pressed.connect(a[1])
func open()->void:show();model.refresh();refresh()
func dismiss()->void:confirmation={};hide();dismissed.emit()
func open_loot()->void:
	if has_node("TeamLoot"):return
	var panel:=TeamLootPanel.new();panel.name="TeamLoot";panel.model=model;add_child(panel)
func confirm(action:String,id:String,text:String)->void:confirmation={"action":action,"id":id,"text":text};refresh()
func refresh()->void:
	if not is_node_ready():return
	# Polling must not jump away from the member being inspected at the bottom.
	var scroll_offset:=member_scroll.scroll_vertical
	for c in rows.get_children():rows.remove_child(c);c.queue_free()
	for c in footer.get_children():footer.remove_child(c);c.queue_free()
	member_scroll.set_deferred("scroll_vertical",scroll_offset if confirmation.is_empty() else 0)
	var p:Dictionary=model.party()
	var ready_count:=0
	for m in p.get("members",[]):
		if m.online and (m.leader or (m.get("following",true) and m.ready)):ready_count+=1
	summary.text="尚未组队 · 最多五人同行" if p.is_empty() else "%d / 5 人　·　%d 人已准备"%[p.members.size(),ready_count]
	tip.text="准备一次持续参战；取消或暂离可退出后续战斗。"
	if model.has_method("loot_pending") and model.loot_pending():tip.text="战利品待ROLL／放弃，60秒超时自动放弃。"
	if p.get("battle_active",false) and not model.active():tip.text="队友正在战斗；本轮未参战，结束后可重新集合。"
	if not confirmation.is_empty():
		_label(confirmation.text)
		_actions([["确认",func()->void:model.submit(confirmation.action,confirmation.id);confirmation={};refresh()],["取消",func()->void:confirmation={};refresh()]])
		return
	for offer in model.state.incoming:
		_label("%s 邀请你加入队伍"%offer.name)
		_actions([["同意",func()->void:model.submit("accept",offer.id)],["拒绝",func()->void:model.submit("reject",offer.id)]])
	if p.is_empty():
		_label("尚未加入任何队伍。\n点击其他玩家资料中的“邀请组队”，或先创建队伍。")
		_actions([["创建队伍",func()->void:model.submit("create")],["刷新",func()->void:model.refresh()]])
		return
	for m in p.members:
		_member(m)
		var actions:Array=[["资料",func()->void:profile_requested.emit(m.id)]]
		if m.id==model.character_id:
			if not m.leader:
				if m.get("following",true):actions.append(["取消准备" if m.ready else "准备",func()->void:model.submit("ready","","",not m.ready)])
				actions.append(["暂离" if m.get("following",true) else "跟随队长",func()->void:model.submit("follow","","",not m.get("following",true))])
		elif p.leader:
			actions.append(["移交",func()->void:confirm("transfer",m.id,"将队长移交给%s？"%m.display_name)])
			actions.append(["移出",func()->void:confirm("kick",m.id,"将%s移出队伍？"%m.display_name)])
		_actions(actions)
	for offer in p.outgoing:
		_label("已邀请%s，等待确认"%offer.name)
		_actions([["取消邀请",func()->void:model.submit("cancel",offer.id)]])
	var actions:Array=[["解散队伍" if p.leader else "退出队伍",func()->void:confirm("disband" if p.leader else "leave","","确定%s当前队伍？"%("解散" if p.leader else "退出"))],["刷新",func()->void:model.refresh()]]
	if model.has_method("loot_pool") and not model.loot_pool().is_empty():actions.append(["战利品",open_loot])
	_actions(actions,footer)
