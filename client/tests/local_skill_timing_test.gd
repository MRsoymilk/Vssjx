extends Node
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://local_skill_timing_%d.json"%OS.get_process_id()
	for id in ["sheet_010","sheet_018","sheet_007","sheet_035"]:
		await verify_skill(id)
	Game.player=old;Game.save_path=path
	print("LOCAL SKILL TIMING: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
func verify_skill(id:String)->void:
	var skill:=SkillRules.item(id)
	Game.new_player("特效时序",int(skill.job),3);Game.player.level=60;Game.restore()
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false)
	app._enter_world()
	var enemy:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);enemy.hp=100000;enemy.attack=1
	app._start_battle(enemy);app._battle_turn("skill",id)
	var deadline:=Time.get_ticks_msec()+3000
	while app.battle_playback==null and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	var player:BattleActionPlayback=app.battle_playback
	check(player!=null,"Skill starts a native actor action: "+id)
	if player==null:app._home();app.queue_free();return
	check(app.battle_effects._attachments.is_empty(),"Skill effect does not precede its cast impact: "+id)
	player.advance(player.impact_time)
	var sprites:Array[AnimatedSprite2D]=[]
	for entry in app.battle_effects._attachments:
		if is_instance_valid(entry.sprite):
			sprites.append(entry.sprite);entry.sprite.pause()
	check(sprites.size()==BattleEffects.binding(id).layers.size(),"Impact starts every matching native skill layer: "+id)
	player.advance(player.duration)
	app.battle_effects.advance_reactions(BattleDodgePlayback.DURATION) # The app clock is intentionally disabled in this test.
	for frame in 3:await get_tree().process_frame
	check(app.battle_stage=="player" and not app.battle.skills.last_enemy_acted,"Enemy cannot act while the skill effect is still playing: "+id)
	if sprites.size()>1:
		for i in sprites.size()-1:sprites[i].speed_scale=40;sprites[i].play()
		await get_tree().create_timer(0.12).timeout
		check(app.battle_stage=="player","The last layer also belongs to the same skill action: "+id)
	for sprite in sprites:
		if is_instance_valid(sprite):sprite.speed_scale=40;sprite.play()
	deadline=Time.get_ticks_msec()+3000
	while app.battle_stage=="player" and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(app.battle_stage=="enemy" and app.battle_playback!=null and app.battle_playback.actor==app.battle_enemy,"Enemy begins immediately after all skill layers finish: "+id)
	app._home();app.queue_free();await get_tree().process_frame
	# Cancelling during the visual tail must not resume a stale counterattack.
	Game.new_player("取消施法",int(skill.job),3);Game.player.level=60;Game.restore()
	app=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false)
	app._enter_world()
	app._start_battle(enemy);app._battle_turn("skill",id)
	deadline=Time.get_ticks_msec()+3000
	while app.battle_playback==null and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	player=app.battle_playback
	if player!=null:
		player.advance(player.impact_time)
		for entry in app.battle_effects._attachments:entry.sprite.pause()
		player.advance(player.duration)
		app._home()
		for frame in 3:await get_tree().process_frame
		check(app.mode!="battle" and app.battle_playback==null,"Leaving clears the visual wait without a delayed enemy action: "+id)
	app.queue_free();await get_tree().process_frame
