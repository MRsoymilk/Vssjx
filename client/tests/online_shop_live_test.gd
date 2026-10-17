extends Node
var checks := 0
var failures := 0
var view: OnlineWorldView
func _ready() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error("ONLINE SHOP UI: "+text)
func wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+20000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	return predicate.call()
func _run() -> void:
	var local := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_SHOP_TEST_BASE"),"shop_first","shop-test-password")
	await OnlineAccount.completed
	OnlineAccount.list_characters();await OnlineAccount.completed
	check(not OnlineAccount.characters.is_empty(),"Fixture account has character")
	if OnlineAccount.characters.is_empty(): get_tree().quit(1);return
	view=load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=OnlineAccount.characters[0].id
	add_child(view)
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready),"Real client accepts shop state")
	check(await wait_until(func() -> bool: return view.network.appearances.has(view.character_id)),"Opt-in appearance stream synchronizes")
	check(view.actors[view.character_id].sprite.get_meta("art_key")=="hero/mck_w2_c1","World renders equipped appearance")
	view._scene_action("shop")
	check(view.shop != null and not view.shop.equip_button.disabled,"Original menu opens online shop")
	view.shop.selected="weapon_3";view.shop.refresh();view.shop.buy_button.pressed.emit()
	check(view.network.pve.pending() and not view.network.pve.state.shop.owned.has("weapon_3"),"Purchase waits for server confirmation")
	check(await wait_until(func() -> bool: return not view.network.pve.pending() and view.network.pve.state.shop.owned.has("weapon_3")),"Confirmed purchase updates ownership")
	view.shop.equip_button.pressed.emit()
	check(await wait_until(func() -> bool: return not view.network.pve.pending() and view.network.pve.state.shop.weapon=="weapon_3"),"Equip confirmed by server")
	check(await wait_until(func() -> bool: return view.actors[view.character_id].sprite.get_meta("art_key")=="hero/mck_w3_c1"),"World swaps weapon immediately")
	view._scene_action("bag")
	check(view.backpack.preview.get_meta("art_key")=="hero/mck_w3_c1" and view.backpack.armor_icon.visible,"Online bag renders actual loadout")
	view.backpack._select_equipment(2);view.backpack.equip_item()
	check(await wait_until(func() -> bool: return not view.network.pve.pending() and view.network.pve.state.shop.armor==null),"Online bag unequips armor")
	check(view.backpack.items.any(func(i: Dictionary) -> bool: return i.id=="armor_2"),"Unequipped armor returns to bag")
	view._scene_action("shop")
	view.shop.selected="original/if1";view.shop.refresh();view.shop.buy_button.pressed.emit()
	check(await wait_until(func()->bool:return not view.network.pve.pending() and view.network.pve.state.shop.owned.has("original/if1")),"Original hat purchase confirmed")
	view.shop.equip_button.pressed.emit()
	check(await wait_until(func()->bool:return not view.network.pve.pending() and view.network.pve.state.shop.slots.hat=="original/if1"),"Hat occupies its authoritative slot")
	check(await wait_until(func()->bool:return view.actors[view.character_id].sprite.get_meta("art_key")=="hero/mck_w3_c0_h1"),"Three-component appearance stream renders head gear")
	view._scene_action("bag")
	check(view.backpack.slot_icons.hat.visible and view.backpack.preview.get_meta("art_key")=="hero/mck_w3_c0_h1","Online backpack renders head slot and dynamic portrait")
	check(Game.player==local,"Online purchases and equipment never change local save")
	view._close_inventory();view.network.leave();view.queue_free()
	await get_tree().process_frame
	print("ONLINE SHOP UI: %d checks, %d failures" % [checks,failures])
	get_tree().quit(1 if failures else 0)
