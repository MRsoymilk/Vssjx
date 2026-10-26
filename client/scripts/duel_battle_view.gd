class_name DuelBattleView
extends OnlineBattleView
var channel: OnlineDuel
var adapter := DuelBattleModel.new()
var opponent: Dictionary = {}
var hero_name: Label
var enemy_name: Label
var waiting_panel: Panel
var waiting_text: Label
var waiting_surrender: Button
var _latest:Dictionary={}
var _queue:Array[Dictionary]=[]
var _playing:Dictionary={}
var _seen_round:=0
var _visual_revision:=0
var _channel_connected:=false
var played_order:Array[String]=[]
const HERO_NAME_HOME := Vector2(210,147)
const ENEMY_NAME_HOME := Vector2(4,138)

func _ready() -> void:
	super._ready()
	hero_name = OriginalSceneChrome.label(self,"",Rect2(HERO_NAME_HOME,Vector2(110,18)),11,Color("613e26"))
	enemy_name = OriginalSceneChrome.label(self,"",Rect2(ENEMY_NAME_HOME,Vector2(110,18)),11,Color("613e26"))
	for tag in [hero_name,enemy_name]:tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	waiting_panel=OriginalSceneChrome.panel(self,Rect2(88,177,144,72),Color("fff3ad"),Color("6c542a"))
	waiting_panel.name="WaitingForOpponent"
	waiting_text=OriginalSceneChrome.label(waiting_panel,"等待对方操作",Rect2(6,9,132,22),13,Color("654518"))
	waiting_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	waiting_surrender=OriginalSceneChrome.button(waiting_panel,"认输",Rect2(47,40,50,23),11)
	waiting_surrender.add_theme_color_override("font_color",Color("8b6c3a"))
	waiting_surrender.pressed.connect(choose.bind("flee"))
	waiting_panel.hide()

func present_duel(duel:OnlineDuel)->void:
	channel=duel;adapter.channel=duel
	var b:Dictionary=duel.state.battle
	_latest=b.duplicate(true)
	var restoring:bool=duel.connected and not _channel_connected and battle_id==b.id
	_channel_connected=duel.connected
	if battle_id!=b.id or restoring:
		_cancel_motion()
		_queue.clear();_playing={};played_order.clear();_visual_revision+=1;_seen_round=int(b.resolved_round)
		adapter.playing=false
		_display(b,b.fighters,"",null,"",true)
	elif int(b.resolved_round)>_seen_round:
		_seen_round=int(b.resolved_round)
		for i in b.events.size():_queue.append({"battle":b.duplicate(true),"event":b.events[i].duplicate(true),"last":i==b.events.size()-1})
		adapter.playing=not _queue.is_empty() or not _playing.is_empty()
		if animation_time<=0 and _playing.is_empty():_next_event()
	elif _queue.is_empty() and _playing.is_empty():
		_display(b,b.fighters,"",null,"",true)
	adapter.ready=duel.connected;adapter.last_code=duel.last_code
	refresh()

func _display(b:Dictionary,fighters:Array,action:String,actor:Variant,used:String,last:bool)->void:
	var me:Dictionary=fighters[0] if fighters[0].id==channel.character_id else fighters[1]
	opponent=fighters[1] if fighters[0].id==channel.character_id else fighters[0]
	var mine:bool=actor==channel.character_id
	var fx:Dictionary=me.effects.duplicate(true)
	fx.last_skill=used if mine else ""
	fx.last_enemy_acted=not mine and action in ["attack","skill"]
	var outcome:String="active" if not last or b.status=="active" else ("victory" if b.winner==channel.character_id else "defeat" if b.winner!=null else "fled")
	var c:={"id":me.id,"display_name":me.name,"job":me.job,"gender":me.gender,"school":me.school,"level":me.level,"hp":me.hp,"mp":me.mp}
	adapter.state={"character":c,"stats":me.stats,"potions":0,"skills":{"available":SkillRules.list_for(int(me.job),int(me.school),int(me.level)).map(func(s:Dictionary)->String:return s.id)},"battle":{"id":b.id,"revision":str(_visual_revision),"round":b.round,"hp":me.hp,"mp":me.mp,"enemy_hp":opponent.hp,"outcome":outcome,"skills":fx,"skill_rules_version":1,"enemy":{"name":opponent.name,"level":opponent.level,"hp":opponent.stats.hp,"attack":opponent.stats.attack,"defense":opponent.stats.defense,"art":ShopRules.actor_key(int(opponent.job),int(opponent.gender),opponent.appearance)}}}
	adapter.last_action=action if mine else "duel_opponent"
	adapter.last_code="";adapter.ready=channel.connected
	hero_name.text=me.name;enemy_name.text=opponent.name
	super.present(adapter)
	_hero_key=ShopRules.actor_key(int(me.job),int(me.gender),me.appearance)
	OriginalArt.apply_appearance(hero,_hero_key)
	if action=="stun":
		animation_time=0.8
		var stunned:AnimatedSprite2D=hero if mine else enemy
		stunned.play("idle")
		move_callout.present_for("眩晕 · 无法行动",stunned,animation_time,Vector2(0,-130))
		refresh()

func _next_event()->void:
	if _queue.is_empty():
		_playing={};adapter.playing=false
		_display(_latest,_latest.fighters,"",null,"",true)
		if channel.can_decide():_open_menu()
		return
	var entry:Dictionary=_queue.pop_front()
	_playing=entry.event
	played_order.append(_playing.actor)
	adapter.playing=true;_visual_revision+=1
	_display(entry.battle,_playing.fighters,_playing.action,_playing.actor,_playing.skill,entry.last)

func _process(delta:float)->void:
	super._process(delta)
	if not visible or channel==null:return
	if channel.connected and not _playing.is_empty() and animation_time<=0:_next_event()

func refresh()->void:
	super.refresh()
	if channel==null or model==null:return
	buttons[3].disabled=true;buttons[3].text="道具禁用"
	buttons[5].text="6 认输"
	buttons[5].disabled=not channel.connected or channel.pending() or not channel.active() or adapter.playing or animation_time>0
	if hero!=null:_follow_level(hero_name,hero,$Hero,HERO_NAME_HOME)
	if enemy!=null:_follow_level(enemy_name,enemy,$Enemy,ENEMY_NAME_HOME)
	status_hero.position=hero_name.position+Vector2((hero_name.size.x-status_hero.size.x)/2,-19)
	status_enemy.position=enemy_name.position+Vector2((enemy_name.size.x-status_enemy.size.x)/2,-19)
	$Hud/AutoButton.hide()
	var was_waiting:=waiting_panel.visible
	waiting_panel.hide()
	if channel.active():
		countdown=maxf(0,(float(_latest.remaining_ms)-(Time.get_ticks_msec()-channel.received_at))/1000.0)
		if not channel.connected:$Hint.text="连接中断，正在恢复决斗……"
		elif adapter.playing or _latest.phase=="resolving":$Hint.text="第%d回合 · 按敏捷结算双方行动"%int(_latest.round)
		elif channel.pending():$Hint.text="正在确认本回合指令……"
		elif not channel.can_decide():$Hint.text="指令已锁定 · 等待对方操作"
		else:
			var me:Dictionary=_latest.fighters[0] if _latest.fighters[0].id==channel.character_id else _latest.fighters[1]
			$Hint.text="第%d回合 · 双方同时决策 · 速度%d"%[int(_latest.round),int(me.speed)]
		if not channel.connected or adapter.playing or animation_time>0 or _latest.phase=="resolving":
			$Hud/ActionMenu.hide();skill_picker.hide();$Choice.hide()
		elif channel.pending() or not channel.can_decide():
			$Hud/ActionMenu.hide();skill_picker.hide();$Choice.hide();$Inspect.hide()
			waiting_text.text="正在确认指令…" if channel.pending() else "等待对方操作"
			waiting_surrender.disabled=buttons[5].disabled
			waiting_panel.show()
		elif was_waiting:
			super._open_menu()
		$Countdown.visible=_latest.phase=="planning" and not adapter.playing
		$Countdown.value=str(maxi(0,ceili(countdown)));$Countdown.queue_redraw()
	else:$Hint.text="切磋不消耗日常血蓝与物品，无胜负奖励。"

	if channel.active() and Time.get_ticks_msec()<_status_notice_until:$Hint.text=_status_notice

func _open_menu()->void:
	# Actor taps and popup close callbacks must respect the locked decision.
	if channel!=null and channel.active() and (not channel.connected or channel.pending() or not channel.can_decide() or adapter.playing or animation_time>0):
		refresh();return
	super._open_menu()

func _status_sources()->Array:
	# enemy_* fields live on their caster in the duel protocol, not the victim.
	var mine:Dictionary=model.state.battle.get("skills",{})
	var theirs:Dictionary=opponent.get("effects",{})
	var hero_rows:=BattleStatusStrip.harmful(theirs);hero_rows.append_array(BattleStatusStrip.beneficial(mine))
	var enemy_rows:=BattleStatusStrip.harmful(mine);enemy_rows.append_array(BattleStatusStrip.beneficial(theirs))
	if _playing.get("action")=="stun" and channel!=null:
		var rows:Array=hero_rows if _playing.actor==channel.character_id else enemy_rows
		if not rows.any(func(row:Dictionary)->bool:return row.id=="stun"):rows.append({"id":"stun","turns":1})
	return [hero_rows,enemy_rows]
func toggle_auto()->void:pass

func choose(action:String)->void:
	if action=="potion":return
	if action=="flee" and channel!=null and channel.connected and not channel.pending() and channel.active() and not adapter.playing and animation_time<=0:
		action_requested.emit("flee");return
	super.choose(action)

func _hero_impact()->void:
	if _hero_motion==null or _hero_motion.cancelled:return
	if _playing.get("missed",false):effects.dodge(enemy,hero)
	effects.number(enemy,int(_playing.get("damage",0)),_playing.get("critical",false))
	effects.number(hero,int(_playing.get("reflected",0)))
	if (model.last_action=="skill" or not _playing.get("missed",false)) and (model.last_action!="skill" or BattleEffects.projectile_seconds(_playing.get("skill",""))<=0):effects.play_action(model.last_action,int(model.state.character.job),_playing.get("skill",""),hero,enemy,int(model.state.battle.skills.get("last_skill_level",1)))
	if _enemy_took_damage and not _playing.get("missed",false) and enemy.sprite_frames.has_animation("hurt"):enemy.play("hurt")
	_shown_hero_hp=int(model.state.battle.hp);_shown_enemy_hp=int(model.state.battle.enemy_hp)
	effects.play_reflection(int(opponent.job),int(opponent.school),int(opponent.level),opponent.effects,model.last_action=="skill" and int(model.state.character.job)==2,enemy,hero)

func _start_enemy_motion()->void:
	_enemy_attack_delay=0
	if not _should_enemy_act():_start_death();return
	var event:Dictionary=_playing.duplicate(true)
	_enemy_motion=BattleActionPlayback.new()
	_enemy_motion.impact.connect(func()->void:
		if _enemy_motion.cancelled:return
		if event.get("missed",false):effects.dodge(hero,enemy)
		effects.number(hero,int(event.get("damage",0)),event.get("critical",false))
		effects.number(enemy,int(event.get("reflected",0)))
		if (event.action=="skill" or not event.get("missed",false)) and (event.action!="skill" or BattleEffects.projectile_seconds(event.skill)<=0):effects.play_action(event.action,int(opponent.job),event.skill,enemy,hero,int(opponent.effects.get("last_skill_level",1)))
		if int(model.state.battle.hp)<_shown_hero_hp and not event.get("missed",false) and hero.sprite_frames.has_animation("hurt"):hero.play("hurt")
		_shown_hero_hp=int(model.state.battle.hp);_shown_enemy_hp=int(model.state.battle.enemy_hp)
		var me:Dictionary=event.fighters[0] if event.fighters[0].id==channel.character_id else event.fighters[1]
		effects.play_reflection(int(me.job),int(me.school),int(me.level),me.effects,event.action=="skill" and int(opponent.job)==2,hero,enemy)
	)
	_enemy_motion.completed.connect(func()->void:if not _enemy_motion.cancelled:_after_reactions(_start_death))
	effects.start_motion(_enemy_motion,event.action,int(opponent.job),event.skill,enemy,OriginalArt.actor_info(model.state.battle.enemy.art),hero,int(opponent.effects.get("last_skill_level",1)))
	move_callout.present_for(ShushanBattle.action_name(event.action,int(opponent.job),event.skill),enemy,_enemy_motion.duration)
	animation_time=_enemy_motion.duration
