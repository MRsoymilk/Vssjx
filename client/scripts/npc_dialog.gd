class_name OriginalNpcDialog
extends Control
## Paper NPC option list follows the supplied gameplay video's reference frame 11.
signal action_requested(action: String, target: String)
signal dismissed
var target := ""
var model: OnlinePve
var approaching := false
var ai_mode := false
var local_mode := false
var ai_state: Dictionary = {}
var character_level := 1
var selected_action := ""
var selected_target := ""
var extra_buttons: Array[Button] = []
@onready var quest_button: Button = $Paper/Quest
@onready var restore_button: Button = $Paper/Restore
@onready var hint: Label = $Paper/Hint
@onready var restore_caption:String=$Paper/Restore.text

func _ready() -> void:
	$Dismiss.pressed.connect(dismiss)
	quest_button.pressed.connect(func() -> void:
		if quest_button.disabled:return
		if target==EndlessRules.rules.npc.id:action_requested.emit("endless",target);return
		if ai_mode:action_requested.emit(selected_action,selected_target)
		else:action_requested.emit("accept" if _legacy_stage()==0 else "claim",target)
	)
	restore_button.pressed.connect(func() -> void:
		if target==EndlessRules.rules.npc.id:
			if not has_node("EndlessLeaderboard"):
				var board:=EndlessLeaderboard.new();board.name="EndlessLeaderboard";add_child(board);board.present("" if local_mode else model.character_id)
			return
		if not restore_button.disabled: action_requested.emit("ai_restore" if ai_mode else "restore", target)
	)

func present(id: String, resident: Dictionary, pve: OnlinePve) -> void:
	target = id
	model = pve
	ai_mode=false;local_mode=false
	approaching = false
	$Paper/Name.text = resident.name
	$Paper/Greeting.text = "小友，山中妖物惊扰行人。"
	_reset_paper()
	show()
	refresh()

func present_local(resident: Dictionary) -> void:
	target=String(resident.get("id","qingwei"));model=null;ai_mode=false;local_mode=true;approaching=false
	$Paper/Name.text=resident.name;$Paper/Greeting.text="小友，山中妖物惊扰行人。"
	_reset_paper();show();refresh()

func present_ai(id: String, resident: Dictionary, state: Dictionary, level: int, pve: OnlinePve = null) -> void:
	target=id;model=pve;ai_mode=true;local_mode=pve==null;ai_state=state;character_level=level;approaching=false
	$Paper/Name.text=String(resident.name)+" · AI支线"
	$Paper/Greeting.text=resident.get("dialogue","此地驿路仍需修士照应。")
	show();refresh()

func _clear_extras() -> void:
	for button in extra_buttons:
		button.get_parent().remove_child(button);button.queue_free()
	extra_buttons.clear()

func _reset_paper() -> void:
	_clear_extras()
	restore_button.text=restore_caption
	$Paper.position=Vector2(6,125);$Paper.size=Vector2(308,157)
	$Paper/Greeting.autowrap_mode=TextServer.AUTOWRAP_OFF
	$Paper/Greeting.position.y=34;$Paper/Greeting.size.y=20
	$Paper/Rule.position.y=59;quest_button.position.y=66;restore_button.position.y=96;hint.position.y=130
	$Paper/BL.position.y=143;$Paper/BR.position.y=143
	quest_button.show();restore_button.show()

func _legacy_stage() -> int:
	return int(Game.player.get("quest",0)) if local_mode else int(model.state.character.quest_stage)

func _locked() -> bool:
	return Game.storage_busy or approaching or Game.local_battle_active() or Game.is_soul() if local_mode else model==null or not model.ready or model.pending() or model.active() or model.is_soul() or approaching

func _restore_full() -> bool:
	if local_mode:
		var stats := Game.stats()
		return int(Game.player.hp)==int(stats.hp) and int(Game.player.mp)==int(stats.mp)
	return int(model.state.character.hp)==int(model.state.stats.hp) and int(model.state.character.mp)==int(model.state.stats.mp)

func allows(action: String, destination: String) -> bool:
	if not visible or _locked():return false
	if target==EndlessRules.rules.npc.id:return action=="endless" and destination==target and not quest_button.disabled
	if action in ["gourd_refill_hp","gourd_refill_mp"]:
		return destination==target and (target=="qingwei" or target.ends_with("_guide")) and _can_refill(GourdRules.refill_id(action))
	if action=="school_join":return not ai_mode and target=="qingwei" and _school()==SchoolRules.UNJOINED and SchoolRules.index(destination)>=0
	if action==("ai_restore" if ai_mode else "restore"):return destination==target and restore_button.visible and not restore_button.disabled
	if not ai_mode:return destination==target and action==("accept" if _legacy_stage()==0 else "claim") and not quest_button.disabled
	for option in AIWorld.npc_options(target,ai_state,character_level):
		if option.action==action and option.target==destination and not option.disabled:return true
	return false

func refresh() -> void:
	if target==EndlessRules.rules.npc.id:_refresh_endless();return
	if ai_mode:_refresh_ai();return
	if not local_mode and (model == null or model.state.is_empty()): return
	_reset_paper()
	var stage := _legacy_stage()
	var kills := int(Game.player.get("kills",0)) if local_mode else int(model.state.progress.kills)
	quest_button.text = ["! 山林试炼（接受）", "[已接] 山林试炼（%d/3）" % kills, "! 山林试炼（完成）", "[完成] 山林试炼"][mini(stage, 3)]
	var locked := _locked()
	quest_button.disabled = locked or stage == 1 or stage >= 3
	var full := _restore_full()
	restore_button.disabled = locked or full
	hint.text = "点击任务项接受或完成任务。" if stage in [0, 2] else ("击败山狼后，回来完成试炼。" if stage == 1 else "试炼已完成。")
	if local_mode:
		if locked:hint.text="正在保存，请稍候……"
		_refresh_school(locked)
		_refresh_gourds()
		return
	if not model.ready: hint.text = "连接中断，正在同步任务结果……"
	elif approaching: hint.text = "正在与道人交谈……"
	elif model.pending():
		var action: String = OnlineAccount.pending_pve.command.action
		hint.text = {"accept":"正在接受任务……", "claim":"正在完成任务……", "restore":"正在恢复元气……","school_join":"正在确认入派……"}.get(action, "正在等待回复……")
	elif model.last_action in ["accept", "claim", "restore"] and not model.last_code.is_empty(): hint.text = OnlinePve.error_text(model.last_code)
	_refresh_school(locked)
	_refresh_gourds()
	if model.last_action in GourdRules.ACTIONS and not model.last_code.is_empty():hint.text=OnlinePve.error_text(model.last_code)
	if model.last_action=="school_join" and not model.last_code.is_empty():hint.text=OnlinePve.error_text(model.last_code)

func _refresh_endless()->void:
	_reset_paper();restore_button.text="无尽之路排行榜";restore_button.position.y=126;restore_button.disabled=false
	$Paper/Name.text=String(EndlessRules.rules.npc.name)+" · 无尽试炼"
	$Paper/Greeting.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	$Paper/Greeting.text="一层更比一层强。胜利后继续，失败或撤退结束本轮，最高纪录保留。"
	$Paper/Greeting.size=Vector2(284,48);$Paper/Rule.position.y=86;quest_button.position.y=94
	$Paper.size.y=237;$Paper.position.y=75;hint.position.y=159;hint.size=Vector2(284,63);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	$Paper/BL.position.y=223;$Paper/BR.position.y=223
	var supported:bool=local_mode or (model!=null and model.state.has("endless"))
	var progress:Dictionary=EndlessRules.progress(Game.player) if local_mode else (model.state.get("endless",{}).get("progress",EndlessRules.empty()) if model!=null else EndlessRules.empty())
	quest_button.text="挑战第%d层 · 最高已过%d层"%[int(progress.stage),int(progress.best)]
	quest_button.disabled=_locked() or not supported or progress.in_progress or (Game.is_soul() if local_mode else model.is_soul())
	hint.text="每层：气血+20%／攻击+10%／防御+8%（按首层基数）。仅携带已开启的葫芦可战后自动补给。"
	if not supported:hint.text="当前服务器尚未开放无尽试炼，请等待服务器更新。"
	elif not local_mode and not model.last_code.is_empty() and model.last_action=="endless":hint.text=OnlinePve.error_text(model.last_code)
	elif _locked():hint.text="正在准备试炼，请稍候……"

func _school() -> int:
	return int(Game.player.get("school",SchoolRules.UNJOINED)) if local_mode else int(model.state.character.get("school",SchoolRules.UNJOINED))

func _refresh_school(locked: bool) -> void:
	if target!="qingwei" or _school()!=SchoolRules.UNJOINED:return
	for index in 3:
		var button:Button=quest_button.duplicate(0)
		$Paper.add_child(button);extra_buttons.append(button)
		button.position=Vector2(12,126+index*30);button.size=Vector2(284,27)
		button.text="拜入%s（入派并传送）"%SchoolRules.label(index)
		button.disabled=locked
		button.pressed.connect(func()->void:
			if not button.disabled:action_requested.emit("school_join",SchoolRules.TARGETS[index]))
	$Paper.position.y=64;$Paper.size.y=247
	hint.position.y=220
	$Paper/BL.position.y=233;$Paper/BR.position.y=233
	if not locked:hint.text="入派后自动前往门派驻地；技能仍按职业和等级开放。"

func _refresh_ai() -> void:
	_clear_extras()
	if model!=null and model.state.is_empty():
		quest_button.disabled=true;restore_button.disabled=true;hint.text="正在同步任务结果……";return
	if model!=null:
		ai_state=model.state.get("ai_world",{})
		character_level=int(model.state.get("character",{}).get("level",character_level))
	elif local_mode:ai_state=AIWorld.progress();character_level=int(Game.player.level)
	var options := AIWorld.npc_options(target,ai_state,character_level)
	var locked := _locked()
	var greeting: Label=$Paper/Greeting
	greeting.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var measured: Vector2=greeting.get_theme_font("font").get_multiline_string_size(greeting.text,HORIZONTAL_ALIGNMENT_LEFT,284,greeting.get_theme_font_size("font_size"))
	var greeting_height := clampf(ceilf(measured.y)+2,20,72)
	greeting.position.y=34;greeting.size=Vector2(284,greeting_height)
	$Paper/Rule.position.y=34+greeting_height+5
	var y: float=$Paper/Rule.position.y+7
	quest_button.visible=not options.is_empty()
	for i in options.size():
		var option: Dictionary=options[i]
		var button: Button=quest_button if i==0 else quest_button.duplicate(0)
		if i==0:selected_action=option.action;selected_target=option.target
		else:
			$Paper.add_child(button);extra_buttons.append(button)
			button.pressed.connect(func()->void:
				if not button.disabled:action_requested.emit(option.action,option.target))
		button.text=option.text;button.clip_text=true;button.tooltip_text=option.text
		button.position=Vector2(12,y);button.size=Vector2(284,27);button.disabled=locked or option.disabled
		y+=30
	restore_button.visible=target.ends_with("_guide")
	if restore_button.visible:
		restore_button.position=Vector2(12,y);restore_button.disabled=locked or _restore_full();y+=30
		y=_gourd_buttons(y)
	hint.position=Vector2(12,y+4);hint.size=Vector2(284,24)
	hint.text="点击任务项接受或完成任务。" if not options.is_empty() else "此刻没有需办理的任务。"
	if local_mode and locked:hint.text="正在保存，请稍候……"
	elif model!=null:
		if not model.ready:hint.text="连接中断，正在同步任务结果……"
		elif approaching:hint.text="正在与人物交谈……"
		elif model.pending():hint.text="正在等待任务结果……"
		elif model.last_action.begins_with("ai_") and not model.last_code.is_empty():hint.text=OnlinePve.error_text(model.last_code)
		elif model.last_action in GourdRules.ACTIONS and not model.last_code.is_empty():hint.text=OnlinePve.error_text(model.last_code)
	var height := y+31
	$Paper.position=Vector2(6,(375-height)/2);$Paper.size=Vector2(308,height)
	$Paper/BL.position.y=height-14;$Paper/BR.position.y=height-14

func _gourds()->Dictionary:
	return Game.player.get("gourds",{}) if local_mode else model.state.get("gourds",{})

func _can_refill(id:String)->bool:
	var s:Dictionary=_gourds().get(id,{})
	return not s.is_empty() and int(s.remaining)<int(ShopRules.item(id).capacity)

func _gourd_buttons(y:float)->float:
	for id in GourdRules.IDS:
		var button:Button=quest_button.duplicate(0)
		$Paper.add_child(button);extra_buttons.append(button)
		button.name="RefillHp" if id==GourdRules.HP else "RefillMp"
		button.position=Vector2(12,y);button.size=Vector2(284,27);button.show()
		button.text="补满%s · 免费"%ShopRules.item(id).name
		if not _gourds().has(id):button.text+="（未购买）"
		elif not _can_refill(id):button.text+="（已满）"
		button.disabled=_locked() or not _can_refill(id)
		var action:="gourd_refill_hp" if id==GourdRules.HP else "gourd_refill_mp"
		button.pressed.connect(func()->void:
			if allows(action,target):action_requested.emit(action,target))
		y+=30
	return y

func _refresh_gourds()->void:
	if target!="qingwei":return
	var y:=_gourd_buttons(hint.position.y-4)
	hint.position.y=y+4
	$Paper.size.y=y+31;$Paper.position.y=maxf(6,(375-$Paper.size.y)/2)
	$Paper/BL.position.y=$Paper.size.y-14;$Paper/BR.position.y=$Paper.size.y-14

func dismiss() -> void:
	if local_mode and Game.storage_busy:return
	if has_node("EndlessLeaderboard"):get_node("EndlessLeaderboard").queue_free()
	hide()
	dismissed.emit()
