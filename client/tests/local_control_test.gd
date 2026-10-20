extends Node
const DELAYED := preload("res://tests/fixtures/delayed_storage.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LOCAL CONTROL FAIL: "+message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await Platform.when_ready()
	var old_player:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	var account:=OnlineAccount.account.duplicate(true)
	Game.save_path="user://local_control_%d.json"%OS.get_process_id()
	Game.new_player("指令测试",0,2)
	var app:Control=load("res://scenes/main.tscn").instantiate()
	add_child(app);app.set_process(false);app._enter_world()
	var screen:GameWorldScreen=app.ui.get_node("GameWorldScreen")
	var chat:LocalWorldChat=screen.local_chat
	check(chat.panel.is_visible_in_tree() and chat.input.is_visible_in_tree() and screen.get_node("Chat/ChatSend").is_visible_in_tree(),"Entering local world directly exposes the chat composer and send button")
	chat.input.text="/control lv 50"
	await chat.send()
	check(Game.player.level==50 and Game.player.xp==0,"Local chat command sets requested level and clears XP")
	check(Game.player.hp==Game.stats().hp and Game.player.mp==Game.stats().mp,"Level command restores the new HP and MP caps")
	check(app.hud_name.text.contains("50") and screen.chrome.identity.text=="LV.50" and screen.chrome.hp_bar.value==Game.player.hp,"World HUD refreshes level and health immediately")
	check(SkillRules.list_for(0,2,50).any(func(skill:Dictionary)->bool:return skill.id=="sheet_011"),"New level immediately opens eligible skills")
	check(chat.messages.size()==1 and chat.messages[0].channel=="system" and chat.input.text.is_empty(),"Command becomes a local system confirmation rather than a public chat message")
	check(JSON.parse_string(FileAccess.get_file_as_string(Game.save_path)).level==50,"Confirmed level is persisted")
	var capture:=OS.get_environment("SSJX_LOCAL_CHAT_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(capture)
	chat.toggle()
	check(chat.expanded.visible and chat.panel.visible,"Local history expands above the persistent composer")
	chat.close()
	check(not chat.expanded.visible and chat.panel.is_visible_in_tree() and not screen.chrome.log_label.visible,"Closing history or a menu keeps the inline chat available")
	Game.player={}
	check((await Game.load_game()).ok and Game.player.level==50,"Level survives loading the local save")
	var before:=Game.player.duplicate(true)
	for invalid in ["/control","/control help","/control lv","/control lv 0","/control lv 61","/control lv -1","/control lv 1.5","/control lv abc","/control lv 50 extra","/control gold 999"]:
		chat.input.text=invalid;await chat.send()
		check(Game.player==before and chat.messages[-1].channel=="system","Help/invalid command leaves the character unchanged: "+invalid)
	Game.player.allocated_attributes=[250,0,0,0,0]
	chat.input.text="/control lv 1";await chat.send()
	check(Game.player.level==1 and Game.allocated_attributes()==[0,0,0,0,0] and Game.valid_save(Game.player),"Downgrade resets only over-budget allocations and keeps a valid save")
	check(chat.messages[-1].text.contains("重置属性分配"),"Allocation reset is explained to the player")
	chat.input.text="/control  lv   60";await chat.send()
	check(Game.player.level==60,"Upper bound and repeated spaces are supported")
	chat.input.text="普通本地消息";await chat.send()
	check(chat.messages[-1].channel=="public" and chat.messages[-1].text=="普通本地消息","Ordinary local chat remains unchanged")
	var resources:=Game.player.duplicate(true)
	chat.input.text="/control hp 1";await chat.send()
	check(Game.player.hp==1 and screen.chrome.hp_bar.value==1,"HP command sets absolute health to one and refreshes HUD")
	check(Game.player.mp==resources.mp and Game.player.gold==resources.gold and Game.player.level==resources.level and Game.player.xp==resources.xp,"HP control changes no other resource")
	check((await Game.load_game()).ok and Game.player.hp==1,"One HP survives actual disk reload")
	var starting_gold:int=Game.player.gold
	chat.input.text="/control money 1";await chat.send()
	check(Game.player.gold==starting_gold+1 and Game.player.hp==1,"Money command adds one copper rather than setting the total to one")
	chat.input.text="/control money 1";await chat.send()
	check(Game.player.gold==starting_gold+2,"Repeated money commands add independently once each")
	check((await Game.load_game()).ok and Game.player.gold==starting_gold+2,"Added copper survives actual disk reload")
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		await get_tree().process_frame;RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(capture.get_basename()+"-hp-money.png")
	before=Game.player.duplicate(true)
	for invalid in ["/control hp 0","/control hp -1","/control hp 1000000","/control hp 1.5","/control hp x","/control hp 1 extra","/control money 0","/control money -1","/control money 1.5","/control money x","/control money 1000000001","/control money 1 extra"]:
		chat.input.text=invalid;await chat.send();check(Game.player==before,"Invalid resource control leaves save unchanged: "+invalid)
	Game.player.gold=1000000000
	chat.input.text="/control money 1";await chat.send()
	check(Game.player.gold==1000000000,"Copper addition cannot exceed the save-format cap")
	Game.player=before.duplicate(true)
	Game.become_soul();var soul:=Game.player.duplicate(true)
	for command in ["/control hp 1","/control money 1","/control lv 50"]:
		chat.input.text=command;await chat.send();check(Game.player==soul,"Resource controls cannot bypass soul recovery: "+command)
	Game.player=before.duplicate(true)
	var original:=Platform.context
	var storage:=DELAYED.new()
	Platform.context=PlatformContext.new("local-control-test",storage,original.runtime_config,original.display,original.lifecycle,original.resource_loader,original.text_input,original.system_actions)
	before=Game.player.duplicate(true)
	chat.input.text="/control lv 50";chat.send()
	check(Game.storage_busy and chat._control_busy and storage.operations.size()==1,"Delayed save waits for actual persistence")
	chat.input.text="/control lv 20";chat.send()
	check(storage.operations.size()==1 and Game.player.level==50,"Repeated submit cannot enqueue another level mutation while saving")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试保存失败"))
	check(Game.player==before and not chat._control_busy and chat.messages[-1].text.contains("未生效"),"Save failure rolls back the entire character and reports failure")
	for command in ["/control hp 2","/control money 1"]:
		chat.input.text=command;chat.send()
		check(Game.storage_busy and chat._control_busy,"Resource control waits for durable storage: "+command)
		storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试保存失败"))
		check(Game.player==before and not chat._control_busy and chat.messages[-1].text.contains("未生效"),"Failed resource save rolls back without changing another field: "+command)
	screen.online_mode=true
	chat.input.text="/control lv 10";await chat.send()
	check(Game.player==before and storage.operations.is_empty(),"Online screen cannot dispatch local controls")
	for command in ["/control hp 1","/control money 1"]:
		chat.input.text=command;await chat.send();check(Game.player==before and storage.operations.is_empty(),"Online screen cannot invoke resource controls: "+command)
	screen.online_mode=false
	# A remote chat channel carries literal text and has no local mutation hook.
	var remote:=OnlinePublicChat.new();remote.enabled=true;remote.connected=true
	var sent:Array=[];remote.send_requested.connect(func(packet:Dictionary)->void:sent.append(packet))
	check(remote.submit("/control lv 50") and sent.size()==1 and sent[0].type=="chat.send" and Game.player==before,"Online command text is only chat; no level operation is introduced")
	check(OnlineAccount.account==account,"Control commands leave the online account untouched")
	chat.input.text="/control lv 30";chat.send()
	Game.new_player("另一角色",1,0)
	var next_character:=Game.player.duplicate(true)
	storage.complete(PlatformResult.success({"written":true,"durability":"native_file","bytes":12}))
	check(Game.player==next_character and chat.messages[-1].text.contains("未生效"),"A stale save completion cannot overwrite a different local character")
	Platform.context=original
	# Let chat's deferred scroll restoration finish before destroying the test UI.
	for frame in 3:await get_tree().process_frame
	app.free()
	if FileAccess.file_exists(Game.save_path):DirAccess.remove_absolute(Game.save_path)
	Game.save_path=old_path;Game.player=old_player
	print("LOCAL CONTROL: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
