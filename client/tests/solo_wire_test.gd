extends Node
func _ready()->void:
	var snapshot:Variant=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SSJX_SOLO_STATE")))
	var validator:=OnlinePve.new()
	validator.character_id=snapshot.character.id
	if not validator.valid(snapshot):push_error("Real server formation rejected");get_tree().quit(1);return
	var adapter:=SoloEncounter.new();adapter.attach(validator)
	if not validator.receive({"type":"pve.state","state":snapshot}):get_tree().quit(1);return
	if adapter.battle().enemies.size()<2:get_tree().quit(1);return
	print("SOLO WIRE: PASS");get_tree().quit()
