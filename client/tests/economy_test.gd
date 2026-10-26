extends "res://tests/loot_instances_test.gd"
class QuietMarket extends OnlineEconomy:
	func tick()->void:pass
func _run()->void:
	await Game.when_ready()
	var path:=OS.get_environment("SSJX_ECONOMY_FIXTURES")
	check(not path.is_empty(),"Market validation requires real committed server responses")
	if path.is_empty():get_tree().quit(1);return
	var old:=Game.player.duplicate(true);var pending:=OnlineAccount.pending_economy.duplicate(true)
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string(path));var shown:Dictionary={}
	for fixture in fixtures:
		var pve:=OnlinePve.new();pve.character_id=fixture.character_id
		var model:=OnlineEconomy.new();model.pve=pve;model.character_id=fixture.character_id;model.request={"action":"snapshot" if fixture.operation_id==null else "list","operation_id":fixture.operation_id};model.inflight=true
		check(model.valid(fixture),"Production escrow decoder accepts a real server snapshot")
		model._completed("economy",fixture)
		check(model.request.is_empty() and pve.ready and not model.state.is_empty(),"Response confirms the exact operation and synchronizes authoritative equipment and currency")
		if not fixture.market.listings.is_empty() and fixture.market.listings[0].status=="open" and fixture.market.listings[0].seller!=fixture.character_id:shown=fixture
	check(not shown.is_empty(),"Actual browse response includes another seller's tradable equipment")
	var pve:=OnlinePve.new();pve.character_id=shown.character_id;check(pve.receive({"type":"pve.state","state":shown.state}),"Production player state accepts cross-class unbound inventory")
	var model:=QuietMarket.new();model.pve=pve;model.character_id=pve.character_id;model.state=shown.market.duplicate(true)
	var panel:=EconomyPanel.new();panel.model=model;panel.online_model=pve;add_child(panel);await get_tree().process_frame
	model.request={}
	check(panel.scroll.get_v_scroll_bar().custom_minimum_size.x>=24,"Market list reserves a phone-sized drag target")
	check(panel.scroll.size.x<=284 and panel.rows.size.x<=260,"Market filters and rows leave real space for the widened scrollbar")
	var listing:Dictionary=shown.market.listings[0]
	panel.confirm("buy",{"target":listing.id,"revision":int(listing.revision)},"确认以%d铜购买？"%int(listing.buyout))
	check(panel.confirmation.visible and model.request.is_empty(),"Purchase confirmation cannot charge before a second explicit action")
	panel.confirmation.hide();check(model.request.is_empty(),"Cancel leaves item ownership and wallet unchanged")
	check(model.submit("buy",{"target":listing.id,"revision":int(listing.revision)}),"Confirmed purchase queues an authoritative listing identifier and revision")
	var queued:=model.request.duplicate(true)
	check(not model.submit("buy",{"target":listing.id}) and model.request==queued and not model.request.has("item") and not model.request.has("seed"),"Rapid duplicate taps cannot submit client rolled stats or a second operation")
	var saved_request:=OnlineAccount.pending_economy.duplicate(true)
	var retry:=OnlineEconomy.new();retry.bind_model(pve)
	check(retry.request==queued,"Reopening the market retains an unknown write's original operation UUID")
	retry.detach();OnlineAccount.pending_economy=saved_request;model.request={}
	var malformed:=shown.duplicate(true);malformed.market.listings[0].item.bound=true;model.request={"operation_id":shown.operation_id}
	check(not model.valid(malformed),"Bound items cannot enter decoded tradable escrow")
	malformed=shown.duplicate(true);malformed.character_id=LootRules.uuid();check(not model.valid(malformed),"A market response for a different character is rejected")
	model.request={};panel._tab("deliveries");check(panel.section=="deliveries","Delivery page is reachable without modifying offline saves")
	panel._tab("sell");check(is_instance_valid(panel.sell_item),"Native market includes the unbound inventory listing form")
	var output:=OS.get_environment("SSJX_ECONOMY_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		panel._tab("browse");await get_tree().process_frame;await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output)==OK,"Capture the real phone-size auction interface")
	panel.queue_free();await get_tree().process_frame
	check(Game.player==old,"Online trading never alters the offline character")
	OnlineAccount.pending_economy=pending
	print("ECONOMY CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
