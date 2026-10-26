extends "res://tests/loot_instances_test.gd"

func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://random_binding_%d.json"%Time.get_ticks_usec()
	var native:={};var ai:={};var foreign:=false
	for seed in 512:
		var reference:Dictionary={}
		for job in 3:
			for gender in 2:
				var p:Dictionary={"job":job,"gender":gender,"potions":0,"shop_owned":[],"weapon_owned":false,"loot_state":LootRules.empty()}
				p.loot_state.focus="weapon" if job==0 else "hat"
				ProgressionRules.reward(p,60,true,seed*7919)
				check(LootRules.valid(p.loot_state,job,gender),"Any class and gender may own the random loot")
				var comparable:=without_ids(p.loot_state);comparable.erase("focus")
				if reference.is_empty():reference=comparable
				else:check(same(reference,comparable),"Recipient class, gender and old focus cannot change seeded drops")
				for item in p.loot_state.items:
					check(not item.bound and LootRules.tradable(item),"All new drops start unbound and tradable")
					var definition:=ShopRules.item(item.template)
					if not LootRules.equip_error(item,job,gender).is_empty():foreign=true
					if item.template.begins_with("original/"):native[definition.slot]=true
					else:ai[definition.slot]=true
	check(foreign and native.size()==10 and ai.size()==10,"All ten slots from both art sources drop, including items the recipient cannot wear")
	Game.new_player("绑定验收",0,3,0);Game.player.level=60
	var item:=LootRules.roll("ai/eva01/wfs/weapon",30,"yellow",17);Game.player.loot_state.items.append(item)
	var before:=Game.player.duplicate(true)
	check(not (await Game.loot_command("gear_equip",item.id)).ok and Game.player==before,"Rejected cross-class equip neither binds nor changes inventory")
	Game.new_player("绑定验收",2,3,1);Game.player.level=60;Game.player.loot_state.items.append(item)
	check((await Game.loot_command("gear_equip",item.id)).ok and Game.player.loot_state.items.back().bound,"Successful persisted equip binds the exact UUID")
	check((await Game.loot_command("gear_unequip",item.id)).ok and Game.player.loot_state.items.back().bound,"Unequipping never removes binding")
	check((await Game.load_game()).ok and not LootRules.tradable(Game.player.loot_state.items.back()),"Binding survives reload")
	var legacy:=LootRules.roll("original/if2",30,"yellow",17);legacy.erase("bound");Game.player.loot_state.items.append(legacy);LootRules.sync_legacy(Game.player)
	check(Game.player.loot_state.items.back().bound,"Old equipment without binding history is conservatively bound")
	for job in 3:
		for gender in 2:
			Game.new_player("原生外观",job,3,gender);Game.player.level=60
			for slot in ["weapon","armor","hat"]:
				var definition:Dictionary=ShopRules.catalog.items.filter(func(d:Dictionary)->bool:return d.id.begins_with("original/") and d.slot==slot and ShopRules.equipment_error(d,job,gender).is_empty()).back()
				var original:=LootRules.roll(definition.id,60,"yellow",17);Game.player.loot_state.items.append(original)
				check((await Game.loot_command("gear_equip",original.id)).ok,"Original weapon, armor and hat can be worn by each actor")
			var key:=Game.appearance_key();var outfit:=HeroAppearance.outfit_for_key(key)
			check(outfit!=null and outfit.valid(),"Original art resolves an actual native-layer outfit")
			for equipment in [outfit.weapon,outfit.clothing,outfit.head]:
				for part in equipment.parts:check(not part.source_id.begins_with("ai/"),"Original outfits use recovered source parts")
			var sprite:=OriginalArt.actor(key);add_child(sprite)
			check(sprite.sprite_frames.get_frame_count("idle")>0 and sprite.sprite_frames.get_frame_texture("idle",0)!=null,"Original dropped looks compose real renderable animation frames")
			sprite.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path
	print("RANDOM BINDING: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func without_ids(state:Dictionary)->Dictionary:
	var copy:=state.duplicate(true)
	for item in copy.items+copy.pending:item.erase("id")
	copy.skins.sort();return copy
