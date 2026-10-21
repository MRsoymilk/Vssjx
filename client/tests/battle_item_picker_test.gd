extends "res://tests/shared_interface_test.gd"

class RemoteBattle extends RefCounted:
	signal changed
	var character_id:="00000000-0000-4000-8000-000000000001"
	var server_time:=0
	var received_at:=0
	var state:Dictionary={}
	var requests:Array=[]
	var waiting:=false
	var allowed:=true
	func battle()->Dictionary:return state
	func party()->Dictionary:return {"leader":true}
	func active()->bool:return state.outcome=="active"
	func pending()->bool:return waiting
	func connected()->bool:return true
	func can_submit()->bool:return allowed and not waiting
	func my_turn()->bool:return allowed and not waiting
	func submit(action:String,target:String="",skill:String="")->bool:
		if not can_submit():return false
		requests.append({"action":action,"target":target,"skill":skill});waiting=true;changed.emit();return true

func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path
	Game.save_path="user://battle_item_picker_%d.json"%OS.get_process_id()
	Game.new_player("选药检查",1,2);Game.player.hp=5;Game.player.potions=3
	output=OS.get_environment("SSJX_ITEM_CAPTURE_PATH") if DisplayServer.get_name()!="headless" else ""
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app._enter_world()
	var opponent:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);opponent.hp=10000;opponent.attack=1
	app._start_battle(opponent)
	var hp:int=app.battle.hp;var count:int=app.battle.potions
	app.action_menu.get_node("BattleButtons3").pressed.emit()
	var picker:BattleItemPicker=app.modal.get_node("BattleItemPicker")
	check(picker.visible and picker.item_button.text.contains("回春散 ×3"),"Item command opens the real available item list with quantity")
	check(app.battle.phase=="select" and app.battle.round_number==0 and app.battle.hp==hp and app.battle.potions==count,"Opening items neither heals nor spends a potion or a turn")
	await capture("local-item-list")
	picker.find_child("Cancel",true,false).pressed.emit()
	check(app.modal==null and app.action_menu.visible and app.battle.round_number==0 and app.battle.potions==count,"Cancel returns to the action menu without a turn or inventory change")
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_4
	app._unhandled_key_input(key)
	picker=app.modal.get_node("BattleItemPicker")
	check(app.battle.phase=="select" and picker.visible,"Four key opens item selection instead of using medicine")
	key.keycode=KEY_ESCAPE;picker._unhandled_key_input(key)
	check(app.modal==null and app.action_menu.visible and app.battle.potions==count,"Escape cancels item selection and restores the action menu")
	app._battle_items();picker=app.modal.get_node("BattleItemPicker")
	picker.item_button.pressed.emit();picker.item_button.pressed.emit()
	check(app.modal==null and app.battle.round_number==1,"Choosing an item submits exactly one local action")
	var deadline:=Time.get_ticks_msec()+3000
	while app.battle.potions==count and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(app.battle.potions==count-1 and app.battle.hp>hp,"Only item confirmation consumes one potion and heals at action time")
	app._home();app.queue_free();await get_tree().process_frame
	Game.new_player("阵列选药",1,2);Game.player.hp=5;Game.player.potions=3
	var solo:=SoloEncounter.new();solo.start([opponent])
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=solo;add_child(view);view.set_process(false);view.present()
	var before:=solo.state.duplicate(true)
	view.action_buttons[3].pressed.emit()
	check(view.item_picker.visible and solo.state==before,"Local formation item button only opens the picker")
	await capture("formation-item-list")
	view.item_picker.find_child("Cancel",true,false).pressed.emit()
	check(not view.item_picker.visible and view.menu.visible and solo.state==before,"Formation cancel leaves the round and bag untouched")
	view._choose("potion");view.item_picker.item_button.pressed.emit();view.item_picker.item_button.pressed.emit()
	check(solo.engine.potions==2 and solo.state.events.filter(func(e:Dictionary)->bool:return e.actor==solo.character_id and e.action=="potion").size()==1,"Formation confirmation consumes exactly one potion")
	view.queue_free();await get_tree().process_frame
	var remote:=RemoteBattle.new();remote.state=before.duplicate(true);remote.state.solo=false
	remote.server_time=int(Time.get_unix_time_from_system()*1000);remote.received_at=Time.get_ticks_msec();remote.state.deadline_ms=remote.server_time+30000
	var ally:Dictionary=remote.state.fighters[0].duplicate(true);ally.id=PEER;ally.name="同伴";remote.state.fighters.append(ally)
	view=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=remote;add_child(view);view.set_process(false);view.present()
	view._choose("potion")
	check(view.item_picker.visible and remote.requests.is_empty(),"Multiplayer item button sends no request before selection")
	view.item_picker.dismissed.emit()
	check(remote.requests.is_empty() and remote.state.fighters[0].potions==3,"Multiplayer cancel does not consume inventory or a command window")
	view._choose("potion");remote.allowed=false;view._refresh_controls();view.item_picker.activate()
	check(not view.item_picker.visible and remote.requests.is_empty(),"Expired turn closes the list and blocks stale item confirmation")
	remote.allowed=true;view._choose("potion");view.item_picker.activate();view.item_picker.activate()
	check(remote.requests.size()==1 and remote.requests[0].action=="potion","Confirmed multiplayer choice sends one server-authoritative action")
	check(remote.state.fighters[0].hp==5 and remote.state.fighters[0].potions==3,"Client never invents remote healing or consumes remote inventory")
	view.queue_free();await get_tree().process_frame
	var empty:=BattleItemPicker.new();add_child(empty)
	var sent:Array=[];empty.chosen.connect(func(id:String)->void:sent.append(id))
	empty.present(0,5,95,45);empty.activate()
	check(sent.is_empty() and empty.item_button.disabled and empty.description.text.contains("没有"),"Empty inventory explains why no item can be used")
	empty.present(3,95,95,45);empty.activate()
	check(sent.is_empty() and empty.item_button.disabled and empty.description.text.contains("已满"),"Full HP cannot spend a potion")
	empty.queue_free();Game.player=old;Game.save_path=old_path
	print("BATTLE ITEM PICKER: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
