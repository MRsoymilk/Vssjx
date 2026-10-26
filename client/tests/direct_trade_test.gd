extends "res://tests/loot_instances_test.gd"
class QuietTrade extends OnlineEconomy:
	func tick()->void:pass
func _run()->void:
	await Game.when_ready()
	var path:=OS.get_environment("SSJX_DIRECT_TRADE_FIXTURES")
	check(not path.is_empty(),"Direct trade validation requires real committed server responses")
	if path.is_empty():get_tree().quit(1);return
	var old:=Game.player.duplicate(true);var pending:=OnlineAccount.pending_economy.duplicate(true)
	var shown:Dictionary={}
	for fixture in JSON.parse_string(FileAccess.get_file_as_string(path)):
		var pve:=OnlinePve.new();pve.character_id=fixture.character_id
		var model:=OnlineEconomy.new();model.pve=pve;model.character_id=fixture.character_id;model.request={"action":"snapshot" if fixture.operation_id==null else "trade_offer","operation_id":fixture.operation_id};model.inflight=true
		check(model.valid(fixture),"Production decoder accepts real invitation, escrow, confirmation, rollback, cancellation and expiry states")
		model._completed("economy",fixture)
		check(model.request.is_empty() and pve.ready,"Actual trade responses synchronize authority-owned inventory and wallet")
		var trade:Variant=fixture.market.trade
		if trade!=null and trade.status=="active" and trade.offers.all(func(offer:Dictionary)->bool:return offer.locked) and not trade.offers[0 if trade.sender==fixture.character_id else 1].confirmed:shown=fixture
	check(not shown.is_empty(),"Real exchange reached the locked second-confirmation stage")
	var pve:=OnlinePve.new();pve.character_id=shown.character_id;pve.receive({"type":"pve.state","state":shown.state})
	var model:=QuietTrade.new();model.pve=pve;model.character_id=shown.character_id;model.state=shown.market.duplicate(true)
	var panel:=EconomyPanel.new();panel.model=model;panel.online_model=pve;panel.section="direct";add_child(panel)
	await get_tree().process_frame;model.request={}
	var final:Button
	var lock_button:Button
	for child in panel.rows.get_children():
		if child is Button and child.text=="最终确认交换":final=child
		if child is Button and child.text=="锁定当前报价":lock_button=child
	check(final!=null and not final.disabled and lock_button.disabled,"Only both locked offers expose the final exchange confirmation")
	final.pressed.emit()
	check(panel.confirmation.visible and model.request.is_empty(),"Opening final confirmation cannot transfer anything")
	panel.confirmation.hide();check(model.request.is_empty(),"Cancelling the final dialog does not confirm or exchange")
	var reference:Dictionary={"target":shown.market.trade.id,"revision":int(shown.market.trade.revision)}
	check(model.submit("trade_confirm",reference) and model.request.target==reference.target and model.request.revision==reference.revision,"Exchange request contains the frozen trade revision, not client ownership or item stats")
	var request:=model.request.duplicate(true)
	check(not model.submit("trade_offer",{"items":[],"amount":0}) and model.request==request,"An unknown final confirmation cannot be replaced by another quote")
	model.request={}
	var malformed:=shown.duplicate(true);malformed.market.trade.offers[0].items[0].bound=true;model.request={"operation_id":shown.operation_id}
	check(not model.valid(malformed),"Bound equipment cannot be forged into an active trade offer")
	malformed=shown.duplicate(true);malformed.market.trade.recipient=LootRules.uuid();malformed.market.trade.sender=LootRules.uuid()
	check(not model.valid(malformed),"Unrelated participants cannot be substituted into a private trade")
	model.request={}
	var output:=OS.get_environment("SSJX_DIRECT_TRADE_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		await get_tree().process_frame;await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output+"-offer.png")==OK,"Capture real double-sided escrow and offer controls")
		for child in panel.rows.get_children():
			if child is Button and child.text=="最终确认交换":final=child
		final.pressed.emit();await get_tree().process_frame;await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output+"-confirm.png")==OK,"Capture second confirmation without executing a trade")
	panel.queue_free();await get_tree().process_frame
	check(Game.player==old,"Online direct trade never writes into the offline character")
	OnlineAccount.pending_economy=pending
	print("DIRECT TRADE CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
