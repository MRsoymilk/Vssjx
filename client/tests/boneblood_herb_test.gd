extends Node
const ID := "original/ix10"
var checks := 0
var failures := 0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _ready()->void:
	await Game.when_ready()
	var herb:=ShopRules.item(ID)
	check(herb.name=="生骨融血草" and herb.slot=="consumable" and herb.restore_hp==8000 and herb.restore_mp==0,"Confirmed name and fixed recovery")
	check(herb.price==10 and herb.sections==["hot","elixir"],"Existing price and medicine shop tabs")
	check(ShopRules.description(ID).contains("8000") and ShopRules.description(ID).contains("战斗外"),"Shop and bag explain recovery and use restriction")
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://herb_test_%d.json"%OS.get_process_id()
	Game.new_player("草药验证",0,3);Game.player.gold=100
	check((await Game.shop_command("buy",ID,2)).ok,"Buy the existing original resource ID")
	check(Game.player.gold==80 and ShopRules.quantity(ShopRules.local_state(Game.player),ID)==2,"Exact quantity and price saved")
	for maximum in [20000,100000]:
		var sample:=Game.player.duplicate(true);sample.hp=1;sample.mp=7
		check(ShopRules.apply_local(sample,"use",ID,1,{"hp":maximum,"mp":100,"balance":{"skills_revision":1}})=="","Herb uses existing medicine consumer")
		check(sample.hp==8001 and sample.mp==7,"Exactly 8000 HP regardless of maximum HP; mana unchanged")
	Game.player.hp=1
	check((await Game.shop_command("use",ID)).ok and Game.player.hp==int(Game.stats().hp),"Actual saved character clamps healing to its HP limit")
	check(ShopRules.quantity(ShopRules.local_state(Game.player),ID)==1,"Using one consumes exactly one")
	check((await Game.load_game()).ok and ShopRules.quantity(ShopRules.local_state(Game.player),ID)==1,"Existing ID quantity survives reload")
	var before:=Game.player.duplicate(true)
	check(not (await Game.shop_command("use",ID)).ok and Game.player==before,"Full HP does not waste the herb")
	var catalog=load("res://scripts/admin/data_catalog.gd").new();catalog.reload()
	var entries:Array=catalog.find("items","生骨融血草","原包资源")
	check(entries.size()==1 and entries[0].data["原版名称"]=="生骨融血草" and entries[0].data["原版属性"]["恢复气血"]==8000,"Resource manager exposes only confirmed original facts")
	var page:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate();add_child(page)
	page._select_section("elixir")
	var rows:Array=page.rows.filter(func(row:Button)->bool:return row.get_meta("item_id")==ID)
	check(rows.size()==1,"Medicine tab contains the herb")
	if not rows.is_empty():
		rows[0].pressed.emit()
		check(rows[0].get_node("ItemName").text==herb.name and rows[0].get_node("Icon").texture.resource_path==herb.icon,"Original icon and confirmed name render together")
		check(page.hint.text.contains("战斗外") and page.hint.text.contains("不消耗"),"Shop explains useful medicine restrictions")
		for frame in 2:await get_tree().process_frame
		page.scroll.ensure_control_visible(rows[0])
	var output:=OS.get_environment("SSJX_HERB_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Medicine shop screenshot")
	page.queue_free();DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path
	print("BONEBLOOD HERB: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
