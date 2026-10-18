extends Control
## Paper and native gold corner ornaments; one scrolling page at phone size.
signal dismissed
signal duel_requested(id: String)
signal team_requested(id:String)
var model: RefCounted
var section := "friends"
var guild_section := "members"
var profile_id := ""
var search: LineEdit
var notice: Label
var title: Label
var scroll: ScrollContainer
var rows: VBoxContainer
var tabs: Dictionary = {}
var preview: AnimatedSprite2D
var confirmation: Panel
var confirmation_text: Label
var confirmation_action: Dictionary = {}
var draft_announcement := ""
var _dirty := false
const BROWN := Color("654518")
const SLOT_NAMES := ["兵器","玉佩","衣装","护腕","腰带","裤子","鞋子","戒指","项链","头盔"]

func style(fill: Color, border: Color=Color("b47b26")) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=fill;s.border_color=border;s.set_border_width_all(1)
	return s

func _ready() -> void:
	z_index=20
	var shade:=ColorRect.new();shade.color=Color(0.02,0.04,0.03,0.65);shade.size=Vector2(320,480);add_child(shade)
	var panel:=OriginalSceneChrome.panel(self,Rect2(8,27,304,421),Color("c17b22"),Color("ffe785"));panel.mouse_filter=MOUSE_FILTER_STOP
	OriginalSceneChrome.panel(panel,Rect2(4,4,296,413),Color("fff1b8"),Color("78501f"))
	title=OriginalSceneChrome.label(panel,"江湖同道",Rect2(12,6,280,24),16,BROWN)
	for i in 4:
		var key: String=["profile","friends","requests","guild"][i]
		var button:=_button(["人物资料","好友","申请","帮派"][i],panel)
		button.position=Vector2(8+i*72,34);button.size=Vector2(72,29);button.pressed.connect(_tab.bind(key));tabs[key]=button
	search=LineEdit.new();search.position=Vector2(9,70);search.size=Vector2(210,30);search.max_length=12;panel.add_child(search)
	search.placeholder_text="输入完整角色名"
	search.add_theme_color_override("font_color",BROWN);search.add_theme_stylebox_override("normal",style(Color("fff8d5")))
	search.add_theme_color_override("font_placeholder_color",Color("927444"))
	search.focus_entered.connect(func()->void: Platform.context.text_input.request_focus(search))
	search.text_submitted.connect(func(_s: String)->void: _search())
	var find:=_button("查找",panel);find.position=Vector2(224,70);find.size=Vector2(71,30);find.pressed.connect(_search)
	scroll=ScrollContainer.new();scroll.position=Vector2(9,106);scroll.size=Vector2(286,242);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	var bar:=scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x=8
	bar.add_theme_stylebox_override("scroll",style(Color("856022")))
	for key in ["grabber","grabber_highlight","grabber_pressed"]:bar.add_theme_stylebox_override(key,style(Color("edc66a")))
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",5);scroll.add_child(rows)
	notice=OriginalSceneChrome.label(panel,"",Rect2(10,352,284,27),11,BROWN);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var refresh:=_button("刷新",panel);refresh.position=Vector2(12,382);refresh.size=Vector2(70,28);refresh.pressed.connect(func()->void: notice.text="正在刷新……";model.fetch("profile",profile_id) if section=="profile" and not profile_id.is_empty() else model.fetch())
	var back:=_button("返回",panel);back.position=Vector2(117,382);back.size=Vector2(70,28);back.pressed.connect(dismiss)
	for i in 4:
		var corner:=TextureRect.new();corner.texture=preload("res://assets/ui/chat_corner.png");corner.size=Vector2(14,14)
		corner.position=Vector2(0 if i%2==0 else 290,0 if i<2 else 407);corner.flip_h=i%2==1;corner.flip_v=i>=2;corner.mouse_filter=MOUSE_FILTER_IGNORE;panel.add_child(corner)
	confirmation=OriginalSceneChrome.panel(self,Rect2(25,172,270,136),Color("fff1b8"),Color("a76619"));confirmation.mouse_filter=MOUSE_FILTER_STOP;confirmation.z_index=2
	confirmation_text=OriginalSceneChrome.label(confirmation,"",Rect2(10,8,250,75),13,BROWN);confirmation_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var yes:=_button("确认",confirmation);yes.position=Vector2(12,93);yes.size=Vector2(100,30)
	yes.pressed.connect(func()->void:
		confirmation.hide()
		_send(String(confirmation_action.action),String(confirmation_action.get("target","")))
	)
	var no:=_button("取消",confirmation);no.position=Vector2(158,93);no.size=Vector2(100,30);no.pressed.connect(func()->void:confirmation.hide())
	confirmation.hide()
	model.changed.connect(_on_changed)
	model.message.connect(func(text: String)->void:notice.text=text)
	_refresh()

func _button(text: String, parent: Node) -> Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size=Vector2(0,30);b.add_theme_font_size_override("font_size",12)
	for k in ["normal","disabled"]:b.add_theme_stylebox_override(k,style(Color("a9661b")))
	for k in ["hover","pressed","focus"]:b.add_theme_stylebox_override(k,style(Color("d59430"),Color("ffe27a")))
	b.add_theme_color_override("font_color",Color("fff4c3"));b.add_theme_color_override("font_disabled_color",Color("cfb077"))
	parent.add_child(b);return b

func open(tab: String="friends", target: String="") -> void:
	section=tab;profile_id=target;confirmation.hide();notice.text="";show()
	scroll.scroll_vertical=0
	if tab=="profile" and not target.is_empty():
		model.profile={}
		if not model.fetch("profile",target):notice.text="正在请求，请稍候再查找。"
	elif model.state.is_empty():model.fetch()
	_refresh()

func dismiss() -> void:
	Platform.context.text_input.release_focus(search)
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit:Platform.context.text_input.release_focus(focus)
	confirmation.hide();hide();dismissed.emit()

func _tab(tab: String) -> void:
	Platform.context.text_input.release_focus(search);section=tab;confirmation.hide();scroll.scroll_vertical=0;_refresh()

func _search() -> void:
	if not Platform.context.text_input.check_submission([search]).ok:return
	Platform.context.text_input.release_focus(search)
	scroll.scroll_vertical=0
	if section=="guild":
		guild_section="directory";model.fetch("guild_browse","",search.text);_refresh()
	else:
		section="profile";profile_id="";model.profile={};model.fetch("find","",search.text);_refresh()

func _on_changed() -> void:
	if section=="profile" and not model.profile.is_empty():profile_id=model.profile.id
	_dirty=true
	if visible:_refresh()

func _process(_delta: float) -> void:
	if visible and _dirty:_refresh()

func _label(text: String, height: float=24) -> Label:
	var label:=Label.new();label.text=text;label.custom_minimum_size=Vector2(260,height);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_color_override("font_color",BROWN);rows.add_child(label);return label

func _actions(values: Array) -> void:
	var row:=HBoxContainer.new();rows.add_child(row)
	for entry in values:
		var button:=_button(entry[0],row);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.disabled=not model.request.is_empty()
		button.pressed.connect(entry[1])

func _send(action: String, target: String="", name: String="", text: String="") -> void:
	if not model.submit(action,target,name,text):notice.text="正在请求，请等待当前操作确认。"
	else:notice.text="正在保存……"

func _confirm(action: String, target: String, caption: String) -> void:
	confirmation_action={"action":action,"target":target};confirmation_text.text=caption;confirmation.show()

func _refresh() -> void:
	if not is_node_ready():return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit and is_ancestor_of(focus):_dirty=true;return
	_dirty=false
	var old_scroll:=scroll.scroll_vertical
	for c in rows.get_children():rows.remove_child(c);c.queue_free()
	preview=null
	for key in tabs:
		tabs[key].add_theme_stylebox_override("normal",style(Color("40c3aa") if key==section else Color("a9661b")))
		tabs[key].add_theme_color_override("font_color",BROWN if key==section else Color("fff4c3"))
	tabs.requests.text="申请(%d)"%model.state.get("incoming",[]).size()
	search.placeholder_text="输入完整帮派名" if section=="guild" else "输入完整角色名"
	title.text="江湖同道 · "+{"profile":"人物资料","friends":"好友","requests":"好友申请","guild":"帮派"}.get(section,"")
	if model.state.is_empty():_label("正在获取江湖关系……")
	elif section=="profile":_profile()
	elif section=="friends":_friends()
	elif section=="requests":_requests()
	else:_guild()
	if model.pending():notice.text="操作结果待确认，自动重试中……"
	scroll.set_deferred("scroll_vertical",old_scroll)

func _person_row(p: Dictionary, suffix: String="") -> void:
	_label("%s · %s Lv.%d · %s%s"%[p.display_name,Game.JOBS[int(p.job)],int(p.level),"在线" if p.online else "离线",suffix],30)

func _friends() -> void:
	_label("好友 %d / 100 · 点击资料可查看装备"%model.state.friends.size())
	if model.state.friends.is_empty():_label("尚未结交好友。可查找角色，或点击地图中的玩家发送申请。",48)
	for p in model.state.friends:
		_person_row(p)
		_actions([["查看资料",func()->void:open("profile",p.id)],["删除好友",func()->void:_confirm("friend_remove",p.id,"确定与%s解除好友关系？"%p.display_name)]])

func _requests() -> void:
	_label("收到的申请")
	if model.state.incoming.is_empty():_label("暂无好友申请。")
	for p in model.state.incoming:
		_person_row(p)
		_actions([["资料",func()->void:open("profile",p.id)],["同意",func()->void:_send("friend_accept",p.id)],["拒绝",func()->void:_send("friend_reject",p.id)]])
	_label("已发出的申请")
	for p in model.state.outgoing:
		_person_row(p)
		_actions([["取消申请",func()->void:_send("friend_remove",p.id)]])

func _profile() -> void:
	var p: Dictionary=model.profile
	if p.is_empty():_label("查找完整角色名，或在地图中点击玩家查看。",45);return
	_person_row(p)
	_label("门派：%s　帮派：%s"%[SchoolRules.label(int(p.school)),p.guild.name if p.guild is Dictionary else "无"])
	var avatar:=Control.new();avatar.custom_minimum_size=Vector2(260,84);rows.add_child(avatar)
	preview=OriginalArt.actor(ShopRules.actor_key(int(p.job),int(p.gender),p.appearance));preview.position=Vector2(140,80);avatar.add_child(preview)
	if p.id!=model.character_id:
		var friend:=false
		for entry in model.state.friends:
			if entry.id==p.id:friend=true
		if friend:_label("已是好友")
		else:_actions([["加为好友",func()->void:_send("friend_request",p.id)]])
		_actions([["邀请决斗",func()->void:duel_requested.emit(p.id);dismiss()]])
		_actions([["邀请组队",func()->void:team_requested.emit(p.id);dismiss()]])
	var c: Dictionary=p.combat
	_label("气血 %d　灵力 %d\n物攻 %d　法攻 %d\n物防 %d　法防 %d\n物暴 %d　法暴 %d\n物命 %d　法命 %d\n物闪 %d　法闪 %d\n减伤 %d"%[c.hp,c.mp,c.physical_attack,c.magic_attack,c.physical_defense,c.magic_defense,c.physical_crit,c.magic_crit,c.physical_hit,c.magic_hit,c.physical_evasion,c.magic_evasion,c.damage_reduction],126)
	_label("已装备物品")
	for i in ShopRules.SLOTS.size():
		var id: Variant=p.equipment[ShopRules.SLOTS[i]]
		var line:=HBoxContainer.new();line.custom_minimum_size=Vector2(0,34);rows.add_child(line)
		var icon:=TextureRect.new();icon.custom_minimum_size=Vector2(28,32);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(icon)
		var item:=ShopRules.bag_item(String(id),int(p.job)) if id!=null else {}
		if not item.is_empty() and ResourceLoader.exists(item.icon):icon.texture=load(item.icon)
		var label:=Label.new();label.text="%s · %s"%[SLOT_NAMES[i],item.get("name","未装备")];label.add_theme_color_override("font_color",BROWN);line.add_child(label)

func _guild() -> void:
	var guild: Variant=model.state.guild
	_actions([["帮派列表",func()->void:guild_section="directory";model.fetch("guild_browse");_refresh()],["我的帮派",func()->void:guild_section="members";model.fetch();_refresh()]])
	if guild_section=="directory":
		_label("按完整帮派名搜索，或申请以下帮派。",34)
		for g in model.state.guilds:
			_label("%s · %d / 50人"%[g.name,int(g.members)])
			if not g.announcement.is_empty():_label(g.announcement,36)
			if guild==null:
				_actions([["取消申请" if g.applied else "申请加入",func()->void:_send("guild_cancel" if g.applied else "guild_apply",g.id)]])
		return
	if guild==null:
		_label("尚未加入帮派。可在帮派列表申请加入，或创建自己的帮派。",48)
		var name:=LineEdit.new();name.placeholder_text="新帮派名（2–12字）";name.max_length=12;name.custom_minimum_size.y=32;rows.add_child(name)
		name.add_theme_color_override("font_color",BROWN);name.add_theme_color_override("font_placeholder_color",Color("927444"));name.add_theme_stylebox_override("normal",style(Color("fff8d5")))
		name.focus_entered.connect(func()->void:Platform.context.text_input.request_focus(name))
		_actions([["免费创建帮派",func()->void:
			if Platform.context.text_input.check_submission([name]).ok:
				Platform.context.text_input.release_focus(name);_send("guild_create","",name.text)
		]])
		return
	_label("%s · %s · %d / 50人"%[guild.name,"帮主" if guild.role=="leader" else "成员",guild.members.size()],30)
	_label("公告："+("暂无公告" if guild.announcement.is_empty() else guild.announcement),48)
	if guild.role=="leader":
		_actions([["成员",func()->void:guild_section="members";_refresh()],["入帮申请(%d)"%guild.applications.size(),func()->void:guild_section="applications";_refresh()],["编辑公告",func()->void:guild_section="announcement";draft_announcement=guild.announcement;_refresh()]])
	if guild_section=="applications" and guild.role=="leader":
		if guild.applications.is_empty():_label("暂无入帮申请。")
		for p in guild.applications:
			_person_row(p)
			_actions([["资料",func()->void:open("profile",p.id)],["同意",func()->void:_send("guild_approve",p.id)],["拒绝",func()->void:_send("guild_reject",p.id)]])
	elif guild_section=="announcement" and guild.role=="leader":
		var input:=LineEdit.new();input.max_length=120;input.text=draft_announcement;input.custom_minimum_size.y=34;rows.add_child(input)
		input.add_theme_color_override("font_color",BROWN);input.add_theme_stylebox_override("normal",style(Color("fff8d5")))
		input.focus_entered.connect(func()->void:Platform.context.text_input.request_focus(input))
		input.text_changed.connect(func(v: String)->void:draft_announcement=v)
		_actions([["保存公告",func()->void:
			if Platform.context.text_input.check_submission([input]).ok:
				Platform.context.text_input.release_focus(input);_send("guild_announce","","",input.text)
		]])
	else:
		for p in guild.members:
			_person_row(p," · 帮主" if p.role=="leader" else "")
			var actions: Array=[["资料",func()->void:open("profile",p.id)]]
			if guild.role=="leader" and p.id!=model.character_id:
				actions.append(["移交",func()->void:_confirm("guild_transfer",p.id,"将帮主移交给%s？你将成为普通成员。"%p.display_name)])
				actions.append(["移除",func()->void:_confirm("guild_kick",p.id,"确定将%s移出帮派？"%p.display_name)])
			_actions(actions)
	if guild.role=="leader":_actions([["解散帮派",func()->void:_confirm("guild_disband","","确定解散帮派？所有成员与申请将被移除。")]])
	else:_actions([["退出帮派",func()->void:_confirm("guild_leave","","确定退出当前帮派？")]])
