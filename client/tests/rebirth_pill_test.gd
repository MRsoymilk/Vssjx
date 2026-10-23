extends Node
const ITEM:="restored/rebirth_pill"
var checks:=0
var failures:=0

func check(ok:bool,text:String)->void:
	checks+=1
	if not ok: failures+=1;push_error("REBIRTH: "+text)

func _ready()->void:_run.call_deferred()

func capture(name:String)->void:
	var folder:=OS.get_environment("SSJX_REBIRTH_CAPTURE")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(folder)
	for frame in 4:await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"Capture "+name)

func _run()->void:
	await Game.when_ready()
	var previous:=Game.player.duplicate(true);var path:=Game.save_path
	var hash:=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var pending:=OnlineAccount.pending_pve.duplicate(true)
	var scratch:="user://rebirth_test_%d.json"%Time.get_ticks_usec()
	Game.save_path=scratch
	check(ShopRules.item(ITEM).name=="重生再造丹","Use recovered original item name")
	check(ShopRules.description(ITEM).contains("属性点") and ResourceLoader.exists(ShopRules.item(ITEM).icon),"Real icon and effect description")
	for job in 3:
		Game.new_player("重生测试",job,3,job%2)
		Game.player.level=20;Game.player.gold=2000
		Game.player.allocated_attributes=[20,10,30,20,10]
		Game.player.balance_respec_available=job==1
		Game.player.hp=85;Game.player.mp=30
		var old_stats:=Game.stats()
		var free:bool=Game.player.balance_respec_available
		var identity:=[Game.player.level,Game.player.job,Game.player.school,Game.player.xp]
		check((await Game.shop_command("buy",ITEM,3)).ok and Game.player.gold==1400,"Buy stack using real save")
		var before:=Game.player.duplicate(true)
		check(not (await Game.shop_command("use",ITEM,2)).ok and Game.player==before,"Reject multiple-use request without mutation")
		check((await Game.shop_command("use",ITEM)).ok,"Use for job "+str(job))
		check(Game.allocated_attributes()==[0,0,0,0,0] and Game.attribute_profile().available==100,"All spent and unspent points available")
		check(Game.player.hp==maxi(1,85*int(Game.stats().hp)/int(old_stats.hp)) and Game.player.mp==30*int(Game.stats().mp)/int(old_stats.mp),"Preserve HP and MP ratios")
		check(Game.player.balance_respec_available==free and identity==[Game.player.level,Game.player.job,Game.player.school,Game.player.xp],"Keep identity and free reset entitlement")
		check(ShopRules.quantity(ShopRules.local_state(Game.player),ITEM)==2,"Consume exactly one")
		check((await Game.load_game()).ok and Game.allocated_attributes()==[0,0,0,0,0] and ShopRules.quantity(ShopRules.local_state(Game.player),ITEM)==2,"Reset and remaining pills survive reload")
		before=Game.player.duplicate(true)
		var no_points:=await Game.shop_command("use",ITEM)
		check(not no_points.ok and no_points.code=="NO_ALLOCATED_ATTRIBUTES" and Game.player==before,"No allocation means no wasted pill")
		check((await Game.allocate_attributes([0,0,70,10,20])).ok,"Can redistribute refunded points")
		before=Game.player.duplicate(true)
		Game.save_path="user://rebirth_missing_"+str(Time.get_ticks_usec())+"/save.json"
		check(not (await Game.shop_command("use",ITEM)).ok and Game.player==before,"Save failure rolls back both points and item")
		Game.save_path=scratch
		# Legacy local arithmetic remains consistent without forcing migration here.
		var legacy:=Game.player.duplicate(true);legacy.balance_revision=0
		legacy.hp=40;legacy.mp=20
		var limits:=CharacterAttributeRules.stats(job,20,false,legacy.allocated_attributes)
		check(ShopRules.apply_local(legacy,"use",ITEM,1,limits)=="" and legacy.allocated_attributes==[0,0,0,0,0],"Legacy attribute rule also supports pill")
	await _equipped_resets()
	await _potion_recovery()
	await _ui()
	var fixture:=OS.get_environment("SSJX_REBIRTH_FIXTURE")
	if not fixture.is_empty():
		for snapshot in JSON.parse_string(FileAccess.get_file_as_string(fixture)):
			var model:=OnlinePve.new();model.character_id=snapshot.character.id
			check(model.valid(snapshot),"Actual server snapshot validates after respec")
	DirAccess.remove_absolute(scratch)
	Game.player=previous;Game.save_path=path
	check(OnlineAccount.pending_pve==pending,"Local use never sends network requests")
	check((FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "")==hash,"Actual player save untouched")
	print("REBIRTH PILL: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _equipped_resets()->void:
	for job in 3:
		Game.new_player("装备洗点",job,3,0);Game.player.level=60;Game.player.gold=2000
		Game.player.allocated_attributes=[90,60,90,30,30]
		for slot in ["armor","hat"]:
			var template:Dictionary=ShopRules.catalog.items.filter(func(d:Dictionary)->bool:return d.slot==slot and ShopRules.equipment_error(d,job,0).is_empty())[0]
			var item:=LootRules.roll(template.id,60,"yellow",17);item.upgrade=6
			item.affixes=[{"kind":"hp_percent","value":400},{"kind":"hp","value":120},{"kind":"mana","value":80},{"kind":"defense","value":40}]
			Game.player.loot_state.items.append(item)
			check((await Game.loot_command("gear_equip",item.id)).ok,"Equip valid upgraded percentage-HP and flat HP/MP gear before resetting")
		check((await Game.shop_command("buy",ITEM,2)).ok,"Purchase reset pills with percentage gear equipped")
		var loadout:=Game.player.duplicate(true);var before:=Game.stats()
		for hp in [1,int(before.hp)/2,int(before.hp)-1,int(before.hp)]:
			Game.player=loadout.duplicate(true);Game.player.hp=hp;Game.player.mp=0 if hp==1 else int(before.mp)/2
			var previous_mp:=int(Game.player.mp);var equipment:Dictionary=Game.player.loot_state.duplicate(true)
			check((await Game.shop_command("use",ITEM)).ok,"Reset from minimum, half, almost-full and full health")
			var after:=Game.stats()
			check(Game.player.hp==maxi(1,hp*int(after.hp)/int(before.hp)) and Game.player.mp==previous_mp*int(after.mp)/int(before.mp),"Reset preserves ratios after reapplying percentage bonuses and integer rounding")
			check(Game.player.loot_state==equipment and Game.allocated_attributes()==[0,0,0,0,0],"Reset preserves UUIDs, affixes, upgrade ranks and equipped slots")
			var result:=[Game.player.hp,Game.player.mp]
			check((await Game.load_game()).ok and [Game.player.hp,Game.player.mp]==result and ShopRules.quantity(ShopRules.local_state(Game.player),ITEM)==1,"Correct ratios and exactly one consumed pill survive reload")
		Game.player=loadout.duplicate(true);Game.player.hp=int(before.hp)/2
		var saved:=Game.player.duplicate(true);var path:=Game.save_path
		Game.save_path="user://equipped_respec_missing_%d/save.json"%Time.get_ticks_usec()
		check(not (await Game.shop_command("use",ITEM)).ok and Game.player==saved,"Persistence failure rolls back percentage-gear reset and pill atomically")
		Game.save_path=path

func _potion_recovery()->void:
	for revision in [0,1]:
		for job in 3:
			for level in [1,60]:
				Game.new_player("药效验证",job,3,0);Game.player.level=level;Game.player.balance_revision=revision;Game.player.hp=1;Game.player.mp=0;Game.player.potions=6
				var stats:=Game.stats();var expected:=maxi(45,int(stats.hp)/5) if revision==1 else 45
				var enemy:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);enemy.hp=10000
				var battle:=ShushanBattle.new(enemy)
				check(battle.begin_action("potion").ok,"Battle accepts potion at low health")
				battle.resolve_player()
				check((await Game.shop_command("use","potion")).ok and Game.player.hp==1+expected and battle.hp==Game.player.hp,"World and combat potion amounts agree for every job, low/high level and old/new rules")
				check(Game.player.potions==5 and battle.potions==5 and Game.player.mp==0,"Each context consumes one potion without restoring mana")
				var text:=ShopRules.description("potion",stats)
				check(text.contains("20%") if revision==1 else text=="恢复45点气血","Description follows the active rules")
				Game.player.hp=int(stats.hp)-1
				check((await Game.shop_command("use","potion")).ok and Game.player.hp==stats.hp and Game.player.potions==4,"Potion clamps to the real maximum and consumes one")
				var full:=Game.player.duplicate(true)
				check(not (await Game.shop_command("use","potion")).ok and Game.player==full,"Full health rejects waste without consuming a potion")
	Game.player.hp=1
	var before:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://potion_missing_%d/save.json"%Time.get_ticks_usec()
	check(not (await Game.shop_command("use","potion")).ok and Game.player==before,"Failed persistence rolls back potion and percentage healing together")
	Game.save_path=path

func _ui()->void:
	Game.new_player("洗点演示",0,3,1);Game.player.level=20;Game.player.gold=2000
	Game.player.allocated_attributes=[20,10,30,20,10];Game.player.balance_respec_available=false
	Game.restore()
	check((await Game.shop_command("buy",ITEM,2)).ok,"Purchase for UI test")
	var shop:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(shop);shop.section="elixir";shop.category="药品";shop.selected=ITEM;shop._filter()
	for index in shop.category_box.item_count:
		if shop.category_box.get_item_text(index)=="药品":shop.category_box.select(index)
	check(shop.goods.any(func(row:Dictionary)->bool:return row.id==ITEM),"Listed in native elixir tab")
	check(shop.summary.text.contains("返还全部属性点"),"Shop explains real effect")
	for frame in 2:await get_tree().process_frame
	shop.scroll.ensure_control_visible(shop.rows[-1])
	await capture("shop")
	shop.queue_free();await get_tree().process_frame
	var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate()
	add_child(bag)
	for index in bag.items.size():
		if bag.items[index].id==ITEM:bag.selected_index=index
	bag.refresh();bag.open_menu()
	var usable:=false
	for child in bag.item_menu.get_children():
		if child is Button and child.text=="使用":usable=not child.disabled
	check(usable,"Respec is enabled even with full HP/MP")
	var before:=Game.player.duplicate(true)
	await bag.use_item()
	check(bag.item_menu.has_node("ConfirmAttributeReset") and Game.player==before,"Confirmation does not spend item")
	await capture("confirm")
	bag.close_menu()
	check(Game.player==before,"Cancel leaves allocation and pills intact")
	await bag.use_item()
	bag.item_menu.get_node("ConfirmAttributeReset").pressed.emit()
	for frame in 5:await get_tree().process_frame
	check(Game.allocated_attributes()==[0,0,0,0,0] and ShopRules.quantity(ShopRules.local_state(Game.player),ITEM)==1,"Real confirm button saves reset and one-item consumption")
	check(not ShopRules.use_error(ShopRules.item(ITEM),Game.player,Game.stats()).is_empty(),"No-op use visibly disabled")
	bag.queue_free();await get_tree().process_frame
