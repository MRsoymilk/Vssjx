class_name EndlessLeaderboard
extends Control
var character_id:=""
var local_mode:=false
var waiting:=false
var entries:Array=[]
var title:Label
var status:Label
var rows:VBoxContainer
var refresh_button:Button
func _ready()->void:
	z_index=30;size=Vector2(320,375);mouse_filter=Control.MOUSE_FILTER_STOP
	theme=preload("res://scenes/ui/online_pve_theme.tres")
	var shade:=ColorRect.new();shade.color=Color(0.04,0.05,0.03,0.65);shade.size=size;add_child(shade)
	var paper:=Panel.new();paper.position=Vector2(6,10);paper.size=Vector2(308,352);add_child(paper)
	var style:=StyleBoxFlat.new();style.bg_color=Color("fff3bc");style.border_color=Color("8f5423");style.set_border_width_all(2);paper.add_theme_stylebox_override("panel",style)
	title=_label(paper,"无尽之路排行榜",Rect2(10,8,288,24));title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status=_label(paper,"",Rect2(12,35,284,35));status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_label(paper,"名次       角色                 职业    通关层数",Rect2(12,75,284,18))
	var scroll:=ScrollContainer.new();scroll.position=Vector2(12,96);scroll.size=Vector2(284,198);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;paper.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",3);scroll.add_child(rows)
	var refresh:=Button.new();refresh.text="刷新";refresh.position=Vector2(18,312);refresh.size=Vector2(122,29);paper.add_child(refresh);refresh.pressed.connect(reload);refresh_button=refresh
	var close:=Button.new();close.text="返回";close.position=Vector2(168,312);close.size=Vector2(122,29);paper.add_child(close);close.pressed.connect(queue_free)
	OnlineAccount.completed.connect(_completed)
func _label(parent:Node,text:String,rect:Rect2)->Label:
	var label:=Label.new();label.text=text;label.position=rect.position;label.size=rect.size;label.add_theme_color_override("font_color",Color("60411e"));label.add_theme_font_size_override("font_size",11);parent.add_child(label);return label
func present(id:String="")->void:
	character_id=id;local_mode=id.is_empty();reload()
func reload()->void:
	if local_mode:
		var members:=Game.local_characters().filter(func(c:Dictionary)->bool:return int(EndlessRules.progress(c).best)>0)
		members.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(EndlessRules.progress(a).best)>int(EndlessRules.progress(b).best) if int(EndlessRules.progress(a).best)!=int(EndlessRules.progress(b).best) else String(a.id)<String(b.id))
		var ranked:Array=[];var own:={"rank":null,"best":0}
		for i in members.size():
			var member:Dictionary=members[i];var row:={"rank":i+1,"character_id":member.id,"display_name":member.name,"job":member.job,"level":member.level,"best":EndlessRules.progress(member).best};ranked.append(row)
			if member.id==Game.active_local_character_id():own={"rank":i+1,"best":row.best}
		title.text="无尽之路 · 本地排行";_render({"entries":ranked,"self":own,"total":ranked.size()});return
	if waiting:return
	if OnlineAccount.busy:status.text="正在同步，请稍后刷新。";return
	waiting=true;refresh_button.disabled=true;status.text="正在读取全服排行榜……";OnlineAccount.endless_board_request(character_id)
static func valid(board:Variant,id:String)->bool:
	if not board is Dictionary or board.get("version")!="endless-board-v1" or board.get("character_id")!=id or not OnlinePve.integer(board.get("total"),0,1000000000) or not board.get("entries") is Array or board.entries.size()!=mini(100,int(board.total)) or not board.get("self") is Dictionary:return false
	var seen:={};var previous:=int(EndlessRules.rules.max_stage)+1
	for i in board.entries.size():
		var row:Variant=board.entries[i]
		if not row is Dictionary or not OnlineWorldClient._uuid(row.get("character_id")) or seen.has(row.character_id) or not OnlinePve.integer(row.get("rank"),i+1,i+1) or not row.get("display_name") is String or not OnlineAccount.valid_nickname(row.display_name) or not OnlinePve.integer(row.get("job"),0,2) or not OnlinePve.integer(row.get("level"),1,60) or not OnlinePve.integer(row.get("best"),1,previous):return false
		previous=int(row.best);seen[row.character_id]=true
	var own:Dictionary=board.self
	if not own.has("rank") or not OnlinePve.integer(own.get("best"),0,int(EndlessRules.rules.max_stage)):return false
	if own.get("rank")==null:return own.best==0 and not seen.has(id)
	if not OnlinePve.integer(own.rank,1,int(board.total)) or int(own.best)==0:return false
	if int(own.rank)<=100:return board.entries[int(own.rank)-1].character_id==id and board.entries[int(own.rank)-1].best==own.best
	return not seen.has(id)
func _completed(action:String,result:Dictionary)->void:
	if action!="endless_board" or not waiting:return
	waiting=false;refresh_button.disabled=false
	if not result.get("ok",false):status.text="读取失败，请刷新重试。";return
	var board:Variant=result.get("leaderboard")
	if not valid(board,character_id):status.text="排行榜数据未同步，请刷新重试。";return
	_render(board)
func _render(board:Dictionary)->void:
	entries=board.entries.duplicate(true)
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var rank:Variant=board.self.rank
	status.text=("我的名次：第%d名 · 最高%d层"%[int(rank),int(board.self.best)] if rank!=null else "尚未通关，暂无排名")+"\n"+("仅本机角色" if local_mode else "全服前100名 · 同层按达成时间排序")
	if entries.is_empty():_label(rows,"暂无通关记录，快去挑战吧！",Rect2(0,0,280,24))
	for entry in entries:
		var row:=HBoxContainer.new();row.custom_minimum_size.y=24;rows.add_child(row)
		for field in [[str(int(entry.rank)),26],[String(entry.display_name),130],[Game.JOBS[int(entry.job)],30],["%d层"%int(entry.best),70]]:
			var label:=Label.new();label.text=field[0];label.tooltip_text=String(entry.display_name)+" · Lv."+str(int(entry.level));label.custom_minimum_size.x=field[1];label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label.clip_text=true;label.add_theme_font_size_override("font_size",11);label.add_theme_color_override("font_color",Color("b04e19") if entry.character_id==(Game.active_local_character_id() if local_mode else character_id) else Color("60411e"));row.add_child(label)
