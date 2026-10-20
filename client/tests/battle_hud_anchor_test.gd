extends "res://tests/team_test.gd"
func body_center(a:Dictionary,view:Control)->Vector2:
	var info:=OriginalArt.actor_info(a.key)
	var origin:=Vector2(float(info.origin[0])-float(info.get("anchor_x",0)),float(info.origin[1]))
	# The composite atlas stabilizes the head; battle offsets restore its source translation.
	var head:=Vector2(a.sprite.offset.x-origin.x,0)
	return view.get_global_transform_with_canvas().affine_inverse()*(a.sprite.get_global_transform_with_canvas()*head)
func verify(a:Dictionary,view:Control,context:String)->void:
	var center:=body_center(a,view)
	check(absf(a.hp.position.x+a.hp.size.x/2-center.x)<0.01,context+": HP is centered on rendered character")
	check(absf(a.mp.position.x+a.mp.size.x/2-center.x)<0.01,context+": MP shares character center")
	check(absf(a.tag.position.x+a.tag.size.x/2-center.x)<0.01,context+": Name shares character center")
func _run()->void:
	await Platform.when_ready()
	var saved:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	var model:=OnlineTeamModel.new();model.bind_character(SELF);model.state=state(encounter())
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present()
	var hero:Dictionary=view.actors[SELF]
	view._process(0)
	verify(hero,view,"Idle before any movement")
	for facing in [1.0,-1.0]:
		hero.sprite.scale.x=facing
		view._play({"actor":SELF,"target":"m0","action":"attack","skill":"","damage":1,"healed":0,"critical":false})
		for step in 6:
			view._process(view.motion.duration/8.0)
			verify(hero,view,"Equipped attack %d facing %d"%[step,int(facing)])
		view._cancel();view._process(0);verify(hero,view,"Cancelled attack restores anchor")
	# Actor roots and UI use different transforms; text/bar widths remain upright.
	view.actors_layer.position=Vector2(17,9);view.actors_layer.scale=Vector2(1.1,0.9)
	view._process(0);verify(hero,view,"Scaled and translated actor layer")
	view._play({"actor":SELF,"target":"m0","action":"attack","skill":"","damage":1,"healed":0,"critical":false})
	view._process(view.motion.duration);verify(hero,view,"Natural completion restores anchor")
	# Native FX can hold the queue while the actor returns or changes animation.
	view._effect_wait="sheet_010";view.effects.play_binding("sheet_010","cast_impact",hero.sprite,view.actors.m0.sprite)
	hero.sprite.position+=Vector2(13,0);view._process(0);verify(hero,view,"HUD remains current during FX tail wait")
	view._cancel();view.actors_layer.position=Vector2.ZERO;view.actors_layer.scale=Vector2.ONE;hero.sprite.scale.x=1;hero.sprite.position=hero.home;view._process(0)
	if DisplayServer.get_name()!="headless":
		view._play({"actor":SELF,"target":"m0","action":"attack","skill":"","damage":1,"healed":0,"critical":false})
		view._process(view.motion.duration*0.42)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../work/battle-hud-anchor.png")
	view._cancel();view.queue_free();await get_tree().process_frame;OnlineAccount.pending_team=saved
	await get_tree().create_timer(0.25).timeout
	print("BATTLE HUD ANCHOR: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
