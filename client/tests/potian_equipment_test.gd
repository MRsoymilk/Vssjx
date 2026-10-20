extends Node
const ITEM := "ai/legendary/potian_axe"
const MAPPING := preload("res://scripts/admin/equipment_appearance.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("POTIAN: "+message)

func _ready() -> void: _run.call_deferred()

func capture(name: String) -> void:
	var folder:=OS.get_environment("SSJX_POTIAN_CAPTURE")
	if folder.is_empty() or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(folder)
	for frame in 4: await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"Capture "+name)

func _run() -> void:
	await Platform.when_ready()
	var previous:=Game.player.duplicate(true)
	var previous_path:=Game.save_path
	var previous_hash:=FileAccess.get_sha256(previous_path) if FileAccess.file_exists(previous_path) else ""
	var pending:=OnlineAccount.pending_pve.duplicate(true)
	var scratch:="user://potian_test_%d.json"%Time.get_ticks_usec()
	Game.save_path=scratch
	var entry:=ShopRules.item(ITEM)
	check(entry.name=="破天斧" and entry.job==0 and entry.gender==-1,"One weapon for male/female lishi")
	for gender in 2:
		Game.new_player("破天斧测试",0,0,gender)
		Game.player.gold=1000
		check((await Game.shop_command("buy",ITEM)).ok,"Buy and save")
		check(Game.player.gold==750,"Deduct authoritative price")
		check((await Game.shop_command("equip",ITEM)).ok,"Equip and save")
		check(ShopRules.appearance(ShopRules.local_state(Game.player))==[46,0,0],"Standalone weapon leaves head and clothing native")
		check(ShopRules.bonus(ShopRules.local_state(Game.player)).x==20,"Weapon contributes attack")
		check((await Game.load_game()).ok and ShopRules.local_state(Game.player).weapon==ITEM,"Equip persists after reload")
		var foreign:=Game.player.duplicate(true)
		for job in [1,2]:
			foreign.job=job
			check(ShopRules.apply_local(foreign,"equip",ITEM)=="WRONG_JOB","Reject non-lishi")
		var stem:="mzs" if gender==0 else "wzs"
		var native:=OriginalArt.actor_info("hero/"+stem)
		for look in [[46,0,0],[46,3,2],[46,12+gender,10+gender],[46,18+gender,16+gender],[46,24+gender,22+gender]]:
			var key:=ShopRules.actor_key(0,gender,look)
			check(HeroAppearance.is_key(key),"Valid standalone/mixed appearance")
			var built:=HeroAppearance.build(key,native)
			check(not built.is_empty() and built.info.playback==native.playback,"Retain original movement and battle recipes")
			var actor:=OriginalArt.battle_actor(key)
			for action in native.playback:
				check(actor.sprite_frames.get_frame_count(action)==native.playback[action].size(),"Native animation "+action)
			actor.free()
		var mapping:=MAPPING.variant(entry,0,gender)
		check(mapping["装备后部件"]["武器"]==["legendary/potian_axe"],"Admin preview maps to actual approved axe")
		var shop:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate()
		add_child(shop)
		shop.category="传世兵器 · 本角色";shop._filter()
		for index in shop.category_box.item_count:
			if shop.category_box.get_item_text(index)==shop.category: shop.category_box.select(index)
		check(shop.goods.size()==1 and shop.goods[0].id==ITEM,"Discoverable themed shop category")
		shop.selected=ITEM;shop.refresh()
		await capture("shop-"+stem)
		shop.queue_free();await get_tree().process_frame
		var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate()
		add_child(bag)
		check(bag.preview.get_meta("art_key")==Game.appearance_key(),"Inventory displays equipped axe")
		check(ShopRules.bag_item(ITEM).icon==entry.icon,"Bag uses approved image icon")
		await capture("bag-"+stem)
		bag.queue_free();await get_tree().process_frame
		check((await Game.shop_command("unequip",ITEM)).ok,"Unequip")
		check(ShopRules.appearance(ShopRules.local_state(Game.player))==[0,0,0],"Restore bare hands")
	check(not HeroAppearance.is_key("hero/mck_w46_c0_h0"),"Reject weapon appearance on other jobs")
	check(OnlineAccount.pending_pve==pending,"Local actions do not send online requests")
	var fixture:=OS.get_environment("SSJX_POTIAN_FIXTURE")
	if not fixture.is_empty():
		var rows:Array=JSON.parse_string(FileAccess.get_file_as_string(fixture))
		for row in rows:
			var model:=OnlinePve.new();model.character_id=row.character.id
			check(model.valid(row.state),"Accept actual server equipment state")
			var online_look:Array=row.character.appearance_v2.map(func(value:Variant)->int:return int(value))
			check(ShopRules.appearance(row.state.shop)==online_look,"Roster and live state share the same appearance")
			var key:=ShopRules.actor_key(int(row.character.job),int(row.character.gender),row.character.appearance_v2)
			var actor:=OriginalArt.actor(key)
			check(actor.get_meta("art_key")==key,"Render actual online appearance")
			actor.free()
	await _review()
	DirAccess.remove_absolute(scratch)
	Game.player=previous;Game.save_path=previous_path
	check(not FileAccess.file_exists(previous_path) or FileAccess.get_sha256(previous_path)==previous_hash,"Preserve actual save")
	print("POTIAN EQUIPMENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _review() -> void:
	if OS.get_environment("SSJX_POTIAN_CAPTURE").is_empty(): return
	get_window().size=Vector2i(840,660)
	get_window().content_scale_size=Vector2i(840,660)
	var canvas:=Control.new();canvas.theme=load("res://scenes/ui/online_pve_theme.tres")
	add_child(canvas)
	var bg:=ColorRect.new();bg.size=Vector2(840,660);bg.color=Color("6cca9b");canvas.add_child(bg)
	var row:=0
	for gender in 2:
		for clothing in [0,12+gender]:
			var key:=ShopRules.actor_key(0,gender,[46,clothing,10+gender if clothing else 0])
			var col:=0
			for action in ["idle","walk","attack","hurt"]:
				var label:=Label.new();label.text=("男" if gender==0 else "女")+"力士 · "+action
				label.position=Vector2(20+col*210,10+row*150);label.add_theme_color_override("font_color",Color("654518"));canvas.add_child(label)
				var actor:=OriginalArt.actor(key);canvas.add_child(actor)
				actor.position=Vector2(90+col*210,135+row*150);actor.scale=Vector2.ONE*2
				actor.play(action);actor.pause();actor.frame=mini(2,actor.sprite_frames.get_frame_count(action)-1)
				col+=1
			row+=1
	await capture("poses")
