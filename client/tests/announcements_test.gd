extends "res://tests/shared_interface_test.gd"
var deliveries: Array = []

func notice_packet(revision: int, text: String = "维护通知：今晚22:00更新，请提前下线。") -> Dictionary:
	return {"type": "announcement.state", "epoch": EPOCH, "revision": str(revision), "notice": {"id": SELF, "text": text, "remaining_ms": 60000, "expires_at_ms": "1792080000000"}}

func _run() -> void:
	var channel := OnlineAnnouncements.new()
	channel.changed.connect(func(value: Dictionary) -> void: deliveries.append(value))
	check(channel.receive(notice_packet(1)), "First global notice is accepted")
	check(channel.receive(notice_packet(1)) and deliveries.size() == 1, "Duplicate publication never restarts the marquee")
	check(not channel.receive(notice_packet(0)) and deliveries.size() == 1, "Old notice cannot replace a newer revision")
	for text in ["", "字".repeat(241), "隐藏\u202e", "换\n行"]:
		check(not channel.receive(notice_packet(2, text)), "Invalid notice is rejected without partial installation")
	var bad := notice_packet(2)
	bad.notice.remaining_ms = 86400001
	check(not channel.receive(bad), "Notice lifetime is bounded")
	var cleared := {"type": "announcement.state", "epoch": EPOCH, "revision": "2", "notice": null}
	check(channel.receive(cleared) and deliveries[-1].is_empty(), "Operator cancellation clears the client state")
	channel.clear()
	check(channel.revision == -1 and channel.receive(notice_packet(1)), "A fresh connection accepts the current server notice")
	var before := Game.player.duplicate(true)
	var old_characters := OnlineAccount.characters.duplicate(true)
	OnlineAccount.characters = [{"id": SELF, "display_name": "昆仑客", "job": 1, "gender": 0, "school": 2, "level": 1, "hp": 95, "mp": 45, "gold": 30}]
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	check(not view.network._exchange_packet().has("announcement_version"), "Older ticket servers receive the original compatible handshake")
	view.network._announcement_version = 1
	check(view.network._exchange_packet().get("announcement_version") == 1, "Capable ticket servers receive the notice opt-in")
	view.network.world_ready = true
	view.network.stream = EPOCH
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10, 16])}
	view.network.changed.emit(view.network.entities)
	var packet := notice_packet(1, "全服通知：青云试炼即将开启，欢迎诸位道友参加！")
	view.network._receive(packet, JSON.stringify(packet).to_utf8_buffer())
	var banner: AnnouncementBanner = app.announcement_banner
	check(banner.visible and banner.message.text == packet.notice.text, "Real network dispatch presents the global tscn overlay")
	check(banner.get_parent() is CanvasLayer and banner.mouse_filter == Control.MOUSE_FILTER_IGNORE and banner.clip.clip_contents, "Banner renders above menus without intercepting game input")
	banner.set_process(false)
	var start := banner.message.position.x
	banner._process(1.0)
	check(is_equal_approx(banner.message.position.x, start - AnnouncementBanner.SPEED), "Marquee scrolls left at a steady speed")
	var second := OnlineAnnouncements.new()
	var peer_banner: AnnouncementBanner = load("res://scenes/ui/announcement_banner.tscn").instantiate()
	add_child(peer_banner)
	peer_banner.hide()
	second.changed.connect(peer_banner.present)
	check(second.receive(packet) and peer_banner.message.text == banner.message.text, "Independent second client receives the same global notification")
	peer_banner.hide()
	view.menu.open()
	banner._process(1.0)
	check(banner.visible and banner.message.position.x < start - AnnouncementBanner.SPEED, "Opening the game menu does not pause the notification")
	view.menu.dismiss()
	banner.message.position.x = -banner.message.size.x - 1
	banner._process(0.01)
	check(banner.message.position.x == banner.clip.size.x, "Text wraps back after the entire message leaves the clipped area")
	banner.message.position.x = 8
	output = OS.get_environment("SSJX_ANNOUNCEMENT_CAPTURE_PATH")
	await capture("announcement_game")
	view.network._receive(cleared, JSON.stringify(cleared).to_utf8_buffer())
	check(not banner.visible, "Server removal hides the overlay immediately")
	view.network._receive(notice_packet(3), PackedByteArray())
	banner._expires_at = Time.get_ticks_msec() - 1
	banner._process(0.01)
	check(not banner.visible, "Notice stops locally when its lifetime elapses")
	view.network._receive(notice_packet(4), PackedByteArray())
	view.network._failed("NETWORK_ERROR", true)
	check(not banner.visible, "Connection loss clears the previous server announcement")
	var wire_path := OS.get_environment("SSJX_ANNOUNCEMENT_PACKET_PATH")
	if not wire_path.is_empty():
		var wire: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(wire_path))
		view.network.stream = EPOCH
		view.network.world_ready = true
		view.network.changed.emit(view.network.entities)
		view.network._receive(wire, JSON.stringify(wire).to_utf8_buffer())
		check(banner.visible and banner.message.text == wire.notice.text, "Exact packet published by the Rust operator API reaches the game overlay")
		check(second.receive(wire) and peer_banner.message.text == wire.notice.text, "Second independent channel accepts the exact Rust publication")
		peer_banner.hide()
		banner.message.position.x = 8
		await capture("announcement_game")
	check(Game.player == before, "Global announcements never alter player saves")
	OnlineAccount.characters = old_characters
	peer_banner.queue_free()
	app.queue_free()
	await get_tree().process_frame
	print("GLOBAL ANNOUNCEMENTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
