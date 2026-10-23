extends Node
class RejectWrites extends "res://scripts/interface/adapters/native/native_storage.gd":
	func write(_path:String,_text:String)->PlatformStorageRequest:
		return PlatformStorageRequest.resolved(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"WRITE_FAILED","测试保存失败"))
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("GATHERING: "+text)
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var combat:Variant=Game.local_combat
	Game.save_path="user://gathering_%d.json"%Time.get_ticks_usec();Game.local_combat=null;Game.new_player("采集测试",0,3,0)
	check(GatheringRules.catalog.nodes.size()==418,"Bundled resource points match the seeded database catalog")
	for n in GatheringRules.catalog.nodes:
		var map:=SharedWorldMap.load_data(n.map_id)
		check(not map.blocked[int(n.cell[1])*32+int(n.cell[0])],"Resource remains on original walkable ground: "+n.id)
	var node:Dictionary=GatheringRules.nodes_for("qingyun_trail")[0];var cell:=Vector2i(node.cell[0],node.cell[1]);Game.player.cell=[cell.x,cell.y]
	check(Game.begin_gathering(node.id,cell,"qingyun_trail").is_empty(),"Local confirmation begins a nonpersistent collection timer")
	var early:=await Game.finish_gathering(cell,"qingyun_trail")
	check(not early.ok and early.code=="GATHER_NOT_READY" and not Game.player.has("gathering"),"Local collection cannot grant before duration")
	Game.local_gather.started=Time.get_ticks_msec()-int(node.duration_ms)-1
	var result:=await Game.finish_gathering(cell,"qingyun_trail")
	check(result.ok and int(Game.player.gathering.materials[node.material])>=1 and int(Game.player.gathering.materials[node.material])<=3,"Local completion saves a bounded material stack")
	check(Game.local_gather.is_empty() and Game.valid_save(Game.player),"Completed timer disappears and new optional save data validates")
	check(Game.begin_gathering(node.id,cell,"qingyun_trail")=="GATHER_COOLDOWN","Local cooldown survives reopening the resource panel")
	var saved:Dictionary=Game.player.gathering.duplicate(true);var loaded:=await Game.load_game()
	check(loaded.ok and int(Game.player.gathering.materials[node.material])==int(saved.materials[node.material]) and int(Game.player.gathering.respawns[node.id])==int(saved.respawns[node.id]),"Materials and refresh deadlines survive a real local save/load")
	var bad:=Game.player.duplicate(true);bad.gathering.materials[node.material]=1000
	check(not Game.valid_save(bad),"Corrupt out-of-range material stacks are rejected")
	var legacy:=Game.player.duplicate(true);legacy.erase("gathering")
	check(Game.valid_save(legacy),"Existing saves without gathering remain valid")
	await craft_checks()
	var bag:=GatheringMaterialBag.new();add_child(bag)
	check(bag.rows.text.contains(GatheringRules.MATERIALS[node.material]),"Local material bag shows persisted gathering materials")
	var scrap:=int(Game.player.loot_state.scrap)
	bag.batches.value=2;bag.craft.pressed.emit()
	check(int(Game.player.loot_state.scrap)==scrap+2 and bag.stock.text.contains("炼材"),"Material bag processes selected batches and refreshes real resource balances")
	var panel:=GatheringPanel.new();add_child(panel);panel.present(node);panel.hero_point=func()->Vector2:return Vector2(160,216)
	panel._process(0)
	check(panel.visible and panel.progress.size==Vector2(48,6) and panel.get_child_count()==1 and panel.position==Vector2(136,130),"Gathering uses only a compact overhead bar, without a frame, explanation or confirmation buttons")
	var output:=OS.get_environment("SSJX_GATHERING_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(output);await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output.path_join("materials-and-gathering.png"))==OK,"Actual material and collection UI render capture")
		panel.hide();await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output.path_join("materials-crafting.png"))==OK,"Actual recipe, quantities and resource balances render capture")
	panel.queue_free();bag.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path);Game.player=old;Game.save_path=path;Game.local_combat=combat;Game.local_gather={}
	print("GATHERING CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func craft_checks()->void:
	Game.player.gathering.materials={"iron":9,"copper":6,"gancao":6,"danggui":3}
	var original_scrap:=int(Game.player.loot_state.scrap);var potions:=int(Game.player.potions)
	check((await Game.craft_gathering("smelt_iron",2)).ok and int(Game.player.gathering.materials.iron)==3 and int(Game.player.loot_state.scrap)==original_scrap+2,"Iron processing credits existing upgrading materials at exact recipe cost")
	check((await Game.craft_gathering("smelt_copper",2)).ok and not Game.player.gathering.materials.has("copper") and int(Game.player.loot_state.scrap)==original_scrap+4,"Copper processing removes empty stacks")
	check((await Game.craft_gathering("brew_potion",3)).ok and int(Game.player.potions)==potions+3 and not Game.player.gathering.materials.has("gancao") and not Game.player.gathering.materials.has("danggui"),"Herbal recipe consumes both ingredients and grants usable potions")
	check((await Game.load_game()).ok and int(Game.player.loot_state.scrap)==original_scrap+4 and int(Game.player.potions)==potions+3,"Processing debits and both output resources survive a real save/load")
	Game.player.gathering.materials={"iron":30,"copper":30,"gancao":30}
	var before:=Game.player.duplicate(true)
	check((await Game.craft_gathering("brew_potion")).code=="MATERIALS_INSUFFICIENT" and Game.player==before,"Missing second herb cannot consume the first")
	for count in [-1,0,11,2147483647]:
		check((await Game.craft_gathering("smelt_iron",count)).code=="INVALID_GATHER_COMMAND" and Game.player==before,"Invalid batch size cannot consume or overflow: %d"%count)
	check((await Game.craft_gathering("unknown")).code=="INVALID_GATHER_COMMAND" and Game.player==before,"Unknown recipes cannot change balances")
	Game.player.gathering.materials.danggui=30;Game.player.potions=99;before=Game.player.duplicate(true)
	check((await Game.craft_gathering("brew_potion")).code=="BAG_FULL" and Game.player==before,"Full potion stack rejects before consuming herbs")
	Game.player.loot_state.scrap=1000000000;before=Game.player.duplicate(true)
	check((await Game.craft_gathering("smelt_iron")).code=="CRAFT_RESOURCE_FULL" and Game.player==before,"Full crafting resource balance never silently destroys ore")
	Game.player.potions=0;Game.player.loot_state.scrap=original_scrap
	var items:Array=Game.player.loot_state.items.duplicate(true)
	for i in 60:Game.player.loot_state.items.append(LootRules.roll("sword",1,"white",i))
	before=Game.player.duplicate(true)
	check((await Game.craft_gathering("brew_potion")).code=="BAG_FULL" and Game.player==before,"First potion needs an actual inventory slot including instance gear")
	Game.player.loot_state.items=items;Game.player.potions=potions
	await Game.save_game();before=Game.player.duplicate(true)
	var raw:=FileAccess.get_file_as_string(Game.save_path);var storage:=Platform.context.storage
	Platform.context._storage=RejectWrites.new()
	check(not (await Game.craft_gathering("smelt_iron",2)).ok and Game.player==before and FileAccess.get_file_as_string(Game.save_path)==raw,"Failed persistent write restores ore and scrap together")
	check(not (await Game.craft_gathering("brew_potion",2)).ok and Game.player==before and FileAccess.get_file_as_string(Game.save_path)==raw,"Failed persistent write restores both herbs and potions together")
	Platform.context._storage=storage
	Game.local_combat=weakref(self)
	check((await Game.craft_gathering("smelt_iron")).code=="BATTLE_ACTIVE" and Game.player==before,"Combat cannot process materials")
	Game.local_combat=null;Game.become_soul();var soul:=Game.player.duplicate(true)
	check((await Game.craft_gathering("smelt_iron")).code=="SOUL_STATE" and Game.player==soul,"Soul state cannot process materials")
	Game.player=before
