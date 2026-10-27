extends "res://tests/full_shop_test.gd"

func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var combat:=Game.local_combat
	var outbox:=OnlineAccount.pending_pve.duplicate(true);OnlineAccount.pending_pve={}
	Game.local_combat=null;Game.save_path="user://gourds_%d.json"%Time.get_ticks_usec()
	Game.new_player("葫芦验证",1,3);Game.player.gold=5000;Game.player.cell=[10,14]
	Game.player.hp=3;Game.player.mp=2
	var maxima:=Game.stats()
	check((await Game.shop_command("buy",GourdRules.HP)).ok,"Buy health container through durable local command")
	check(Game.player.hp==maxima.hp and Game.player.mp==2 and Game.player.gourds[GourdRules.HP].remaining==999999-int(maxima.hp)+3,"Purchase supplies only missing health and debits exact amount")
	check((await Game.shop_command("buy",GourdRules.MP)).ok,"Buy mana container")
	check(Game.player.mp==maxima.mp and Game.player.gourds[GourdRules.MP].remaining==999999-int(maxima.mp)+2,"Mana container cannot charge for already restored health")
	var stable:=Game.player.duplicate(true)
	check((await Game.shop_command("buy",GourdRules.HP)).code=="ITEM_ALREADY_OWNED" and Game.player==stable,"Duplicate containers cannot refill by stacking")
	check((await Game.shop_command("buy",GourdRules.HP,2)).code=="INVALID_QUANTITY","Bulk container purchases rejected")
	check((await Game.shop_command("use",GourdRules.HP)).code=="ITEM_NOT_USABLE","Container cannot be consumed as medicine")
	await Game.save_game();await Game.load_game()
	check(Game.player.hp==stable.hp and Game.player.mp==stable.mp and same_reserves(Game.player.gourds,stable.gourds),"Full resource save and reload never consume again")
	Game.player.gourds[GourdRules.HP]={"remaining":10000,"enabled":false}
	Game.player.gourds[GourdRules.MP]={"remaining":5000,"enabled":false}
	check((await Game.save_game()).ok and (await Game.load_game()).ok and same_reserves(Game.player.gourds,{GourdRules.HP:{"remaining":10000,"enabled":false},GourdRules.MP:{"remaining":5000,"enabled":false}}),"Old reserves and switches survive save/reload without a free top-up")
	Game.player=stable.duplicate(true)
	await Game.shop_command("gourd_disable",GourdRules.HP)
	Game.player.hp=1;Game.player.gourds[GourdRules.HP].remaining=7
	await Game.save_game();await Game.load_game()
	check(Game.player.hp==1 and not Game.player.gourds[GourdRules.HP].enabled,"Off switch persists and prevents login supply")
	check((await Game.shop_command("gourd_enable",GourdRules.HP)).ok and Game.player.hp==8 and Game.player.gourds[GourdRules.HP].remaining==0,"Insufficient reserve supplies partially, retaining the empty bottle")
	check(ShopRules.quantity(ShopRules.local_state(Game.player),GourdRules.HP)==1,"Empty container still occupies one inventory slot")
	stable=Game.player.duplicate(true);var good_path:=Game.save_path;Game.save_path="invalid://gourd-failure"
	check(not (await Game.shop_command("gourd_refill_hp","qingwei")).ok and Game.player==stable,"Failed refill save rolls health and reserve back together")
	Game.save_path=good_path
	Game.player.cell=[1,1]
	check((await Game.shop_command("gourd_refill_hp","qingwei")).code=="RESIDENT_TOO_FAR","Cannot refill remotely")
	Game.player.cell=[10,14]
	check((await Game.shop_command("gourd_refill_hp","wolf_a")).code=="GOURD_NPC_REQUIRED","Monster cannot provide a refill")
	var gold:int=Game.player.gold
	check((await Game.shop_command("gourd_refill_hp","qingwei")).ok and Game.player.hp==maxima.hp and Game.player.gold==gold,"Nearby provider refills for free then enabled supply heals missing health")
	await Game.shop_command("gourd_disable",GourdRules.HP)
	await Game.shop_command("gourd_refill_hp","qingwei")
	check(Game.player.gourds[GourdRules.HP].remaining==999999 and not Game.player.gourds[GourdRules.HP].enabled,"Refill preserves the off switch")
	check((await Game.shop_command("gourd_refill_hp","qingwei")).code=="GOURD_FULL","Full reserve cannot be refilled again")
	await Game.shop_command("gourd_enable",GourdRules.HP)
	Game.player.hp=1;stable=Game.player.duplicate(true);Game.save_path="invalid://gourd-failure"
	check(not (await Game.save_game()).ok and Game.player==stable,"Automatic supply itself rolls back if persistence fails")
	Game.save_path=good_path
	# A disk snapshot may contain damage from an interrupted older client.
	FileAccess.open(good_path,FileAccess.WRITE).store_string(JSON.stringify(Game.player))
	check((await Game.load_game()).ok and Game.player.hp==Game.stats().hp,"Loading an injured noncombat save atomically supplies before returning")
	stable=Game.player.duplicate(true);await Game.load_game()
	check(Game.player==stable,"Second load cannot repeat consumption")
	var invalid:=Game.player.duplicate(true);invalid.gourds[GourdRules.HP].remaining=-1
	check(not Game.valid_save(invalid),"Negative reserve invalidates a save")
	invalid=Game.player.duplicate(true);invalid.gourds[GourdRules.HP].remaining=1000000
	check(not Game.valid_save(invalid),"Over-capacity reserve invalidates a save")
	for id in GourdRules.IDS:
		invalid=Game.player.duplicate(true);invalid.gourds[id].remaining=999999
		check(Game.valid_save(invalid),"New maximum reserve is valid for "+id)
		invalid.gourds[id].remaining=1000000
		check(not Game.valid_save(invalid),"One above the new maximum is rejected for "+id)
	invalid=Game.player.duplicate(true);invalid.gourds.erase(GourdRules.HP)
	check(not Game.valid_save(invalid),"Owned bottle cannot silently regain missing reserve")
	var engine:=ShushanBattle.new(ShushanWorld.ENEMIES[0]);Game.local_combat=weakref(engine)
	Game.player.hp=10;Game.player.mp=1;var reserves:Dictionary=Game.player.gourds.duplicate(true)
	await Game.save_game()
	check(Game.player.hp==10 and Game.player.mp==1 and Game.player.gourds==reserves,"Saving during live legacy battle cannot auto-supply")
	check((await Game.shop_command("gourd_refill_mp","qingwei")).code=="BATTLE_ACTIVE","Live battle rejects refill")
	engine.hp=10;engine.mp=1;engine.finished=true;engine.phase="finished";engine.escaped=true
	await engine.commit()
	check(Game.player.hp==maxima.hp and Game.player.mp==maxima.mp,"Actual legacy flee settlement supplies both resources")
	check(engine.hp==10 and engine.mp==1,"Final combat snapshot remains pre-supply for presentation")
	Game.local_combat=null
	Game.player.hp=10;Game.player.mp=1
	var encounter:=SoloEncounter.new();encounter.start([ShushanWorld.ENEMIES[0]]);Game.local_combat=weakref(encounter)
	reserves=Game.player.gourds.duplicate(true);await Game.save_game()
	check(Game.player.hp==10 and Game.player.gourds==reserves,"Formation battle also blocks automatic supply")
	encounter.state.outcome="fled";await encounter._commit()
	check(encounter.save_result.ok and Game.player.hp==maxima.hp and encounter.state.fighters[0].hp==10,"Formation settlement heals only persistent world state")
	stable=Game.player.duplicate(true);await encounter._commit();check(Game.player==stable,"Duplicate settlement does not consume twice")
	Game.local_combat=null;Game.player.hp=0;reserves=Game.player.gourds.duplicate(true);await Game.save_game()
	check(Game.player.hp==0 and Game.player.gourds==reserves,"Zero health without a corpse cannot be revived by supply")
	Game.become_soul();await Game.save_game();await Game.load_game()
	check(Game.is_soul() and Game.player.hp==0 and same_reserves(Game.player.gourds,reserves),"Death and reload keep both reserves intact")
	Game.player.corpse=null;Game.restore()
	Game.player.gourds[GourdRules.HP].remaining=0;Game.player.gourds[GourdRules.MP].remaining=12
	await _ui()
	var input:=OS.get_environment("SSJX_GOURD_FIXTURES")
	check(not input.is_empty(),"Gourd network regression requires real server snapshots")
	if not input.is_empty():await _online(JSON.parse_string(FileAccess.get_file_as_string(input)))
	check(OnlineAccount.pending_pve.is_empty(),"Offline operations do not use the online outbox")
	DirAccess.remove_absolute(good_path);Game.player=old;Game.save_path=path;Game.local_combat=combat;OnlineAccount.pending_pve=outbox
	print("GOURDS CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func same_reserves(a:Dictionary,b:Dictionary)->bool:
	return a.size()==b.size() and a.keys().all(func(id:String)->bool:return b.has(id) and a[id].remaining==b[id].remaining and a[id].enabled==b[id].enabled)

func _ui()->void:
	var shop:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate();add_child(shop)
	shop.selected=GourdRules.HP;shop.refresh()
	check(shop.goods[0].id==GourdRules.HP and shop.goods[1].id==GourdRules.MP,"Both supplies are visible first in the mall")
	check(shop.quantity_box.max_value==1 and shop.buy_button.disabled and shop.summary.text.contains("999999"),"Shop shows capacity and prevents duplicate purchase")
	await get_tree().process_frame
	check(shop.summary.get_line_count()<=2 and shop.summary.position.y+shop.summary.size.y<=shop.total.position.y,"Gourd summary fits above the price without overlap")
	await capture("gourds-shop");shop.queue_free();await get_tree().process_frame
	var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(bag)
	bag.select_item(bag.items.find_custom(func(i:Dictionary)->bool:return i.id==GourdRules.HP))
	check(bag.description.text.contains("0/999999") and bag.description.text.contains("自动开"),"Backpack displays empty reserve, capacity and switch")
	check(bag.description.get_theme_font("font").get_string_size(bag.description.text,HORIZONTAL_ALIGNMENT_LEFT,-1,bag.description.get_theme_font_size("font_size")).x<=bag.description.size.x,"Reserve and switch fit the inventory footer")
	for id in GourdRules.IDS:
		var remaining:int=Game.player.gourds[id].remaining
		Game.player.gourds[id].remaining=999999
		bag.select_item(bag.items.find_custom(func(i:Dictionary)->bool:return i.id==id))
		check(bag.description.text.contains("999999/999999") and bag.description.get_theme_font("font").get_string_size(bag.description.text,HORIZONTAL_ALIGNMENT_LEFT,-1,bag.description.get_theme_font_size("font_size")).x<=bag.description.size.x,"Full six-digit reserve and capacity fit the footer for "+id)
		await capture("gourds-full-"+ShopRules.item(id).resource)
		Game.player.gourds[id].remaining=remaining
	bag.select_item(bag.items.find_custom(func(i:Dictionary)->bool:return i.id==GourdRules.HP))
	await capture("gourds-bag-reserve");bag.show_item()
	check(bag.tooltip_label.text.contains("清微道人") and bag.tooltip_label.position.y+bag.tooltip_label.get_minimum_size().y<=bag.tooltip.size.y,"Container detail names providers and fits the tooltip")
	await capture("gourds-bag-details");bag.open_menu()
	check(bag.item_menu.find_children("*","Button",true,false).any(func(b:Button)->bool:return b.text=="关闭自动补给"),"Backpack exposes the automatic supply switch")
	await capture("gourds-bag");await bag.toggle_gourd()
	check(not Game.player.gourds[GourdRules.HP].enabled,"Actual bag toggle persists off state")
	bag.queue_free();await get_tree().process_frame
	var dialog:OriginalNpcDialog=load("res://scenes/ui/npc_dialog.tscn").instantiate();add_child(dialog)
	dialog.present_local({"id":"qingwei","name":"清微道人"})
	check(dialog.allows("gourd_refill_hp","qingwei") and dialog.allows("gourd_refill_mp","qingwei"),"Provider offers two independent refill services")
	check(dialog.get_node("Paper").size.y<400 and dialog.hint.position.y>dialog.get_node("Paper/RefillMp").position.y,"Refill controls fit beside the school choices")
	await capture("gourds-npc");dialog.queue_free();await get_tree().process_frame
	Game.player.ai_map="ai_001";var resident:=AIWorld.resident("ai_001_guide");Game.player.cell=resident.cell.duplicate()
	check((await Game.shop_command("gourd_refill_hp","ai_001_guide")).ok,"AI map guide supplies the same reusable container")
	dialog=load("res://scenes/ui/npc_dialog.tscn").instantiate();add_child(dialog)
	dialog.present_ai("ai_001_guide",resident,AIWorld.progress(),int(Game.player.level))
	check(not dialog.allows("gourd_refill_hp","ai_001_guide") and dialog.allows("gourd_refill_mp","ai_001_guide"),"AI provider independently disables only the full reserve")
	await capture("gourds-ai-npc");dialog.queue_free();await get_tree().process_frame
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world()
	app._open_ai_npc("ai_001_guide");app.modal.get_node("Paper/RefillMp").pressed.emit()
	await get_tree().process_frame
	check(Game.player.gourds[GourdRules.MP].remaining==999999 and app.modal.get_node("Paper/RefillMp").disabled,"Actual local NPC button routes through distance validation and durable refill")
	await capture("gourds-world-refill");app.queue_free();await get_tree().process_frame

func _online(records:Array)->void:
	var models:={}
	for packet in records:
		var id:String=packet.state.character.id
		if not models.has(id):models[id]=OnlinePve.new();models[id].bind_character(id,"fixture")
		var model:OnlinePve=models[id]
		var revision:int=int(model.state.get("character",{}).get("state_revision",0))
		check(model.receive(packet),"Real server gourd state passes production decoder")
		check(int(model.state.character.state_revision)>=revision,"Old receipts cannot roll back gourd revision")
		if packet.state.gourds.is_empty():continue
		var bad:Dictionary=packet.state.duplicate(true);var key:String=bad.gourds.keys()[0]
		bad.gourds[key].remaining=int(ShopRules.item(key).capacity)+1
		check(not model.valid(bad),"Network refuses forged capacity")
		bad=packet.state.duplicate(true);bad.gourds[key].enabled=1
		check(not model.valid(bad),"Network refuses a non-boolean switch")
		bad=packet.state.duplicate(true);bad.erase("gourds")
		check(not model.valid(bad),"Network refuses missing reserve for an owned container")
	var model:OnlinePve=models[records[0].state.character.id]
	# Render a real noncombat response through the regular online inventory.
	for packet in records:
		if packet.state.character.corpse!=null or packet.state.battle!=null or not packet.state.gourds.has(GourdRules.HP):continue
		model.state=packet.state.duplicate(true);model.ready=true
		var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();bag.online_model=model;add_child(bag)
		bag.select_item(bag.items.find_custom(func(i:Dictionary)->bool:return i.id==GourdRules.HP))
		check(bag.description.text.contains(GourdRules.status(GourdRules.HP,model.state.gourds)),"Online bag reads authoritative reserve")
		await bag.toggle_gourd()
		check(model.pending() and OnlineAccount.pending_pve.command.target==GourdRules.HP and OnlineAccount.pending_pve.command.expected_revision==model.state.character.state_revision,"Online switch sends only identity and expected revision")
		OnlineAccount.pending_pve={};bag.refresh();await capture("gourds-online-bag")
		bag.queue_free();await get_tree().process_frame;break
