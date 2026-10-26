extends Node
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func settle()->void:
	for frame in 3:await get_tree().process_frame
func click(control:Control,touch:bool=false)->void:
	var point:=get_viewport().get_final_transform()*control.get_global_rect().get_center()
	var event:InputEvent
	if touch:event=InputEventScreenTouch.new();event.position=point;event.pressed=true
	else:event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	var release:=event.duplicate();release.pressed=false;Input.parse_input_event(release);Input.flush_buffered_events()
	await settle()
func _ready()->void:
	await Game.when_ready()
	var field:=Control.new();field.position=Vector2(0,28);field.size=Vector2(320,396);field.clip_contents=true
	field.theme=load("res://scenes/ui/online_pve_theme.tres");add_child(field)
	var picker:=SkillPicker.new();field.add_child(picker);picker.position.y=-28
	var chosen:Array=[];picker.chosen.connect(func(id:String)->void:chosen.append(id))
	for job in 3:
		var stats:=CharacterAttributeRules.balanced_stats(job,60,false,[0,0,0,0,0])
		picker.present(job,3,60,1000,[],false,stats,{})
		await settle()
		check(picker.choices.size()==[13,10,11][job],"Every unlocked active skill is listed")
		check(not picker.scroll.get_v_scroll_bar().visible and picker.scroll.scroll_vertical==0,"Current skill pool fits without scrolling")
		for row in picker.rows.get_children():
			check(picker.scroll.get_global_rect().grow(0.5).encloses(row.get_global_rect()),"Every row is fully visible before selection")
		check(picker.paper.position.y<165 and picker.paper.get_rect().end.y>315,"Paper expands both upward and downward")
		check(picker.description.get_global_rect().position.y>=68 and picker.description.get_global_rect().end.y<=picker.paper.get_global_rect().position.y,"Description fits below countdown and above paper")
		check(picker.back.get_global_rect().end.y<=402 and field.get_global_rect().encloses(picker.back.get_global_rect()),"Return button stays above chat and inside actual clipped battle parent: "+str(picker.back.get_global_rect()))
		var count:=chosen.size();var last:Button=picker.rows.get_child(picker.rows.get_child_count()-1)
		await click(last,job==2)
		check(chosen.size()==count+1 and chosen[-1]==picker.choices[-1].id,"Visible last skill submits by mouse or touch without scrolling")
		await click(last,job==2)
		check(chosen.size()==count+1,"Repeated taps cannot submit twice")
	picker.present(0,3,1,1000);await settle()
	check(picker.paper.size.y==150 and picker.choices.size()==1,"Low-level list remains compact")
	picker.present(0,3,60,0);await settle()
	var count:=chosen.size();await click(picker.rows.get_child(0))
	check(chosen.size()==count and picker.description.text.contains("灵力不足"),"Expanded list preserves insufficient mana refusal")
	var stats:=CharacterAttributeRules.balanced_stats(0,60,false,[0,0,0,0,0])
	var effects:=SkillRules.new_state(0,3,60);SkillRules.activate(effects,stats);effects.balance.cooldowns.sheet_010=2
	picker.present(0,3,60,1000,[],false,stats,effects);await settle();await click(picker.rows.get_child(0))
	check(chosen.size()==count and picker.description.text.contains("尚余2轮"),"Expanded list preserves cooldown refusal")
	field.queue_free();await settle()
	var output:=OS.get_environment("SSJX_SKILL_LAYOUT_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		var old:=Game.player.duplicate(true);var path:=Game.save_path;var combat=Game.local_combat
		Game.save_path="user://skill_picker_layout_%d.json"%OS.get_process_id()
		Game.new_player("技能选择",0,3);Game.player.level=60;Game.restore()
		var app=load("res://scenes/main.tscn").instantiate();add_child(app);app._enter_world()
		var enemy:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);enemy.hp=10000
		app._start_local_encounter([enemy,enemy.duplicate(true),enemy.duplicate(true)])
		app.local_encounter_view._choose("skill");await settle()
		check(app.local_encounter_view.picker.visible and not app.local_encounter_view.picker.scroll.get_v_scroll_bar().visible,"Real local encounter opens the complete shared picker")
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Complete picker rendered inside the real battle")
		app._home();app.queue_free();await settle();Game.player=old;Game.save_path=path;Game.local_combat=combat
	print("SKILL PICKER LAYOUT: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
