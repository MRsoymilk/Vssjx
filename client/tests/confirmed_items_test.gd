extends Node
const MEDICINES:=[
	[10,"生骨融血草",8000,0],[14,"极品人参",0,4000],
	[15,"金疮药",500,0],[16,"小金疮药",800,0],[17,"中金疮药",1000,0],[18,"大金疮药",1500,0],[26,"荷叶烧鸡",6000,0],
]
const STONES:=[[31,"敏捷"],[32,"力量"],[33,"体质"],[34,"灵性"],[35,"定力"]]
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://confirmed_items_%d.json"%OS.get_process_id()
	Game.new_player("物品验证",0,3);Game.player.gold=10000
	var catalog=load("res://scripts/admin/data_catalog.gd").new();catalog.reload()
	check(catalog.errors.is_empty(),"Resource catalog loads all originals")
	var page:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate();add_child(page)
	for spec in MEDICINES:
		var id:="original/ix%d"%spec[0];var item:=ShopRules.item(id)
		check(item.name==spec[1] and item.restore_hp==spec[2] and item.restore_mp==spec[3],"Confirmed medicine "+id)
		check(item.icon=="res://assets/items/original/ix%d.png"%spec[0],"Original icon remains "+id)
		check((await Game.shop_command("buy",id,3)).ok,"Purchase medicine "+id)
		for maximum in [20000,100000]:
			var sample:=Game.player.duplicate(true);sample.hp=1;sample.mp=7
			check(ShopRules.apply_local(sample,"use",id,1,{"hp":maximum,"mp":maximum,"balance":{"skills_revision":1}})=="","Use medicine "+id)
			check(sample.hp==1+int(spec[2]) and sample.mp==7+int(spec[3]),"Fixed recovery independent of maxima "+id)
			check(ShopRules.quantity(ShopRules.local_state(sample),id)==2,"Exactly one item consumed "+id)
		var sample:=Game.player.duplicate(true);sample.hp=100;sample.mp=100
		var before:=sample.duplicate(true)
		check(ShopRules.apply_local(sample,"use",id,1,{"hp":100,"mp":100})=="HP_FULL" and sample==before,"Full resource preserves inventory "+id)
		sample.hp=99 if int(spec[2])>0 else 100;sample.mp=99 if int(spec[3])>0 else 100
		check(ShopRules.apply_local(sample,"use",id,1,{"hp":100,"mp":100})=="" and sample.hp==100 and sample.mp==100,"Recovery clamps to maxima "+id)
		var entries:Array=catalog.find("items",spec[1],"原包资源").filter(func(e:Dictionary)->bool:return e.id==id)
		check(entries.size()==1 and entries[0].data["原版名称"]==spec[1],"Resource manager links confirmed name "+id)
		check(entries[0].data["原版属性"]==({"恢复气血":spec[2]} if int(spec[2])>0 else {"恢复灵力":spec[3]}),"Admin recovery matches consumer "+id)
		page._select_section("elixir");page.selected=id;page.refresh()
		check(page.rows.any(func(row:Button)->bool:return row.get_meta("item_id")==id and row.get_node("ItemName").text==spec[1]),"Medicine tab renders confirmed name "+id)
		check(page.summary.text.contains(str(maxi(spec[2],spec[3]))) and page.hint.text.contains("战斗外"),"Medicine detail shows amount and restriction "+id)
	for spec in STONES:
		var id:="original/ix%d"%spec[0];var item:=ShopRules.item(id)
		check(item.name==spec[1]+"石" and item.attribute==spec[1] and item.slot=="material" and item.category=="宝石","Stone identity and attribute "+id)
		check((await Game.shop_command("buy",id,2)).ok,"Purchase stone "+id)
		var before:=Game.player.duplicate(true)
		check((await Game.shop_command("use",id)).code=="ITEM_NOT_USABLE" and Game.player==before,"Material use cannot grant invented attributes or waste stones "+id)
		var entries:Array=catalog.find("items",id,"原包资源")
		check(entries.size()==1 and entries[0].data["原版属性"]=={"对应属性":spec[1],"属性增量":null},"Admin retains confirmed type and unknown amount "+id)
		page._select_section("craft");page.selected=id;page.refresh()
		check(page.rows.any(func(row:Button)->bool:return row.get_meta("item_id")==id and row.get_node("ItemName").text==spec[1]+"石"),"Craft tab contains named stone "+id)
		check(page.summary.text.contains(spec[1]+"类宝石材料") and not page.hint.text.contains("已满"),"Stone has its own material description "+id)
	check((await Game.load_game()).ok,"Inventory survives saved-game reload")
	for spec in MEDICINES+STONES:check(ShopRules.quantity(ShopRules.local_state(Game.player),"original/ix%d"%spec[0])==(3 if spec in MEDICINES else 2),"Original quantity survives reload")
	var output:=OS.get_environment("SSJX_CONFIRMED_ITEMS_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		page._select_section("elixir");page.category="药品";page._filter();page.selected="original/ix18";page.refresh()
		for frame in 3:await get_tree().process_frame
		for row in page.rows:
			if row.get_meta("item_id")==page.selected:page.scroll.ensure_control_visible(row)
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Confirmed items render capture")
	page.queue_free();DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path
	print("CONFIRMED ITEMS: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
