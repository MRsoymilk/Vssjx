extends Node
var checks := 0
var failures := 0
var capture_dir := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RESULT FAIL: " + message)

func _ready() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name()=="headless": return
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(capture_dir+"/"+name+".png")==OK,"Capture actual battlefield "+name)

func _run() -> void:
	capture_dir=OS.get_environment("SSJX_BATTLE_ORIGINAL_CAPTURE")
	var saved:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	Game.save_path="user://battle_result_%d.json"%OS.get_process_id()
	var app:Control=load("res://scenes/main.tscn").instantiate()
	add_child(app);app.set_process(false)
	for victory in [true,false]:
		Game.new_player("结算检查",1,0,1)
		app._enter_world();app._start_battle(ShushanWorld.ENEMIES[0])
		app.battle.finished=true;app.battle.phase="finished";app.battle.victory=victory
		app.battle.hp=95 if victory else 0
		app.battle.enemy_hp=0 if victory else 62
		await app._battle_result()
		var result:BattleResultView=app.battle_result
		result.set_process(false)
		check(result.visible and result.glyph.get_meta("art_key")==BattleResultView.ART_KEYS[0 if victory else 1],"Local outcome uses corresponding original ANI")
		check(result.glyph.sprite_frames.get_frame_count("source_0")==2 and is_equal_approx(result.glyph.sprite_frames.get_frame_duration("source_0",0),2.0),"Both original frames retain native two-tick durations")
		check(result.glyph.offset==Vector2(-30,-37) if victory else result.glyph.offset==Vector2(-32,-37),"Original glyph offsets survive atlas baking")
		var gold:int=Game.player.gold
		await app._battle_result()
		check(Game.player.gold==gold and app.battle_result==result,"Repeated settlement neither duplicates rewards nor restarts the animation")
		check(not result.can_return(),"An accidental last attack tap cannot dismiss the new result")
		await capture("local-victory" if victory else "local-defeat")
		result.advance(BattleResultView.DISPLAY_SECONDS)
		check(app.mode=="world" and app.modal==null,"Local result automatically returns to the map after animation")
		check(app._local_messages[-1].channel=="system" and app._local_messages[-1].text.contains("战斗结束"),"Result survives map return in local system history")
	app.free()
	# Authoritative snapshots govern every outcome. Presentation cannot mutate them.
	var model:=OnlinePve.new();model.ready=true
	model.state={"character":{"job":1,"school":0,"gender":1,"level":1,"hp":95,"mp":40,"display_name":"结算检查"},"stats":{"hp":100,"mp":40},"potions":6}
	var view:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate()
	add_child(view);view.set_process(false)
	var dismissed:Array=[];view.dismissed.connect(func()->void:dismissed.append(true))
	for outcome in ["victory","defeat","fled"]:
		model.state.battle={"id":outcome,"revision":"1","round":1,"outcome":outcome,"enemy_hp":0 if outcome=="victory" else 62,"hp":0 if outcome=="defeat" else 95,"mp":40,"enemy":{"art":"monster/langw","name":"山狼","level":1,"hp":62,"attack":13,"defense":3}}
		var original:=model.state.duplicate(true)
		view.present(model)
		if view.animation_time>0:
			check(not view.get_node("Result").visible,"Death ANI completes before the result glyph")
			view._process(view.animation_time)
		var result:BattleResultView=view.get_node("Result")
		check(result.visible and (result.glyph!=null)==(outcome!="fled"),"Victory/defeat use their own glyph; retreat does not masquerade as defeat")
		view._process(0.45)
		var elapsed:=result.elapsed
		view.present(model)
		check(result.elapsed==elapsed,"Repeated server snapshot does not restart result playback")
		model.ready=false;view._process(0.7)
		check(result.elapsed==elapsed and not result.can_return(),"Disconnect pauses automatic return and blocks taps")
		model.ready=true;view.present(model)
		if view.animation_time>0:view._process(view.animation_time)
		await capture("online-"+outcome)
		view._process(BattleResultView.DISPLAY_SECONDS)
		check(not view.visible and dismissed.size()==["victory","defeat","fled"].find(outcome)+1,"Online outcome returns automatically exactly once")
		check(model.state==original,"Result animation never writes authoritative rewards, HP or progress")
	view.free()
	# Touch row, keyboard confirmation, shortages and repeated taps share one picker.
	var picker:=SkillPicker.new();add_child(picker)
	var chosen:Array=[];picker.chosen.connect(func(id:String)->void:chosen.append(id))
	picker.present(0,2,60,9)
	picker.activate("sheet_011")
	check(chosen.is_empty() and picker.description.text.contains("灵力不足"),"Unaffordable touch row only explains shortage and spends no turn")
	picker.activate("sheet_010");picker.activate("sheet_010")
	check(chosen==["sheet_010"],"A direct row tap submits exactly one eligible skill")
	picker.present(0,2,60,100)
	picker._select("sheet_011")
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_ENTER
	picker._unhandled_key_input(key)
	check(chosen==["sheet_010","sheet_011"],"Keyboard confirms the highlighted skill without an extra confirmation window")
	picker.present(0,2,60,100,[],true)
	check(picker.choices.size()==1 and picker.choices[0].id=="legacy_0","Older capability uses same native list restricted to the supported skill")
	picker.queue_free()
	if FileAccess.file_exists(Game.save_path):DirAccess.remove_absolute(Game.save_path)
	Game.save_path=old_path;Game.player=saved
	print("BATTLE RESULT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
