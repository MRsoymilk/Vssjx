extends Node
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("STUN UI: "+message)
func _ready()->void:_run.call_deferred()
func has_stun(strip:BattleStatusStrip)->bool:return strip.entries.any(func(row:Dictionary)->bool:return row.id=="stun")
func capture(name_value:String)->void:
	if DisplayServer.get_name()=="headless":return
	for frame in 3:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder:=OS.get_environment("SSJX_STUN_CAPTURE_PATH")
	if not folder.is_empty():check(get_viewport().get_texture().get_image().save_png(folder.path_join(name_value+".png"))==OK,"Capture "+name_value)
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var outbox:=OnlineAccount.pending_team.duplicate(true)
	var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BattleStatusStrip.CATALOG_PATH))
	check(meta.original_binding_recovered==false and meta.icons.stun.reference_animation=="t14","Stun star ring is explicitly an authored semantic mapping, not a recovered rule")
	check(FileAccess.get_sha256(meta.icons.stun.texture)==meta.icons.stun.decoded_sha256,"Stun icon preserves the original decoded frame bytes")
	var stats:=CharacterAttributeRules.balanced_stats(0,60,false,[60,60,60,60,60])
	var effects:=SkillRules.new_state(0,3,60);SkillRules.enable_stun(effects,stats)
	var picker:=SkillPicker.new();add_child(picker);picker.present(0,3,60,int(stats.mp),[],false,stats,effects);picker._select("sheet_010")
	check(picker.description.text.contains("35%") and picker.description.text.contains("受击不解除") and picker.description.text.contains("冷却3轮"),"Modern battle picker describes the actual stun and cooldown")
	await capture("stun-skill-picker")
	picker.present(0,3,60,int(stats.mp),[],false,stats,{});picker._select("sheet_010")
	check(not picker.description.text.contains("眩晕") and picker.description.text.contains("冷却0轮"),"Old in-flight battle picker does not promise unenabled stun or new cooldown")
	picker.queue_free();await get_tree().process_frame
	var book:SkillBook=load("res://scenes/ui/skill_book.tscn").instantiate();add_child(book);book.present({"job":0,"school":3,"level":60,"balance_revision":1},true)
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_010"))
	check(book.detail.text.contains("35%") and book.detail.text.contains("威力160%") and book.detail.text.contains("灵力9点") and book.detail.text.contains("冷却3轮"),"Skill book keeps damage and explains fixed mana and authored control")
	await capture("stun-skill-book")
	book.queue_free();await get_tree().process_frame
	var fixture=load("res://tests/team_test.gd").new()
	var b:Dictionary=fixture.encounter();b.enemies[0].effects.enemy_stun=1
	var ids:Dictionary={fixture.SELF:true,fixture.OTHER:true}
	check(OnlineTeamModel.valid_battle(b,fixture.SELF,ids),"Pending stun is valid on the target's authoritative state")
	var bad:=b.duplicate(true);bad.enemies[0].effects.enemy_stun=2
	check(not OnlineTeamModel.valid_battle(bad,fixture.SELF,ids),"Protocol rejects excessive target stun counts")
	var skip:Dictionary={"actor":"m0","target":"m0","action":"stun","skill":"","damage":0,"healed":0,"critical":false}
	b.enemies[0].effects.erase("enemy_stun");b.events=[skip]
	check(OnlineTeamModel.valid_battle(b,fixture.SELF,ids),"An explicit zero-damage skipped-action event validates")
	for key in ["damage","healed","skill","target","critical"]:
		bad=b.duplicate(true);bad.events[0][key]="sheet_010" if key=="skill" else (fixture.SELF if key=="target" else (true if key=="critical" else 1))
		check(not OnlineTeamModel.valid_battle(bad,fixture.SELF,ids),"Stun event cannot smuggle damage/healing/skills or a different target")
	var model:=OnlineTeamModel.new();model.bind_character(fixture.SELF);b.events=[];b.enemies[0].effects.enemy_stun=1
	model.state=fixture.state(b);model.server_time=10000;model.received_at=Time.get_ticks_msec()
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present();view._process(0)
	check(has_stun(view.actors.m0.status) and not has_stun(view.actors[fixture.SELF].status),"Restoring a pending stun badges the enemy, never its caster")
	view.actors.m0.status.buttons[0].pressed.emit()
	check(view.hint.text.contains("下一次行动") and view.hint.text.contains("受击不解除"),"Badge explains action consumption rather than an inaccurate round timer")
	b=b.duplicate(true);b.revision=1;b.enemies[0].effects.erase("enemy_stun");b.events=[skip];model.state=fixture.state(b)
	view.present();view._process(0)
	var home:Vector2=view.actors.m0.sprite.position;var hp:float=view.actors[fixture.SELF].hp.value
	check(view.motion!=null and view.motion.action==&"idle" and has_stun(view.actors.m0.status),"Authoritative skip plays idle and shows a temporary stun badge")
	view._process(0.1)
	check(view.actors.m0.sprite.position==home and view.actors[fixture.SELF].hp.value==hp,"Skipped action never approaches or damages the player")
	await capture("stun-team")
	view._process(3);view._process(0)
	check(not has_stun(view.actors.m0.status),"Consumed stun disappears after ordered round playback")
	view.present();check(view.queue.is_empty() and view.motion==null,"Repeated authoritative state does not replay the skip")
	view._play(skip);view._cancel()
	check(not has_stun(view.actors.m0.status) and view.motion==null,"Cancellation clears transient badges and idle playback")
	view.queue_free();fixture.free();await get_tree().process_frame
	var duel_fixture=load("res://tests/duel_test.gd").new()
	var channel:=OnlineDuel.new();channel.bind_character(duel_fixture.SELF);channel.enabled=true
	var packet:Dictionary=duel_fixture.state();packet.battle=duel_fixture.battle();packet.battle.fighters[1].effects.enemy_stun=1
	check(channel.receive(packet),"Duel protocol accepts a pending stun on the opposing caster")
	var duel:DuelBattleView=load("res://scenes/ui/duel_battle_view.tscn").instantiate();add_child(duel);duel.set_process(false);duel.present_duel(channel)
	check(has_stun(duel.status_hero) and not has_stun(duel.status_enemy),"Duel snapshot maps the opposing caster's stun onto the local victim")
	packet=packet.duplicate(true);packet.revision="1";packet.battle.revision="1";packet.battle.resolved_round=1;packet.battle.phase="resolving";packet.battle.fighters[1].effects.erase("enemy_stun")
	packet.battle.submitted=[true,true];packet.battle.your_choice={"action":"guard","skill":null}
	packet.battle.events=[{"actor":duel_fixture.SELF,"action":"stun","skill":"","damage":0,"reflected":0,"fighters":packet.battle.fighters.duplicate(true)}]
	check(channel.receive(packet),"Duel protocol accepts the actual skipped-action event")
	duel.present_duel(channel)
	check(duel.animation_time>0 and duel._hero_motion==null and duel._enemy_motion==null and has_stun(duel.status_hero),"Duel skip shows stun without a fabricated attack animation")
	check(duel.status_hero.visible and not duel.status_hero.get_global_rect().intersects(duel.move_callout.get_global_rect()),"Stun badge remains visible outside the skipped-action callout")
	await capture("stun-duel")
	bad=packet.duplicate(true);bad.revision="2";bad.battle.events[0].damage=1
	check(not channel.receive(bad),"Duel skip cannot carry injected damage")
	duel._process(1)
	check(not has_stun(duel.status_hero) and duel._playing.is_empty(),"Completed duel playback clears the consumed stun badge")
	duel.queue_free();duel_fixture.free();await get_tree().process_frame
	check(Game.player==old,"Skill/status presentation never modifies local character data")
	OnlineAccount.pending_team=outbox
	print("STUN UI: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
