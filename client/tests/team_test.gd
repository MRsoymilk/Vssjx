extends Node
const SELF:="11111111-1111-4111-8111-111111111111"
const OTHER:="22222222-2222-4222-8222-222222222222"
const TEAM:="33333333-3333-4333-8333-333333333333"
const BATTLE:="44444444-4444-4444-8444-444444444444"
var checks:=0
var failures:=0
var sent:Array=[]
func _ready()->void:_run.call_deferred()
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("TEAM: "+text)
func member(id:String)->Dictionary:return {"id":id,"display_name":"青云客" if id==SELF else "昆仑客","job":1,"gender":0,"level":15,"map_id":"qingyun_trail","leader":id==SELF,"ready":true,"online":true,"following":true}
func fighter(id:String)->Dictionary:
	var m:=member(id);var stats:=CharacterAttributeRules.stats(1,15,true,[0,0,0,0,0])
	return {"id":id,"name":m.display_name,"job":1,"gender":0,"school":3,"level":15,"appearance":[1,0,0],"stats":stats,"hp":stats.hp,"mp":stats.mp,"potions":3,"effects":SkillRules.new_state(1,3,15,1),"guarding":false}
func encounter()->Dictionary:
	var es:Array=[]
	for i in 3:
		es.append({"slot":"m%d"%i,"hp":110,"definition":{"id":"wolf_a","name":"山狼","kind":"wolf","art":"monster/langw","hp":110,"attack":18,"defense":5,"level":1,"gold":12,"xp":16},"effects":SkillRules.new_state(1,3,1,1)})
	return {"id":BATTLE,"map_id":"qingyun_trail","fighters":[fighter(SELF),fighter(OTHER)],"enemies":es,"turn":0,"round":1,"revision":0,"outcome":"active","deadline_ms":40000,"last_action_ms":10000,"events":[],"lines":["队伍遭遇战开始。"]}
func state(b:Variant=null)->Dictionary:return {"team":{"id":TEAM,"leader":true,"members":[member(SELF),member(OTHER)],"outgoing":[],"battle":b},"incoming":[]}
func response(model:RefCounted,s:Dictionary)->Dictionary:return {"version":"team-v1","character_id":SELF,"operation_id":model.request.get("operation_id"),"ok":true,"code":"OK","replayed":false,"server_time_ms":10000,"state":s}
func capture(name:String)->void:
	var path:=OS.get_environment("SSJX_TEAM_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path.path_join(name+".png"))==OK,"Render "+name)
func _run()->void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true)
	var outbox:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	var model:RefCounted=preload("res://scripts/network/online_team.gd").new();model.bind_character(SELF)
	model.send_requested.connect(func(payload:Dictionary)->void:sent.append(payload))
	model.tick(false);check(sent.is_empty(),"Offline transport cannot dispatch team operations")
	model.tick(true);check(model.receive(response(model,state())),"Initial versioned team state validates")
	var panel:Control=load("res://scenes/ui/team_panel.tscn").instantiate();panel.model=model;add_child(panel);panel.show()
	check(panel.rows.get_children().filter(func(row:Node)->bool:return row is PanelContainer).size()==2,"Team window shows one portrait card per member")
	await get_tree().process_frame
	var back:Button=panel.find_child("Back",true,false)
	check(back!=null and is_equal_approx(back.get_rect().get_center().x,back.get_parent().size.x/2) and back.get_rect().end.y<=back.get_parent().size.y-12,"Return stays centered inside the footer with clearance above the gold frame")
	await capture("team")
	var preview:=state()
	for i in 3:
		var m:=member([TEAM,BATTLE,"55555555-5555-4555-8555-555555555555"][i]);m.job=i;m.gender=i%2;m.following=i!=1;m.online=i!=2;m.ready=i==0;m.display_name="天涯明月清风剑客" if i==2 else ["青云力士","花间隐者"][i%2];preview.team.members.append(m)
	model.state=preview;panel.refresh();await get_tree().process_frame;await get_tree().process_frame
	check(panel.rows.get_children().filter(func(row:Node)->bool:return row is PanelContainer).size()==5,"Full team retains every member including offline and away players")
	var scroll:ScrollContainer=panel.rows.get_parent()
	check(scroll.get_v_scroll_bar().max_value>scroll.size.y and panel.footer.get_global_rect().position.y>=scroll.get_global_rect().end.y,"Five-member list scrolls without covering persistent management buttons")
	await capture("team_five")
	scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);await get_tree().process_frame
	var bottom:=scroll.scroll_vertical;panel.refresh();await get_tree().process_frame;await get_tree().process_frame
	check(scroll.scroll_vertical==bottom,"Background team refresh preserves the member being inspected")
	await capture("team_five_bottom")
	panel.confirm("disband","","确定解散当前队伍？");await capture("team_confirmation")
	model.state={"team":null,"incoming":[]};panel.confirmation={};panel.refresh();await capture("team_empty")
	model.state=state();panel.refresh()
	panel.hide()
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view)
	model.refresh();model.tick(true)
	var valid:=response(model,state(encounter()))
	var invalid:=valid.duplicate(true);invalid.state.team.battle.enemies[0].hp=99999
	check(not model.valid(invalid),"Over-maximum monster health rejected")
	invalid=valid.duplicate(true);invalid.state.team.battle.fighters[1].id=SELF
	check(not model.valid(invalid),"Duplicate member identities rejected")
	check(model.receive(valid) and model.active() and model.my_turn(),"Shared battle opens only from authoritative state")
	check(view.visible and view.actors.size()==5,"Both teammates and all three monsters are on the battlefield")
	view.command_toggle.pressed.emit()
	check(view.menu.visible and view.menu.get_node("BattleButtons5").text=="6 撤退","Battle uses the original six-command menu")
	await capture("commands")
	view._choose("inspect")
	check(view.inspect_panel.visible and view.inspect_panel.get_node("Secondary").text.contains("18"),"Original inspect panel displays strengthened monster statistics")
	view.inspect_panel.hide()
	view.actors.m2.hit.pressed.emit();view._choose("attack")
	check(model.request.target=="m2" and model.request.battle_id==BATTLE and model.request.expected_revision==0,"Selected enemy is fenced by shared battle and revision")
	model.tick(true);var original:Dictionary=model.request.duplicate(true)
	model.receive({"ok":false,"code":"NETWORK_ERROR"});check(model.pending() and OnlineAccount.pending_team.request==original,"Unknown combat response retains durable retry identity")
	model.next_poll=0;model.tick(true);check(sent[-1]==original,"Combat retry never invents a new operation ID")
	model.receive({"ok":false,"code":"SERVER_ERROR"});check(model.pending(),"Ambiguous gateway failure cannot discard the pending operation")
	model.next_poll=0;model.tick(true)
	var next:=encounter();next.turn=1;next.revision=1;next.enemies[2].hp=70;next.events=[{"actor":SELF,"target":"m2","action":"attack","skill":"","damage":40,"healed":0}]
	check(model.receive(response(model,state(next))) and not model.my_turn(),"Authoritative turn passes to teammate")
	await capture("battle")
	await get_tree().create_timer(1.6).timeout
	check(view.motion==null and view.queue.is_empty(),"Original attack playback completes without freezing")
	view._choose("attack");check(not model.pending(),"Waiting player cannot send another action")
	model.refresh();model.tick(true);var done:=next.duplicate(true);done.revision=2;done.outcome="victory"
	for e in done.enemies:e.hp=0
	done.events=[]
	check(model.receive(response(model,state(done))),"Completed shared fight is received")
	await get_tree().process_frame
	await get_tree().process_frame
	check(view.deaths.size()==3 and view.result.outcome=="victory","All dead monsters receive tombstones and original victory glyph")
	await capture("victory")
	view._dismiss();check(not view.visible,"Finished shared battle returns to map")
	var full:=encounter();full.id="55555555-5555-4555-8555-555555555555"
	var full_state:=state(full)
	for i in 3:
		var id:String=["66666666-6666-4666-8666-666666666666","77777777-7777-4777-8777-777777777777","88888888-8888-4888-8888-888888888888"][i]
		full.fighters.append(fighter(id));full_state.team.members.append(member(id))
	for i in 2:
		var e:Dictionary=full.enemies[0].duplicate(true);e.slot="m%d"%(i+3);full.enemies.append(e)
	model.refresh();model.tick(true)
	check(model.receive(response(model,full_state)) and view.actors.size()==10,"Full five-player, five-monster formation renders all ten combatants")
	for actor in view.actors.values():check(actor.home.x>=0 and actor.home.x<=320 and actor.home.y<=282,"Combatant formation stays above the command bar")
	await capture("full_party")
	view._choose("skill");view.picker.activate("sheet_004")
	check(model.request.get("skill")=="sheet_004","Original skill picker submits the chosen group attack")
	model.tick(true);full.revision=1;full.turn=1;full.events=[]
	for e in full.enemies:e.hp-=20;full.events.append({"actor":SELF,"target":e.slot,"action":"skill","skill":"sheet_004","damage":20,"healed":0})
	check(model.receive(response(model,full_state)),"Authoritative group hits validate")
	await get_tree().process_frame;await get_tree().process_frame
	check(view.motion!=null and view.queue.is_empty(),"Group attack plays one cast for all five target impacts")
	await get_tree().create_timer(1.6).timeout
	var solo:=encounter();solo.id="99999999-9999-4999-8999-999999999999";solo.fighters.resize(1);solo.enemies.resize(1)
	model.refresh();model.tick(true)
	var solo_packet:=response(model,state(solo))
	check(model.receive(solo_packet) and model.my_turn() and view.visible and view.actors.size()==2,"Leader can retain the party and render a one-participant encounter")
	view._choose("inspect")
	check(view.inspect_panel.get_node("Tertiary").text.contains("独自迎战"),"Lone encounter never claims a party strength multiplier")
	view.inspect_panel.hide();await get_tree().process_frame;await get_tree().process_frame;await capture("team_solo")
	model.refresh();model.tick(true)
	var empty_fight:=response(model,state(solo));empty_fight.state.team.battle.fighters=[]
	check(not model.valid(empty_fight),"A zero-participant encounter remains invalid")
	panel.queue_free();view.queue_free();await get_tree().process_frame
	var world:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate();world.character_id=SELF;add_child(world);world.set_process(false);world.network.set_process(false)
	world._scene_action("team");check(world.team_panel.visible and not world.details.visible,"Team menu replaces placeholder")
	world.team.state=state();world.team.state.team.battle_active=true;world.team_panel.refresh()
	check(world.team_panel.tip.text.contains("本轮未参战"),"Reconnecting or away member is told the team already has an encounter")
	world.team_panel.dismiss();world.team.state=state(encounter());world.team.changed.emit()
	check(world.team_battle.visible and world.network.team_active,"Shared encounter activates world movement gate")
	world.network.world_ready=true;world.network._state="ready";world.network._pending_motion={"type":"world.move_to"}
	world.network._receive({"type":"error","code":"TEAM_BATTLE_ACTIVE"},PackedByteArray())
	check(world.network.world_ready and world.network._pending_motion.is_empty(),"A late movement refusal cannot disconnect a team player")
	world.team_battle.hide();world.network.team_active=false
	world.team.state={"team":null,"incoming":[{"id":OTHER,"name":"天涯明月清风剑客"}]};world.team.changed.emit()
	check(world.team_notice.visible and not world.team_notice.get_global_rect().intersects(world.duel_invitation.panel.get_global_rect()),"Left team and duel invitations have separate touch areas")
	await capture("team_invitation")
	world.team.state=state();world.team.changed.emit()
	world.network._team_version=1
	var mark:={SELF:{"leader":true,"following":true},OTHER:{"leader":false,"following":true},TEAM:{"leader":false,"following":false}}
	var packet:={"type":"world.team","map_id":"qingyun_trail","members":mark,"following":true,"travel":null}
	check(OnlineWorldClient.valid_team_packet(packet,"qingyun_trail"),"Native team marker roles validate")
	var bad:=packet.duplicate(true);bad.members[SELF].leader="yes"
	check(not OnlineWorldClient.valid_team_packet(bad,"qingyun_trail"),"Forged flag roles are rejected")
	bad=packet.duplicate(true);bad.travel={"action":"teleport","target":"ancient_ruins","cell":[28,16]}
	check(not OnlineWorldClient.valid_team_packet(bad,"qingyun_trail"),"Following never accepts arbitrary teleport actions")
	world.network._pending_motion={"type":"world.move_to"}
	world.network._receive(packet,PackedByteArray())
	check(world.network.team_following and world.network._pending_motion.is_empty(),"Entering follow clears queued manual motion")
	packet.travel={"action":"transfer","target":"ruins_gate","cell":[28.0,16.0]}
	world.network._receive(packet,PackedByteArray())
	check(typeof(world.network.team_travel.cell[0])==TYPE_INT and world.network.team_travel.cell==[28,16],"JSON portal cells normalize to grid integers before arrival checks")
	world.network._receive({"type":"error","code":"TEAM_FOLLOWING"},PackedByteArray())
	check(world.network.world_ready,"Late manual motion rejection preserves connection")
	var entities:={}
	for i in 3:
		var id:String=[SELF,OTHER,TEAM][i]
		entities[id]={"id":id,"display_name":["青云队长","昆仑队友","暂离队友"][i],"job":i,"gender":0,"cell":[[18,10],[24,14],[28,18]][i],"next_cell":null,"segment_progress":0,"entity_revision":"1","world_epoch":"1"}
	world.network.entities=entities;world._snapshot(entities)
	for i in 3:
		var id:String=[SELF,OTHER,TEAM][i];var flag:Sprite2D=world.actors[id].flag
		check(flag.visible and flag.texture==[preload("res://assets/ui/team_leader.png"),preload("res://assets/ui/team_member.png"),preload("res://assets/ui/team_away.png")][i],"Leader/following/away flag matches recovered art")
		check(flag.position.x < -30 and flag.position.y==-63,"Flag sits beside the name and moves with actor root")
	world.team.state=state();world.team.state.team.leader=false;world.team.state.team.members[0].leader=false;world.team.state.team.members[1].leader=true;world.team_panel.open();world.team_panel.refresh()
	var follow_button:Button
	for row in world.team_panel.rows.get_children():
		for button in row.get_children():
			if button is Button and button.text=="暂离":follow_button=button
	check(follow_button!=null,"Own party row exposes temporary leave")
	if follow_button!=null:
		world.team.request={};world.team.inflight=false;follow_button.pressed.emit()
		check(world.team.request.get("action")=="follow" and world.team.request.ready==false,"Temporary leave submits a server-owned follow command")
	world.team_panel.hide();world._set_battle_layout(false);world.screen.hud.show();world.camera.position=Vector2(392,232)
	await capture("team_flags")
	world.queue_free();await get_tree().process_frame
	check(Game.player==old,"Team UI leaves the offline save untouched")
	OnlineAccount.pending_team=outbox
	print("TEAM CLIENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
