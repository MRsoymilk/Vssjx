extends Node
const MODEL = preload("res://scripts/network/online_social.gd")
const SELF := "11111111-1111-4111-8111-111111111111"
const OTHER := "22222222-2222-4222-8222-222222222222"
const THIRD := "33333333-3333-4333-8333-333333333333"
const GUILD := "44444444-4444-4444-8444-444444444444"
var checks:=0
var failures:=0
var sent: Array=[]

func _ready() -> void:_run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("SOCIAL: "+text)
func person(id: String) -> Dictionary:
	return {"id":id,"display_name":{SELF:"青云客",OTHER:"昆仑客",THIRD:"峨嵋客"}[id],"job":1,"gender":0,"level":8,"online":true}
func state() -> Dictionary:
	var me:=person(SELF);me.role="leader"
	var other:=person(OTHER);other.role="member"
	return {"friends":[person(OTHER)],"incoming":[person(THIRD)],"outgoing":[],"guild":{"id":GUILD,"name":"蜀山同盟","announcement":"同游蜀山，互助修行。","role":"leader","members":[me,other],"applications":[person(THIRD)]},"guilds":[{"id":GUILD,"name":"蜀山同盟","announcement":"同游蜀山","members":2,"applied":false}]}
func profile() -> Dictionary:
	var p:=person(OTHER);p.school=2;p.appearance=[1,0,0]
	p.guild={"id":GUILD,"name":"蜀山同盟","role":"member"}
	p.combat=CharacterAttributeRules.profile(1,8,true,[0,0,0,5,0]).combat
	p.equipment={}
	for slot in ShopRules.SLOTS:p.equipment[slot]=null
	p.equipment.weapon="sword"
	return p
func response(model: RefCounted, s: Dictionary=state(), p: Variant=null) -> Dictionary:
	return {"version":"social-v1","character_id":SELF,"operation_id":model.request.get("operation_id"),"ok":true,"code":"OK","replayed":false,"state":s,"profile":p}
func button(root: Node, text: String) -> Button:
	for node in root.get_children():
		if node is Button and node.text==text:return node
		var found:=button(node,text)
		if found!=null:return found
	return null
func capture(name: String) -> void:
	var path:=OS.get_environment("SSJX_SOCIAL_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path.path_join(name+".png"))==OK,"Render capture "+name)

func _run() -> void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true)
	var outbox:=OnlineAccount.pending_social.duplicate(true)
	OnlineAccount.pending_social={}
	var model:=MODEL.new();model.bind_character(SELF)
	model.send_requested.connect(func(p: Dictionary)->void:sent.append(p))
	check(model.fetch("profile",OTHER),"Profile lookup is queued by target")
	model.tick(false)
	check(sent.is_empty(),"No request before authenticated transport is available")
	model.tick(true)
	check(sent.size()==1 and sent[-1].target==OTHER,"Profile request uses selected target")
	var valid:=response(model,state(),profile())
	var invalid:=valid.duplicate(true);invalid.character_id=OTHER
	check(not model.valid(invalid),"Response for another owned character is rejected")
	invalid=valid.duplicate(true);invalid.profile.equipment.hat="potion"
	check(not model.valid(invalid),"Equipment in the wrong slot is rejected")
	invalid=valid.duplicate(true);invalid.state.guild.members[1].role="leader"
	check(not model.valid(invalid),"Multiple guild leaders are rejected")
	invalid=valid.duplicate(true);invalid.state.erase("guild")
	check(not model.valid(invalid),"Incomplete relationship snapshot is rejected")
	check(model.receive(valid) and model.profile.id==OTHER,"Allowlisted card and relationship snapshot are accepted")
	var panel: Control=load("res://scenes/ui/social_panel.tscn").instantiate();panel.model=model;add_child(panel)
	panel.show();panel.section="profile";panel._refresh()
	check(panel.preview!=null and panel.preview.sprite_frames==OriginalArt.cached["hero/mck"],"Player card renders target's appearance")
	check(panel.rows.get_child_count()>15 and button(panel,"邀请决斗")!=null,"Player card shows equipment and keeps PK invitation entry")
	var equipment_icons: Array=panel.rows.find_children("*","TextureRect",true,false)
	check(equipment_icons.size()==10 and equipment_icons[0].texture!=null,"All ten equipment slots render, using the original icon for the equipped weapon")
	await capture("profile")
	panel.scroll.scroll_vertical=9999
	await capture("equipment")
	panel._tab("friends")
	check(button(panel,"查看资料")!=null and button(panel,"删除好友")!=null,"Friend list provides profile and remove actions")
	button(panel,"删除好友").pressed.emit()
	check(panel.confirmation.visible and sent.size()==1,"Destructive friend removal needs an explicit local confirmation")
	button(panel.confirmation,"取消").pressed.emit()
	check(not panel.confirmation.visible and sent.size()==1,"Cancel confirmation has no side effects")
	panel._tab("requests")
	check(panel.tabs.requests.text=="申请(1)" and button(panel,"同意")!=null and button(panel,"拒绝")!=null,"Incoming requests show independent accept and reject controls")
	button(panel,"同意").pressed.emit();model.tick(true)
	check(model.pending() and sent[-1].action=="friend_accept" and sent[-1].target==THIRD,"Accept button submits only the chosen incoming player")
	var original:=model.request.duplicate(true)
	check(not model.submit("guild_disband"),"Pending mutation cannot be replaced")
	model.receive({"ok":false,"code":"NETWORK_ERROR"})
	check(model.pending() and OnlineAccount.pending_social.request==original,"Unknown transport outcome preserves original outbox")
	model.next_poll=0;model.tick(true)
	check(sent[-1]==original,"Retry preserves original operation UUID and payload")
	var saved:=state();saved.incoming=[];saved.friends.append(person(THIRD))
	var receipt:=response(model,saved);receipt.replayed=true
	check(model.receive(receipt) and not model.pending() and OnlineAccount.pending_social.is_empty(),"Authoritative receipt clears outbox and installs saved relationship")
	panel._tab("guild")
	check(button(panel,"入帮申请(1)")!=null and button(panel,"移交")!=null and button(panel,"解散帮派")!=null,"Leader sees application, transfer and disband controls")
	await capture("guild")
	button(panel,"入帮申请(1)").pressed.emit()
	check(button(panel,"同意")!=null,"Leader can review join applications")
	button(panel,"同意").pressed.emit();model.tick(true)
	check(sent[-1].action=="guild_approve" and sent[-1].target==THIRD,"Guild approval addresses the selected applicant")
	check(model.receive(response(model)),"Guild approval receives a durable receipt")
	panel.guild_section="members"
	var member_state:=state();member_state.guild.role="member";member_state.guild.members[0].role="member";member_state.guild.members[1].role="leader";member_state.guild.applications=[]
	model.state=member_state;panel._refresh()
	check(button(panel,"退出帮派")!=null and button(panel,"解散帮派")==null and button(panel,"移交")==null,"Ordinary members never get leader actions")
	var empty:=state();empty.guild=null;model.state=empty;panel._refresh()
	check(button(panel,"免费创建帮派")!=null,"Unaffiliated player can create a guild")
	panel.guild_section="directory";panel._refresh()
	check(button(panel,"申请加入")!=null,"Unaffiliated player can apply through the guild directory")
	await capture("directory")
	model.fetch();model.tick(true);model.fetch("profile",OTHER)
	check(model.receive(response(model)) and model.request.action=="profile","Profile lookup during background refresh remains queued")
	model.tick(true);model.receive(response(model,state(),profile()))
	check(model.profile.id==OTHER,"Queued lookup receives target card")
	model.fetch();model.tick(true);model.receive({"ok":false,"code":"NOT_FOUND"})
	var count:=sent.size();model.next_poll=0;model.tick(true)
	check(not model.supported and sent.size()==count,"Older server response disables automatic polling")
	model.fetch();model.tick(true)
	check(model.supported and sent.size()==count+1,"Manual refresh can retry after server upgrade")
	model.receive(response(model))
	panel.queue_free();await get_tree().process_frame
	var view: OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=SELF;add_child(view);view.set_process(false);view.network.set_process(false)
	view.network.entities={OTHER:{"display_name":"昆仑客"}}
	view.network.world_ready=true
	view._select_player(OTHER)
	check(view.target_view.visible and not view.target_view.actions.visible and not view.social_panel.visible and view.target.selected==OTHER,"Clicking a map player only selects the upper-right target, independently of PK capability")
	view.target_view.card.pressed.emit()
	check(view.target_view.actions.visible and not view.social_panel.visible,"A second deliberate HUD click opens the action menu")
	view.target_view.buttons.profile.pressed.emit()
	check(view.social_panel.visible and view.social_panel.section=="profile" and view.social.request.target==OTHER,"Only the explicit view-info action opens the public profile")
	view.social_panel.dismiss();view._scene_action("friends")
	check(view.social_panel.visible and view.social_panel.section=="friends","Menu social opens friend management")
	view._scene_action("guild")
	check(view.social_panel.visible and view.social_panel.section=="guild" and not view.details.visible,"Guild entry replaces its old placeholder")
	view._open_expanded_chat()
	check(not view.social_panel.visible and view.expanded_chat.visible,"Chat and social modal never overlap")
	view.queue_free();await get_tree().process_frame
	check(Game.player==old,"Social UI never changes local character data")
	OnlineAccount.pending_social=outbox
	print("SOCIAL CLIENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
