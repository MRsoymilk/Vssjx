extends Control
signal dismissed
var model:RefCounted
var actors:Dictionary={}
var battle_id:=""
var revision:=-1
var events_revision:=-1
var selected:="m0"
var actors_layer:Node2D
var menu:Control
var command_toggle:Button
var inspect_panel:Panel
var hint:Label
var caption:Label
var picker:SkillPicker
var effects:BattleEffects
var move_callout:BattleMoveCallout
var _effect_wait:=""
var automatic:=false
var auto_elapsed:=0.0
var solo_countdown:=30.0
var auto_button:Button
var result:BattleResultView
var queue:Array=[]
var motion:BattleActionPlayback
var deaths:Array=[]
var playing:Dictionary={}
var action_buttons:Array[Button]=[]
var target_marker:Node2D
var _closed:=""
func _ready()->void:
	z_index=15
	var field:=OriginalBattleField.new();field.kind="arena";add_child(field)
	target_marker=Node2D.new();add_child(target_marker)
	for i in 4:
		var part:=Sprite2D.new();part.texture=load("res://assets/ui/select_%d.png"%i);part.position=[Vector2(0,-9),Vector2(0,8),Vector2(-15,0),Vector2(15,0)][i];target_marker.add_child(part)
	actors_layer=Node2D.new();add_child(actors_layer)
	effects=BattleEffects.new();add_child(effects)
	move_callout=preload("res://scenes/ui/battle_move_callout.tscn").instantiate();add_child(move_callout)
	caption=OriginalSceneChrome.label(self,"",Rect2(4,3,312,25),12,Color("654518"))
	hint=OriginalSceneChrome.label(self,"",Rect2(4,286,312,29),11,Color("654518"));hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var original_hud:Control=preload("res://scenes/ui/battle_hud.tscn").instantiate()
	menu=original_hud.get_node("ActionMenu");menu.theme=original_hud.theme;original_hud.remove_child(menu);menu.owner=null
	for child in menu.find_children("*","",true,false):child.owner=null
	add_child(menu);original_hud.free();menu.hide()
	var commands:Array=["attack","skill","guard","potion","inspect","flee"]
	for i in 6:
		var button:Button=menu.get_node("BattleButtons%d"%i);action_buttons.append(button);button.pressed.connect(_choose.bind(commands[i]))
	action_buttons[2].text="3 防御";action_buttons[5].text="6 撤退"
	command_toggle=_compact_button("战斗指令",Vector2(84,350))
	command_toggle.pressed.connect(func()->void:menu.visible=not menu.visible)
	auto_button=_compact_button("自动战斗",Vector2(164,350))
	auto_button.hide();auto_button.pressed.connect(_toggle_auto)
	inspect_panel=preload("res://scenes/ui/battle_inspect.tscn").instantiate();add_child(inspect_panel);inspect_panel.size.y=140;inspect_panel.hide()
	var close:=OriginalSceneChrome.button(inspect_panel,"返回",Rect2(57,112,50,24),12);close.add_theme_color_override("font_color",Color("654518"));close.pressed.connect(inspect_panel.hide)
	picker=SkillPicker.new();add_child(picker);picker.position.y=-28;picker.hide();picker.chosen.connect(func(id:String)->void:picker.hide();_send("skill",id));picker.dismissed.connect(picker.hide)
	result=preload("res://scenes/ui/battle_result.tscn").instantiate();add_child(result)
	result.finished.connect(_dismiss);result.get_node("Return").pressed.connect(_dismiss)
	model.changed.connect(present)
func _compact_button(text:String,point:Vector2)->Button:
	var button:Button=preload("res://scripts/social_chrome.gd").placed_button(self,text,Rect2(point,Vector2(72,22)))
	button.custom_minimum_size=Vector2.ZERO
	button.add_theme_font_size_override("font_size",11)
	for state_name in ["normal","hover","pressed","disabled"]:
		var style:StyleBox=button.get_theme_stylebox(state_name).duplicate()
		style.content_margin_top=2;style.content_margin_bottom=2
		button.add_theme_stylebox_override(state_name,style)
	button.size=Vector2(72,22)
	return button
func _dismiss()->void:
	_closed=battle_id;_cancel();hide();dismissed.emit()
func _cancel()->void:
	_effect_wait=""
	if is_instance_valid(move_callout):move_callout.clear()
	if is_instance_valid(effects):effects.clear()
	if motion!=null:motion.cancel()
	motion=null;queue=[]
	for d in deaths:d.cancel()
	deaths=[]
func _clear()->void:
	_cancel()
	for child in actors_layer.get_children():actors_layer.remove_child(child);child.queue_free()
	actors={}
func _actor(id:String,key:String,point:Vector2,enemy:bool)->void:
	var sprite:=OriginalArt.battle_actor(key);sprite.position=point
	if enemy:sprite.scale.x=-1
	actors_layer.add_child(sprite)
	var nameplate:=OriginalSceneChrome.label(self,"",Rect2(0,0,74,15),10,Color("742a22") if enemy else Color("2f593c"));nameplate.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;nameplate.clip_text=true
	var hp:=OriginalSceneChrome.progress(self,Rect2(0,0,48,4),Color("d9f13c"))
	var mp:ProgressBar=null
	if not enemy:mp=OriginalSceneChrome.progress(self,Rect2(0,0,48,3),Color("3bd8ec"))
	var hit:=Button.new();hit.flat=true;hit.size=Vector2(65,65);hit.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;add_child(hit)
	if enemy:hit.pressed.connect(func()->void:selected=id;_refresh_controls();menu.show())
	else:hit.pressed.connect(func()->void:menu.show())
	actors[id]={"sprite":sprite,"key":key,"tag":nameplate,"hp":hp,"mp":mp,"hit":hit,"home":point,"dead":false}
func present()->void:
	if not is_node_ready():return
	if model.has_method("presentation_ready") and not model.presentation_ready():return
	var b:Dictionary=model.battle()
	if b.is_empty():
		if visible:hide();dismissed.emit()
		return
	if b.outcome!="active" and (b.id==_closed or b.id!=battle_id):return
	if b.id!=battle_id:
		for a in actors.values():
			a.tag.queue_free();a.hp.queue_free();a.hit.queue_free()
			if a.mp!=null:a.mp.queue_free()
		_clear();battle_id=b.id;revision=-1;events_revision=int(b.get("events_revision",b.revision));result.reset();selected="m0";menu.hide();inspect_panel.hide();picker.hide()
		for i in b.fighters.size():
			var f:Dictionary=b.fighters[i]
			_actor(f.id,ShopRules.actor_key(int(f.job),int(f.gender),f.appearance),Vector2(220+(i%2)*53,96+floori(float(i)/2)*78+(i%2)*30),false)
		for i in b.enemies.size():
			var e:Dictionary=b.enemies[i]
			_actor(e.slot,e.definition.art,Vector2(44+(i%2)*56,96+floori(float(i)/2)*78+(i%2)*30),true)
	var packet_events:=int(b.get("events_revision",b.revision))
	if events_revision!=packet_events:
		solo_countdown=30.0;auto_elapsed=0.0
		if revision>=0:
			# Play already-authoritative events; never compute damage locally.
			for event in b.events:
				var item:Dictionary=event.duplicate(true);item["packet"]=packet_events;queue.append(item)
		events_revision=packet_events
	revision=int(b.revision)
	var updating:=motion==null and queue.is_empty()
	for f in b.fighters:
		if updating:
			_display(f.id,f.name+" Lv."+str(int(f.level)),int(f.hp),int(f.stats.hp))
			actors[f.id].mp.max_value=f.stats.mp;actors[f.id].mp.value=f.mp
	for e in b.enemies:
		if updating:_display(e.slot,MonsterCombat.enemy_name(e)+" Lv."+str(int(e.definition.level)),int(e.hp),int(e.definition.hp))
	if not actors.has(selected) or actors[selected].dead:
		for e in b.enemies:
			if e.hp>0:selected=e.slot;break
	show();_refresh_controls()
func _display(id:String,text:String,hp:int,max_hp:int)->void:
	if not actors.has(id):return
	var a:Dictionary=actors[id];a.tag.text=text;a.hp.max_value=max_hp;a.hp.value=hp;a.hp.tooltip_text="%s %d/%d"%[text,hp,max_hp]
	a.dead=hp==0
func _choose(action:String)->void:
	if motion!=null or not queue.is_empty() or not _effect_wait.is_empty() or model.pending() or not model.active():return
	if action not in ["inspect","flee"] and not model.my_turn():return
	menu.hide()
	if action=="inspect":
		for e in model.battle().enemies:
			if e.slot==selected:
				inspect_panel.get_node("NameValue").text=MonsterCombat.enemy_name(e)
				inspect_panel.get_node("Hp").text="气血 %d / %d"%[int(e.hp),int(e.definition.hp)]
				inspect_panel.get_node("Secondary").text="攻击 %d　防御 %d"%[int(e.definition.attack),int(e.definition.defense)]
				inspect_panel.get_node("Tertiary").text=("组队强化" if model.battle().fighters.size()>1 else "独自迎战")+" · Lv.%d"%int(e.definition.level);
				if e.has("elite"):inspect_panel.get_node("Tertiary").text="连击·暴击·流血　复活%d次"%int(e.elite.revives_left)
				inspect_panel.show();return
	if action=="skill":
		for f in model.battle().fighters:
			if f.id==model.character_id:picker.present(int(f.job),int(f.school),int(f.level),int(f.mp),[],false,f.stats,f.effects);picker.show();return
	_send(action)
func _send(action:String,skill:String="")->void:
	if action!="flee" and not model.my_turn():return
	model.submit(action,selected if action in ["attack","skill"] else "",skill)
func _refresh_controls()->void:
	var b:Dictionary=model.battle()
	if b.is_empty():return
	var executing:=motion!=null or not queue.is_empty() or not _effect_wait.is_empty()
	caption.text=("精英遭遇" if int(b.get("monster_revision",0))==2 else ("单人遭遇" if b.fighters.size()==1 else "队伍战斗"))+" · 第%d回合 · %d名敌人"%[maxi(1,int(b.round)-(1 if executing and (b.has("commands") or b.get("solo",false)) else 0)),b.enemies.size()]
	var left:=maxi(0,ceili((int(b.deadline_ms)-model.server_time-(Time.get_ticks_msec()-model.received_at))/1000.0))
	var message:="等待确认" if model.pending() else ("轮到你行动" if model.my_turn() else "等待队友")
	if b.has("commands"):
		var alive:=0
		for f in b.fighters:
			if f.hp>0:alive+=1
		message="已提交 %d/%d · %s"%[b.commands.size(),alive,"请选择指令" if model.my_turn() else ("已锁定，等待队友" if b.commands.has(model.character_id) else "等待指令窗口")]
		if motion!=null or not queue.is_empty() or not _effect_wait.is_empty() or model.server_time+Time.get_ticks_msec()-model.received_at<int(b.selection_starts_ms):message="逐个执行中 · 下轮指令共用30秒";left=0
	hint.text=message if left==0 and b.has("commands") else "%s · %d秒"%[message,left]
	if b.get("solo",false):hint.text="逐个行动中" if executing else ("等待确认" if model.pending() else "点击敌人选定目标，再选择指令")
	if b.get("wounds",{}).has(model.character_id):hint.text+=" · 流血%d回合"%int(b.wounds[model.character_id][0])
	for i in action_buttons.size():action_buttons[i].disabled=not model.active() or not model.can_submit() or motion!=null or not queue.is_empty() or not _effect_wait.is_empty() or (not model.my_turn() if i<4 else (not model.party().get("leader",false) if i==5 else false))
	command_toggle.disabled=not model.active() or model.pending() or motion!=null or not queue.is_empty() or not _effect_wait.is_empty()
	auto_button.visible=b.get("solo",false) and model.active()
	command_toggle.position.x=84 if b.get("solo",false) else 124
	auto_button.text="手动战斗" if automatic else "自动战斗"
	auto_button.disabled=model.pending()
	if not model.active():menu.hide();inspect_panel.hide();picker.hide()

func _toggle_auto()->void:
	if not model.active() or not model.battle().get("solo",false):return
	automatic=not automatic;auto_elapsed=0.0;menu.hide();_refresh_controls()

func _unhandled_key_input(event:InputEvent)->void:
	if not visible or not event is InputEventKey or not event.pressed or picker.visible:return
	if event.keycode==KEY_0:_toggle_auto();get_viewport().set_input_as_handled()
	elif event.keycode>=KEY_1 and event.keycode<=KEY_6:
		_choose(["attack","skill","guard","potion","inspect","flee"][event.keycode-KEY_1]);get_viewport().set_input_as_handled()
	elif event.keycode==KEY_ESCAPE:menu.hide();inspect_panel.hide();get_viewport().set_input_as_handled()
func _process(delta:float)->void:
	if not visible:return
	if model.has_method("connected") and not model.connected():_cancel();hint.text="连接中断，正在恢复战斗……";return
	move_callout.update_anchor()
	if not _effect_wait.is_empty():
		if effects.has_skill_effects(_effect_wait):return
		_effect_wait=""
		_start_deaths()
	if motion!=null:
		motion.advance(delta)
		if not motion.active:
			if playing.get("action")=="skill" and effects.has_skill_effects(playing.get("skill","")):_effect_wait=playing.skill
			motion=null
			if _effect_wait.is_empty():_start_deaths()
	elif not queue.is_empty():
		var waiting:=false
		if queue[0].action=="revive":
			for death in deaths:
				if death.actor==actors[queue[0].actor].sprite and death.active:waiting=true
		if not waiting:_play(queue.pop_front())
	else:
		_sync_final_resources()
		_start_deaths()
		if not model.active() and not model.battle().is_empty() and not model.pending() and deaths.all(func(d:BattleDeathPlayback)->bool:return not d.active):
			var details:="\n".join(PackedStringArray(model.battle().get("lines",[])))
			var saved:=true
			if model is SoloEncounter and model.pve==null and model.save_result!=null:saved=model.save_result.ok
			result.present(model.battle().outcome,details,saved)
	for death in deaths:death.advance(delta)
	for a in actors.values():
		a.tag.position=a.sprite.position+Vector2(-37,-67);a.hp.position=a.sprite.position+Vector2(-24,-50);a.hit.position=a.sprite.position-Vector2(32,60)
		if a.mp!=null:a.mp.position=a.sprite.position+Vector2(-24,-44)
	target_marker.visible=actors.has(selected) and not actors[selected].dead
	if target_marker.visible:target_marker.position=actors[selected].sprite.position+Vector2(0,4)
	_refresh_controls()
	if model.battle().get("solo",false) and model.my_turn() and motion==null and queue.is_empty() and _effect_wait.is_empty() and not picker.visible:
		solo_countdown=maxf(0,solo_countdown-delta);auto_elapsed+=delta
		if automatic and auto_elapsed>=1.4:
			auto_elapsed=0
			var command:Dictionary=model.auto_command() if model.has_method("auto_command") else {"action":"attack","skill":""}
			_send(command.action,command.skill)
		elif solo_countdown==0:solo_countdown=30;_send("guard")
func _sync_final_resources()->void:
	var b:Dictionary=model.battle()
	if b.is_empty():return
	for f in b.fighters:
		_display(f.id,f.name+" Lv."+str(int(f.level)),int(f.hp),int(f.stats.hp))
		actors[f.id].mp.max_value=f.stats.mp;actors[f.id].mp.value=f.mp
	for e in b.enemies:_display(e.slot,MonsterCombat.enemy_name(e)+" Lv."+str(int(e.definition.level)),int(e.hp),int(e.definition.hp))
	if not actors.has(selected) or actors[selected].dead:
		for e in b.enemies:
			if int(e.hp)>0:selected=e.slot;break
func _start_deaths()->void:
	for a in actors.values():
		if a.dead and a.sprite.visible:
			var death:=BattleDeathPlayback.new();death.start(a.sprite);deaths.append(death)
func _play(event:Dictionary)->void:
	if not actors.has(event.actor) or not actors.has(event.target):return
	var a:Dictionary=actors[event.actor];var target:Dictionary=actors[event.target]
	if event.action=="revive":
		for death in deaths.duplicate():
			if death.actor==a.sprite:death.cancel();deaths.erase(death)
		a.sprite.show();a.sprite.play("idle");a.dead=false;a.hp.value=int(event.healed)
		effects.number(a.sprite,int(event.healed),false,true);effects.attach("effect/flash",a.sprite)
		motion=BattleActionPlayback.new();motion.start(a.sprite,OriginalArt.actor_info(a.key),a.sprite.global_position,&"idle",a.sprite)
		playing=event;move_callout.present_for("妖躯复生",a.sprite,motion.duration)
		return
	if not a.sprite.visible:return
	if event.action not in ["attack","skill","guard","potion","dot","regen"]:return
	playing=event
	var group:Array=[event]
	while event.action=="skill" and not queue.is_empty() and queue[0].actor==event.actor and queue[0].target!=event.target and queue[0].skill==event.skill and queue[0].get("packet")==event.get("packet"):
		group.append(queue.pop_front())
	var mode:StringName=&"cast" if event.action=="skill" and a.sprite.sprite_frames.has_animation("cast") else &"attack"
	if event.action in ["guard","potion","dot","regen"]:mode=&"idle"
	if event.action=="skill" and not SkillRules.item(event.skill).is_empty() and SkillRules.item(event.skill).get("damage_percent",0)==0:mode=&"cast" if a.sprite.sprite_frames.has_animation("cast") else &"idle"
	motion=BattleActionPlayback.new()
	motion.impact.connect(func()->void:
		for hit in group:
			var receiver:Dictionary=actors[hit.target]
			receiver.hp.value=maxf(0,receiver.hp.value-int(hit.damage));receiver.dead=receiver.hp.value<=0
			var healer:Dictionary=a if hit.actor!=hit.target and SkillRules.item(hit.get("skill","")).get("target")!="all_allies" else receiver
			healer.hp.value=minf(healer.hp.max_value,healer.hp.value+int(hit.healed));healer.dead=healer.hp.value<=0
			effects.number(receiver.sprite,int(hit.damage),hit.get("critical",false))
			effects.number(a.sprite if hit.actor!=hit.target and SkillRules.item(hit.get("skill","")).get("target")!="all_allies" else receiver.sprite,int(hit.healed),false,true)
			if hit.action=="skill":effects.play_binding(hit.skill,"cast_impact",receiver.sprite if SkillRules.item(hit.skill).get("target")=="all_allies" else a.sprite,receiver.sprite,hit==group[0])
			elif hit.action=="attack":effects.attach("effect/flash",receiver.sprite)
			if int(hit.damage)>0 and receiver.sprite.sprite_frames.has_animation("hurt"):receiver.sprite.play("hurt")
	)
	motion.start(a.sprite,OriginalArt.actor_info(a.key),target.sprite.global_position,mode,target.sprite)
	if String(event.skill).begins_with("monster_"):move_callout.present_for("流血" if event.skill=="monster_bleed" else MonsterCombat.action_name(event.skill),a.sprite,motion.duration)
	elif event.action=="skill":move_callout.present_for(SkillRules.item(event.skill).get("name",""),a.sprite,motion.duration)

func _exit_tree()->void:_cancel()
