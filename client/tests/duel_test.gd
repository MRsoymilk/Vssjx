extends Node
const SELF := "22222222-2222-4222-8222-222222222222"
const OTHER := "11111111-1111-4111-8111-111111111111"
const OFFER := "33333333-3333-4333-8333-333333333333"
const BATTLE := "44444444-4444-4444-8444-444444444444"
var checks := 0
var failures := 0
func _ready() -> void: _run.call_deferred()
func check(value: bool,text: String) -> void:
	checks += 1
	if not value: failures += 1;push_error("DUEL CLIENT FAIL: " + text)
func state(rev: int = 0) -> Dictionary:
	return {"type":"duel.state","revision":str(rev),"incoming":null,"outgoing":null,"battle":null,"notice":""}
func fighter(id: String, gender: int) -> Dictionary:
	return {"id":id,"name":"甲方玩家" if id==SELF else "乙方玩家","job":0,"gender":gender,"school":3,"level":8,"appearance":[2,1,0],"speed":100 if id==SELF else 150,"stats":{"hp":246,"mp":91,"attack":46,"defense":21},"hp":246,"mp":91,"effects":SkillRules.new_state(0,3,8,8),"guarding":false}
func battle() -> Dictionary:
	return {"id":BATTLE,"fighters":[fighter(SELF,1),fighter(OTHER,0)],"revision":"0","round":1,"decision_revision":"0","resolved_round":0,"phase":"planning","submitted":[false,false],"your_choice":null,"events":[],"winner":null,"status":"active","reason":"","lines":["双方已确认，决斗开始。"],"remaining_ms":30000}
func wait_until(test:Callable,seconds:float=12)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return test.call()

func capture(name_value: String) -> void:
	var path := OS.get_environment("SSJX_DUEL_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path.path_join(name_value+".png"))==OK,"Capture "+name_value)

func _run() -> void:
	await Platform.when_ready()
	var old := Game.player.duplicate(true)
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=SELF;add_child(view);view.set_process(false);view.network.set_process(false)
	var duel := view.network.duel
	duel.enabled=true
	var sent: Array[Dictionary]=[]
	duel.send_requested.connect(func(packet:Dictionary)->void:sent.append(packet))
	check(duel.receive(state()) and duel.connected,"Negotiated channel accepts its initial empty baseline")
	check(not view.duel_invitation.visible and not view.duel_battle.visible,"Initial baseline does not show a spurious invitation or fight")
	var history:=state()
	history.battle=battle();history.battle.id=OFFER;history.battle.status="finished";history.battle.phase="finished";history.battle.winner=OTHER
	check(duel.receive(history) and not view.duel_battle.visible,"Logging in again does not replay an earlier completed duel before a new invitation")
	var offer := state(1)
	offer.incoming={"id":OFFER,"from":OTHER,"to":SELF,"from_name":"乙方玩家","to_name":"甲方玩家","remaining_ms":30000}
	check(duel.receive(offer),"Authenticated incoming invitation validates")
	check(view.duel_invitation.visible and view.duel_invitation.panel.position.x==4 and view.duel_invitation.confirm.text=="确认" and view.duel_invitation.reject.text=="拒绝","Invitation is on the left with explicit accept/reject buttons")
	check(not duel.active() and not view.duel_battle.visible,"Being invited cannot start battle")
	await capture("invitation")
	view.duel_invitation.reject.pressed.emit()
	check(sent.size()==1 and sent[0].command.action=="reject" and sent[0].command.invite_id==OFFER,"Reject button addresses only its server-issued invitation")
	check(duel.pending() and view.duel_invitation.confirm.disabled,"Pending reply disables repeated confirmation")
	duel.receive({"type":"duel.result","request_id":duel.request.request_id,"ok":true,"code":"OK","retry_after_ms":0})
	duel.receive(state(2))
	check(not duel.active() and not view.duel_invitation.visible,"Confirmed rejection removes the prompt without entering battle")
	check(duel.submit("invite",OTHER),"Inviter can request an online opponent")
	var request := duel.request.duplicate(true)
	duel.retry()
	check(sent[-1].command==request,"Unconfirmed retry preserves the same request UUID")
	duel.receive({"type":"duel.result","request_id":request.request_id,"ok":false,"code":"DUEL_REJECT_COOLDOWN","retry_after_ms":300000})
	check(duel.cooldown_ms(OTHER)>299000 and not duel.submit("invite",OTHER),"Five-minute server cooldown disables another invitation locally")
	var invalid:=offer.duplicate(true);invalid.incoming.to=OTHER
	check(not duel.receive(invalid),"Invitations addressed to a third party are rejected")
	var combat:=state(3);combat.battle=battle()
	check(duel.receive(combat) and duel.active() and view.duel_battle.visible,"Only the accepted battle baseline opens player combat")
	check(view.duel_battle.hero.get_meta("art_key")==ShopRules.actor_key(0,1,[2,1,0]) and view.duel_battle.enemy.get_meta("art_key")==ShopRules.actor_key(0,0,[2,1,0]),"Both players retain their gender and equipment in battle")
	check(not view.duel_battle.buttons[0].disabled and view.duel_battle.buttons[3].disabled,"Both participants can choose at the beginning of the round; items remain disabled")
	check(view.duel_battle.get_node("Hint").text.contains("同时决策"),"Planning UI identifies simultaneous choices and speed")
	var count:=sent.size()
	view.duel_battle.choose("attack")
	check(sent.size()==count+1 and sent[-1].command.expected_revision=="0","Local decision uses a stable round token")
	duel.receive({"type":"duel.result","request_id":duel.request.request_id,"ok":true,"code":"OK","retry_after_ms":0})
	view.duel_battle.choose("attack")
	check(sent.size()==count+1 and not duel.can_decide(),"Acknowledged decision stays locked even before the next state packet")
	check(view.duel_battle.get_node("Hud/ActionMenu").visible and not view.duel_battle.buttons[5].disabled,"A committed player can still surrender while waiting")
	combat.revision="4";combat.battle.revision="1";combat.battle.submitted=[true,false];combat.battle.your_choice={"action":"attack","skill":null}
	check(duel.receive(combat) and view.duel_battle.animation_time==0,"A single hidden commitment cannot animate or damage the opponent")
	var leak:=combat.duplicate(true);leak.battle.choices=["attack","skill"]
	check(not duel.receive(leak),"Protocol rejects leaked private choices")
	var first:Array=combat.battle.fighters.duplicate(true);first[0].hp=226;first[1].effects.last_damage=20
	var second:Array=first.duplicate(true);second[1].hp=226;second[0].effects.last_damage=20
	combat.revision="5";combat.battle.revision="3";combat.battle.phase="resolving";combat.battle.resolved_round=1;combat.battle.submitted=[true,true];combat.battle.fighters=second
	combat.battle.events=[{"actor":OTHER,"action":"attack","skill":"","damage":20,"reflected":0,"fighters":first},{"actor":SELF,"action":"attack","skill":"","damage":20,"reflected":0,"fighters":second}]
	check(duel.receive(combat) and view.duel_battle._playing.actor==OTHER,"Faster opponent animates before the local player")
	check(view.duel_battle.buttons[0].disabled and view.duel_battle.adapter.playing,"Inputs lock during ordered playback")
	combat.revision="6";combat.battle.revision="4";combat.battle.phase="planning";combat.battle.round=2;combat.battle.decision_revision="1";combat.battle.submitted=[false,false];combat.battle.your_choice=null
	check(duel.receive(combat),"Next simultaneous round can arrive during playback")
	check(await wait_until(func()->bool:return view.duel_battle._playing.is_empty() and view.duel_battle._queue.is_empty()),"Both queued actions finish without interruption")
	check(view.duel_battle.played_order==[OTHER,SELF],"Playback order matches server initiative without skipping either action")
	check(not view.duel_battle.buttons[0].disabled,"Next planning phase enables local choice only after playback")
	view.duel_battle.choose("potion")
	check(not view.duel_battle.get_node("Choice").visible and not duel.pending(),"Disabled item shortcut cannot open or send a PvE potion action")
	view.duel_battle.choose("skill")
	check(view.duel_battle.skill_picker.visible,"PK uses the existing skill selection interface")
	view.duel_battle.skill_picker.chosen.emit("legacy_0")
	check(duel.pending() and sent[-1].command.action=="skill" and sent[-1].command.skill=="legacy_0" and sent[-1].command.expected_revision=="1","Skill button sends an ID and revision, never a client damage value")
	await capture("pk-battle")
	duel.disconnect_channel()
	check(view.duel_battle.adapter.ready==false and "恢复决斗" in view.duel_battle.get_node("Hint").text,"Disconnected combat locks input and explains recovery")
	duel.request={}
	combat.revision="7";combat.battle.revision="5";combat.battle.submitted=[true,false];combat.battle.your_choice={"action":"skill","skill":"legacy_0"}
	check(duel.receive(combat) and not duel.can_decide(),"Reconnect preserves the server-confirmed locked choice")
	check(view.duel_battle._playing.is_empty() and view.duel_battle._queue.is_empty() and view.duel_battle.animation_time==0,"Reconnect installs the current baseline without replaying earlier round events")
	duel.disconnect_channel()
	check(duel.receive(state(0)),"Server restart resets stream revision and replaces an abandoned duel with an empty baseline")
	check(not view.duel_battle.visible and view.screen.hud.visible,"Missing battle after reconnect releases the old combat UI")
	check(Game.player==old,"Online duel UI leaves local characters untouched")
	view.free()
	print("DUEL CLIENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
