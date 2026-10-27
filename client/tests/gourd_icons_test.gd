extends "res://tests/full_shop_test.gd"

func _run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://gourd_icons_%d.json"%Time.get_ticks_usec();Game.new_player("葫芦图标",1,3)
	Game.player.gold=1000
	var before_hash:=ShopRules.catalog_hash
	var mapping:={GourdRules.HP:"res://assets/items/original/ix62.png",GourdRules.MP:"res://assets/items/original/ix63.png"}
	for id in mapping:
		var entry:=ShopRules.item(id);var texture:Texture2D=load(ShopRules.icon_path(entry))
		check(texture!=null and texture.resource_path==mapping[id],"Uses the exact user-selected existing red/blue gourd: "+id)
		check(texture.get_image().get_data()==load(mapping[id]).get_image().get_data(),"Reuses source pixels without recoloring or redrawing: "+id)
		check((await Game.shop_command("buy",id)).ok,"Existing gourd purchase and reserve remain functional: "+id)
	check(ShopRules.icon_path(ShopRules.item("original/ix22"))==ShopRules.item("original/ix22").get("icon"),"Other recovered items retain their original art")
	check(ShopRules.catalog_hash==before_hash and before_hash==FileAccess.get_file_as_string("res://assets/data/shop-v2.json").replace("\r\n","\n").sha256_text(),"Display overrides leave the server catalog and hash unchanged")
	var shop:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate();add_child(shop)
	shop.selected=GourdRules.HP;shop.refresh()
	for id in mapping:
		var row:Button=shop.rows.filter(func(value:Button)->bool:return value.get_meta("item_id")==id)[0]
		check(row.get_node("Icon").texture.resource_path==mapping[id],"Mall shows the selected original gourd: "+id)
	await capture("gourds-original-shop");shop.queue_free();await get_tree().process_frame
	var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(bag)
	for id in mapping:
		var index:=bag.items.find_custom(func(entry:Dictionary)->bool:return entry.id==id)
		bag.select_item(index)
		var icon:TextureRect=bag.grid.get_child(index-bag.offset).get_node("Panel/Icon")
		check(icon.texture.resource_path==mapping[id],"Backpack shows the same original gourd: "+id)
	check(Game.player.gourds[GourdRules.HP].remaining==999999 and Game.player.gourds[GourdRules.MP].remaining==999999,"Art changes leave capacities and reserves intact")
	await capture("gourds-original-inventory");bag.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path);Game.player=old;Game.save_path=path
	print("GOURD ICONS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
