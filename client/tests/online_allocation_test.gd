extends "res://tests/online_pve_test.gd"

func attribute_state(revision: int = 1, allocated: Array = [0,0,0,0,0]) -> Dictionary:
	var value := pve_state(revision)
	var a := allocated
	value.stats = CharacterAttributeRules.stats(1,1,true,a)
	var combat:Dictionary = CharacterAttributeRules.profile(1,1,true,a).combat
	value.attributes = {"version":"attributes-v1","allocated":a.duplicate(),"available":5-int(a.reduce(func(total: int, n: Variant) -> int: return total+int(n),0)),"recommended":[1,0,3,1,0] if a == [0,0,0,0,0] else a.duplicate(),"combat":combat}
	return value

func _run() -> void:
	var old := Game.player.duplicate(true)
	OnlineAccount.pending_pve = {}
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.pve.bind_character(SELF,"http://127.0.0.1:9999")
	view.network.entities = {SELF:entity(SELF,1,"昆仑客",1,0,[10,16])}
	view.network.changed.emit(view.network.entities)
	var model := view.network.pve
	model.send_requested.connect(func(packet: Dictionary) -> void: sent.append(packet))
	var state: Dictionary = JSON.parse_string(JSON.stringify(attribute_state()))
	check(model.receive({"type":"pve.state","state":state}), "Versioned attribute profile validates")
	view._scene_action("properties")
	var page := view.attributes
	view.network._pending_motion = {}
	view.network.entities[SELF].last_input_seq = view.network._input_seq
	view._update_allocation_controls()
	page.select_tab(1)
	check(page.content.scene_file_path.ends_with("attributes_online_extended.tscn") and page.content.get_node("Value_physical_hit").value == "100", "Reference extension is an authored scene using server combat numbers")
	check(page.content.get_node("Remaining").text == "5" and page.content.get_node("Minus0").disabled and page.content.get_node("Confirm").disabled, "Initial point budget and committed lower bound displayed")
	page.content.get_node("Plus2").pressed.emit()
	check(page.allocation_draft == [0,0,1,0,0] and page.content.get_node("Remaining").text == "4" and sent.is_empty(), "Plus edits draft without sending or spending server points")
	page.content.get_node("Minus2").pressed.emit()
	page._adjust_allocation(2,-1)
	check(page.allocation_draft == [0,0,0,0,0], "Draft cannot go below committed allocation")
	page.content.get_node("Recommend").pressed.emit()
	check(page.allocation_draft == [1,0,3,1,0] and page.content.get_node("Remaining").text == "0" and sent.is_empty(), "Recommend stages server plan without saving")
	page._adjust_allocation(0,1)
	check(page.allocation_draft == [1,0,3,1,0] and page.content.get_node("Plus0").disabled, "Exhausted draft cannot exceed budget")
	page.select_tab(0); page.select_tab(1)
	check(page.allocation_draft == [1,0,3,1,0], "Tab navigation retains unconfirmed draft")
	output = OS.get_environment("SSJX_ATTRIBUTES_CAPTURE_PATH")
	await capture("online_attributes_extended_draft")
	view.network.entities[SELF].next_cell = [11,16]
	view._update_allocation_controls()
	page._confirm_allocation()
	check(page.content.get_node("Confirm").disabled and sent.is_empty(), "Moving character cannot submit allocation")
	view.network.entities[SELF].next_cell = null
	view.network._pending_motion = {"test":true}
	view._update_allocation_controls()
	check(not page.allocation_enabled, "Unacknowledged movement blocks allocation")
	view.network._pending_motion = {}
	view._update_allocation_controls()
	page.content.get_node("Confirm").pressed.emit()
	check(model.pending() and sent.size() == 1 and sent[0].command.action == "allocate" and sent[0].command.attributes == [1,0,3,1,0] and sent[0].command.attributes[0] is int and sent[0].command.expected_revision == "1" and not sent[0].command.has("battle_id"), "Confirm submits final allocation fenced by character revision")
	page._confirm_allocation()
	check(sent.size() == 1 and page.content.get_node("Confirm").disabled, "Pending save disables double submission")
	var command: Dictionary = sent[0].command.duplicate(true)
	model.disconnect_channel()
	view._update_allocation_controls()
	check(page.allocation_draft == [1,0,3,1,0] and not page.allocation_enabled, "Lost response preserves draft and pending operation")
	check(model.receive({"type":"pve.state","state":state}) and sent.size() == 2 and sent[1].command == command, "Reconnect reuses original allocation UUID and payload")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(attribute_state(2,[1,0,3,1,0])))
	check(model.receive({"type":"pve.result","operation_id":command.operation_id,"ok":true,"replayed":true,"lines":["属性已保存"],"state":saved}), "Allocation receipt clears retry outbox")
	view._update_allocation_controls()
	check(not model.pending() and page.content.get_node("Remaining").text == "0" and page.content.get_node("Minus2").disabled and page.content.get_node("Value_physical_attack").value == "34", "Authoritative saved totals and actual combat stats refresh")
	check(page.content.get_node("Value_physical_crit").value == "1" and page.content.get_node("Value_magic_crit").value == "0", "Server agility refreshes physical ratings independently of magic")
	check(not model.submit("allocate","",[0,0,3,1,0]) and not model.submit("allocate","",[2,0,3,1,0]), "Model rejects respec and budget overflow")
	for key in ["version","allocated","available","recommended","combat"]:
		var invalid := saved.duplicate(true)
		invalid.attributes.erase(key)
		check(not model.receive({"type":"pve.state","state":invalid}) and model.state.character.state_revision == saved.character.state_revision, "Malformed attribute field rejected: " + key)
	var invalid := saved.duplicate(true)
	invalid.attributes.combat.hp += 1
	check(not model.valid(invalid), "Combat profile cannot contradict health maximum")
	invalid = saved.duplicate(true); invalid.attributes.allocated[0] = 0.5
	check(not model.valid(invalid), "Fractional allocation rejected")
	output = OS.get_environment("SSJX_ATTRIBUTES_CAPTURE_PATH")
	await capture("online_attributes_extended_saved")
	check(Game.player == old, "Online allocation leaves local character untouched")
	OnlineAccount.pending_pve = {}
	app.queue_free()
	await get_tree().process_frame
	print("ONLINE ALLOCATION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
