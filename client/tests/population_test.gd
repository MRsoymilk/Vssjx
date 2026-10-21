extends "res://tests/shared_interface_test.gd"

func residents_packet(revision: int = 1) -> Dictionary:
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/population_fixture.json"))
	for entry in definitions:
		entry.next_cell = null
		entry.segment_progress = 0
		entry.world_epoch = "1"
		entry.entity_revision = "0"
	return {"type": "population.state", "epoch": EPOCH, "revision": str(revision), "entities": definitions}

func _run() -> void:
	var old := Game.player.duplicate(true)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.stream = EPOCH
	view.network.world_ready = true
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10,16])}
	view.network.changed.emit(view.network.entities)
	var packet := residents_packet()
	view.network._receive(packet, JSON.stringify(packet).to_utf8_buffer())
	check(view.residents.size() == 5 and view.actors.size() == 1 and view.count_label.text == "同图1人", "Five server residents appear without changing online player counts")
	for resident in view.residents.values():
		check(resident.scene_file_path == "res://scenes/actors/online_resident.tscn" and resident.sprite is AnimatedSprite2D and resident.sprite.is_playing(), "Resident scene uses animated original art and static name label")
		var tag: Label=resident.get_node("Name")
		if resident.data.kind!="npc":
			check(tag.text=="%d级 %s" % [int(resident.data.level),String(resident.data.name)],"Online monster name shows its authoritative level")
			check(tag.get_theme_color("font_color")==Color("ff3030"),"Online monsters have red names")
		else:
			check(tag.text==resident.data.name and tag.get_theme_color("font_color")==Color("ffe095"),"NPC name and color remain unchanged")
	check(view.screen.hud.get_node("Minimap").shared_population.size() == 5, "NPC and monster markers reach the minimap")
	var invalid := residents_packet(2)
	invalid.entities[1].art = "res://scripts/main.gd"
	check(not view.network.population.receive(invalid) and view.residents.size() == 5, "Untrusted resource paths cannot replace the current population")
	packet = residents_packet(2)
	packet.entities[1].next_cell = [19,10]
	packet.entities[1].segment_progress = 175
	check(view.network.population.receive(packet), "Server wolf motion accepted")
	var wolf: OnlineResident = view.residents.wolf_a
	var before := wolf.position
	view._process(0.1)
	check(wolf.position.x > before.x and wolf.position.distance_to(before) <= 2.81 and wolf.sprite.animation == "walk", "Wolf follows the authoritative patrol at 28 pixels per second")
	check(view.residents.qingwei.position == Vector2(168,216), "Quest NPC remains at the bridge")
	output = OS.get_environment("SSJX_POPULATION_CAPTURE_PATH")
	await capture("online_population")
	await get_tree().process_frame
	var names: Control=view.image.get_node("WorldNameplates")
	names._process(0.0)
	var source: Label=wolf.get_node("Name")
	var proxy: Label=names.entries[source.get_instance_id()].proxy
	check(proxy.get_viewport()!=source.get_viewport() and proxy.text==source.text and source.self_modulate.a==0,"Names render once at UI resolution outside the low-resolution world texture")
	check(proxy.get_theme_color("font_color")==Color("ff3030"),"UI-resolution nameplate preserves the monster's red name and level")
	var name_before:=proxy.position
	wolf.position+=Vector2(5,3);names._process(0.0)
	check(proxy.position.is_equal_approx(name_before+Vector2(5,3)),"Readable text continues following the moving monster")
	source.hide();names._process(0.0)
	check(not proxy.visible,"Name overlay follows actor-label visibility")
	source.show()
	view.network.population.clear()
	await get_tree().process_frame
	names._process(0.0)
	check(not names.entries.has(source.get_instance_id()) if is_instance_valid(source) else not is_instance_valid(proxy) or proxy.is_queued_for_deletion(),"Removed residents leave no floating names")
	check(view.residents.is_empty(), "Disconnect clears resident nodes")
	check(Game.player == old, "Shared residents never modify local progress")
	app.queue_free()
	await get_tree().process_frame
	print("ONLINE POPULATION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
