extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FULL SHOP: "+message)
func _ready() -> void:_run.call_deferred()
func capture(name: String) -> void:
	var path:=OS.get_environment("SSJX_SHOP_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path.path_join(name+".png"))
func _run() -> void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	var pending:=OnlineAccount.pending_pve.duplicate(true)
	Game.new_player("全量商店",1,0,1)
	Game.save_path="user://full_shop_%d.json"%Time.get_ticks_usec()
	Game.player.gold=500000
	var source_count:=0
	for item in ShopRules.catalog.items:
		if not String(item.id).begins_with("original/"):continue
		source_count+=1
		var p:=Game.player.duplicate(true)
		p.job=int(item.job) if int(item.job)>=0 else 1
		p.hp=1;p.mp=0
		var gear:=ShopRules.is_equipment(item)
		var quantity:=1 if gear else 2
		check(ShopRules.apply_local(p,"buy",item.id,quantity)=="","Buy "+item.id)
		check(ShopRules.quantity(ShopRules.local_state(p),item.id)==quantity,"Store quantity "+item.id)
		if gear:
			check(ShopRules.apply_local(p,"equip",item.id)=="","Equip "+item.id)
			check(ShopRules.equipped_id(ShopRules.local_state(p),item.slot)==item.id,"Correct slot "+item.id)
			for gender in 2:
				var key:=ShopRules.actor_key(int(p.job),gender,ShopRules.appearance(ShopRules.local_state(p)))
				var sprite:=OriginalArt.actor(key)
				check(sprite.sprite_frames!=null and sprite.get_meta("art_key","")==key,"Both genders render "+item.id)
				sprite.free()
		elif item.slot=="consumable":
			check(ShopRules.apply_local(p,"use",item.id,1,{"hp":120,"mp":60})=="","Medicine usable "+item.id)
			check(int(p.hp)==mini(120,1+int(item.restore_hp)) and int(p.mp)==mini(60,int(item.restore_mp)),"Restore correct resources "+item.id)
			quantity-=1
		check(ShopRules.apply_local(p,"discard",item.id,quantity)=="" and not ShopRules.local_state(p).owned.has(item.id),"Discard "+item.id)
	check(source_count==208,"All recovered items are functional")
	var page:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(page)
	check(page.rows.size()==459 and page.grid.columns==2,"Complete two-column catalog including ceremonial outfits and supply gourds")
	for row in page.rows:
		check(row.get_node("Icon").texture!=null,"Actual product icon "+String(row.get_meta("item_id")))
	page.category="帽子";page.category_box.select(2);page._filter()
	check(page.goods.size()==33 and page.goods.all(func(i:Dictionary)->bool:return i.slot=="hat"),"Nine original and twenty-four generated hats in their own category")
	page.selected=page.goods[4].id;page.refresh()
	await capture("shop_hats")
	page.preview_window.show();await capture("shop_head_preview");page.preview_window.hide()
	for slot in ShopRules.SLOTS:
		var options:Array=ShopRules.catalog.items.filter(func(i:Dictionary)->bool:return i.slot==slot and (int(i.job)<0 or int(i.job)==1))
		var item:Dictionary=options[mini(4,options.size()-1)]
		check((await Game.shop_command("buy",item.id)).ok and (await Game.shop_command("equip",item.id)).ok,"Durable full loadout "+slot)
	check(Game.valid_save(Game.player),"Full loadout is a valid save")
	var bad:=Game.player.duplicate(true);bad.shop_slots.weapon=null
	check(not Game.valid_save(bad),"Conflicting equipped slots rejected")
	check((await Game.load_game()).ok and ShopRules.appearance(ShopRules.local_state(Game.player))[2]>0,"Head appearance persists")
	page.category="药品";page.category_box.select(11);page.section="elixir";page._filter()
	check(page.goods.size()>20 and page.goods.all(func(i:Dictionary)->bool:return i.slot in ["consumable","gourd"]),"Medicines and refillable gourds have a separate native tab and category")
	var medicine:Dictionary=page.goods.filter(func(i:Dictionary)->bool:return int(i.restore_mp)>0 and int(i.restore_hp)==0)[0]
	page.selected=medicine.id;page.refresh();page.quantity_box.value=5
	check(int(page.quantity_box.max_value)==99 and page.total.text.contains(str(int(medicine.price)*5)),"Quantity updates purchase total")
	await page._command("buy")
	check(ShopRules.quantity(ShopRules.local_state(Game.player),medicine.id)==5,"Bulk purchase persists exact stack")
	await capture("shop_medicines")
	Game.player.mp=0
	check((await Game.shop_command("use",medicine.id)).ok and int(Game.player.mp)>0,"MP medicine works locally")
	Game.player.mp=Game.stats().mp
	var before:=Game.player.duplicate(true)
	check(not (await Game.shop_command("use",medicine.id)).ok and Game.player==before,"Full resource refuses waste")
	page.queue_free();await get_tree().process_frame
	var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate()
	add_child(bag)
	check(bag.equipment_icon.visible and bag.slot_icons.values().all(func(icon:TextureRect)->bool:return icon.visible and icon.texture!=null),"All ten equipment slots show real icons")
	bag._select_equipment(9)
	check(bag._selected().slot=="hat","Head slot selects equipped hat")
	await capture("bag_all_equipment")
	bag.queue_free();await get_tree().process_frame
	check(OnlineAccount.pending_pve==pending,"Local catalog operations never report online")
	DirAccess.remove_absolute(Game.save_path)
	Game.player=old;Game.save_path=old_path
	print("FULL SHOP: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
