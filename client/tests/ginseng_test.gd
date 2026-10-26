extends Node
const ID := "original/ix14"
var checks := 0
var failures := 0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _ready()->void:
	await Game.when_ready()
	var item:=ShopRules.item(ID)
	check(item.name=="极品人参" and item.restore_hp==0 and item.restore_mp==4000 and item.slot=="consumable","Confirmed original ginseng restores mana")
	check(item.price==10 and item.sections==["hot","elixir"],"Same original ID and price in medicine tabs")
	check(ShopRules.description(ID).contains("4000点灵力") and ShopRules.description(ID).contains("战斗外"),"Bag and shop describe actual recovery")
	check(OnlinePve.error_text("HP_FULL").contains("灵力"),"Full-mana refusal does not incorrectly claim only health is full")
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://ginseng_test_%d.json"%OS.get_process_id()
	Game.new_player("人参验证",0,3);Game.player.gold=100
	check((await Game.shop_command("buy",ID,2)).ok and Game.player.gold==80,"Purchase retains 10-copper price")
	for maximum in [10000,20000]:
		var sample:=Game.player.duplicate(true);sample.hp=1;sample.mp=7
		check(ShopRules.apply_local(sample,"use",ID,1,{"hp":100,"mp":maximum,"balance":{"skills_revision":1}})=="","Use through ordinary medicine consumer")
		check(sample.mp==4007 and sample.hp==1,"Exactly 4000 mana at different maxima without healing HP")
	Game.player.hp=1;Game.player.mp=0
	check((await Game.shop_command("use",ID)).ok and Game.player.mp==int(Game.stats().mp) and Game.player.hp==1,"Persisted use respects the mana limit and does not heal HP")
	check((await Game.load_game()).ok and ShopRules.quantity(ShopRules.local_state(Game.player),ID)==1,"Original ID and remaining count survive reload")
	var before:=Game.player.duplicate(true)
	check(not (await Game.shop_command("use",ID)).ok and Game.player==before,"Full mana does not waste ginseng even when HP is missing")
	var catalog=load("res://scripts/admin/data_catalog.gd").new();catalog.reload()
	var entries:Array=catalog.find("items","极品人参","原包资源")
	check(entries.size()==1 and entries[0].data["原版名称"]=="极品人参" and entries[0].data["原版属性"]=={"恢复灵力":4000},"Resource manager records confirmed mana recovery")
	var herb:Array=catalog.find("items","生骨融血草","原包资源")
	check(herb.size()==1 and herb[0].data["原版属性"]=={"恢复气血":8000},"Existing confirmed HP herb remains intact")
	var page:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate();add_child(page);page._select_section("elixir")
	var rows:Array=page.rows.filter(func(row:Button)->bool:return row.get_meta("item_id")==ID)
	check(rows.size()==1,"Ginseng is selectable in medicine shop")
	if not rows.is_empty():
		rows[0].pressed.emit()
		check(rows[0].get_node("ItemName").text==item.name and rows[0].get_node("Icon").texture.resource_path==item.icon,"Original icon matches the confirmed name")
		check(page.hint.text.contains("灵力已满") and not page.hint.text.contains("气血已满"),"Mana medicine uses the correct full-resource notice")
		for frame in 2:await get_tree().process_frame
		page.scroll.ensure_control_visible(rows[0])
	var output:=OS.get_environment("SSJX_GINSENG_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Ginseng shop screenshot")
	page.queue_free();DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path
	print("GINSENG: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
