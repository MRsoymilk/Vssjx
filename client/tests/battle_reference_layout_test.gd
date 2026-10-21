extends "res://tests/team_test.gd"
func render(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://../work/battle-reference-"+name+".png")==OK,"Capture "+name)
func _run()->void:
	await Game.when_ready()
	var old_path:=Game.save_path;Game.save_path="user://battle_reference_%d.json"%OS.get_process_id()
	var old:=Game.player.duplicate(true);var saved:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	Game.new_player("原版布局",1,3);Game.player.level=5;Game.restore()
	var boss:Dictionary=SharedWorldMap.population("ai_001").filter(func(d:Dictionary)->bool:return d.kind=="boss")[0].duplicate(true);boss.hp=10000
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world();app._start_local_encounter([boss])
	var view:Control=app.local_encounter_view;view.set_process(false);view._process(0)
	check(view.menu.visible and view.menu.position.x+view.menu.size.x/2==160,"Single encounter opens centered original commands")
	check(view.countdown.visible and view.countdown.value=="30","Single encounter restores the green countdown")
	check(not view.caption.visible and not view.hint.visible,"Normal encounter removes duplicate heading and instructions")
	check(view.actors.m0.home.y>220 and view.actors[app.local_encounter.character_id].home.y>220,"Both actors return to the middle of the arena")
	check(view.actors.m0.tag.position.y+view.actors.m0.tag.size.y<view.actors.m0.home.y-96,"Large boss name stays above its silhouette")
	check(view.action_buttons[2].text=="3 待机" and view.action_buttons[5].text=="6 逃跑","Reference labels retain existing guard and flee actions")
	view.action_buttons[3].mouse_entered.emit();check(view.menu_cursor.position.y==106,"Original hand pointer follows the selected command")
	view._highlight(0)
	await render("single")
	view._choose("skill");view._process(0)
	check(view.picker.visible and not view.menu.visible,"Skill picker replaces rather than overlaps commands")
	view.picker.dismissed.emit();view._process(0)
	check(view.menu.visible,"Cancelling skill selection restores commands")
	view._toggle_auto();view._process(0)
	check(not view.menu.visible and view.auto_button.text=="手动战斗","Auto mode hides commands and retains short manual label")
	view._toggle_auto();view._process(0)
	view._choose("guard");view._process(0)
	check(not view.menu.visible and not view.countdown.visible,"Playback hides both menu and input countdown")
	view._cancel();app._home();app.queue_free();await get_tree().process_frame
	var chrome:Control=load("res://scenes/ui/battle_chrome.tscn").instantiate();add_child(chrome);chrome.update_header(int(Game.player.hp),int(Game.player.mp),0)
	var model:=OnlineTeamModel.new();model.bind_character(SELF);model.server_time=10000;model.received_at=Time.get_ticks_msec()
	var b:=encounter();b.commands={};b.round_revision=0;b.events_revision=0;b.selection_starts_ms=10000
	for id in ["66666666-6666-4666-8666-666666666666","77777777-7777-4777-8777-777777777777","88888888-8888-4888-8888-888888888888"]:b.fighters.append(fighter(id))
	for i in 2:
		var e:Dictionary=b.enemies[0].duplicate(true);e.slot="m%d"%(i+3);b.enemies.append(e)
	model.state=state(b)
	view=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present();view._process(0)
	check(view.menu.visible and view.countdown.visible and not view.auto_button.visible,"Five-player formation uses the same commands and shared countdown")
	check(view.hint.text.contains("0/5"),"Team submission progress remains visible")
	for a in view.actors.values():
		check(a.hit.get_rect().end.y<349 and a.tag.position.y>50,"Formation hit targets and names stay between timer and footer")
		check(a.level.visible and not a.tag.visible and a.hit.tooltip_text.contains("Lv."),"Crowded formation uses original compact level bars with full identity on hover")
	await render("party")
	b.commands[SELF]={"action":"guard","target":null,"skill":null};view._refresh_controls()
	check(not view.menu.visible and view.countdown.visible and view.hint.text.contains("已锁定"),"Submitted teammate keeps authoritative countdown without actionable menu")
	view.queue_free();chrome.queue_free();await get_tree().process_frame
	Game.player=old;Game.save_path=old_path;OnlineAccount.pending_team=saved
	await get_tree().create_timer(0.25).timeout
	print("BATTLE REFERENCE LAYOUT: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
