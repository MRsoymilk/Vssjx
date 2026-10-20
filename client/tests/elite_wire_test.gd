extends Node
func _ready()->void:
	var snapshot:Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SSJX_SOLO_STATE")))
	var validator:=OnlinePve.new()
	validator.character_id=snapshot.character.id
	if not validator.valid(snapshot):push_error("Real server formation rejected");get_tree().quit(1);return
	var adapter:=SoloEncounter.new();adapter.attach(validator)
	if not validator.receive({"type":"pve.state","state":snapshot}):get_tree().quit(1);return
	if adapter.battle().enemies.is_empty():get_tree().quit(1);return
	var invalid:Dictionary=snapshot.duplicate(true)
	invalid.battle.formation.enemies[0].elite.revives_left=3
	if validator.valid(invalid):push_error("Invalid extra lives accepted");get_tree().quit(1);return
	invalid=snapshot.duplicate(true);invalid.battle.formation.enemies[0].elite.party_size=2
	if validator.valid(invalid):push_error("Invalid elite party size accepted");get_tree().quit(1);return
	print("ELITE WIRE: PASS");get_tree().quit()
