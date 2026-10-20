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
