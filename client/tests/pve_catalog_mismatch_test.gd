extends "res://tests/online_pve_test.gd"
func _run()->void:
	await Platform.when_ready()
	AIWorld.prepare()
	var saved:=OnlineAccount.pending_pve.duplicate(true);OnlineAccount.pending_pve={}
	var good:=pve_state()
	good.ai_world={"version":"ai-world-v1","catalog_sha256":AIWorld.catalog_hash,"completed":[],"active":{},"respawns":{},"completed_count":0}
	var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:8080")
	check(model.receive({"type":"pve.state","state":good}),"Matching catalogs can install a valid initial PVE state")
	var original:=model.state.duplicate(true)
	var stale:=good.duplicate(true);stale.ai_world.catalog_sha256="0".repeat(64)
	check(not model.receive({"type":"pve.state","state":stale}) and model.validation_error=="PVE_CATALOG_MISMATCH","Stale server catalog is rejected with an explicit diagnostic")
	check(model.state==original,"Rejected state cannot overwrite confirmed character data")
	check(model.valid(good) and model.validation_error.is_empty(),"A subsequent matching snapshot clears the stale diagnostic")
	var malformed:=good.duplicate(true);malformed.ai_world.active={"not_a_quest":[1]}
	check(not model.valid(malformed) and model.validation_error.is_empty(),"Malformed progress is still rejected without being labelled a catalog mismatch")
	var wire:=OnlineWorldClient.new();wire.character_id=SELF;wire.pve.bind_character(SELF,"http://127.0.0.1:8080");wire.world_ready=true;wire._pve_version=1
	var notices:Array=[];wire.status_changed.connect(func(text:String)->void:notices.append(text))
	wire._receive({"type":"pve.state","state":stale},PackedByteArray())
	check(wire._state=="failed" and notices[-1].contains("地图数据版本不一致"),"World connection displays a useful content-version error")
	wire.world_ready=true;wire._receive({"type":"pve.state","state":malformed},PackedByteArray())
	check(notices[-1]=="连接中断：INVALID_PVE","Other malformed PVE packets retain strict generic rejection")
	wire.world_ready=false;wire._receive({"type":"pve.state","state":stale},PackedByteArray())
	check(notices[-1]=="连接中断：INVALID_PVE","PVE received before world readiness cannot reuse a previous mismatch code")
	wire.free();OnlineAccount.pending_pve=saved
	print("PVE CATALOG MISMATCH: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
