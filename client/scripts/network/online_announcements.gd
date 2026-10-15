class_name OnlineAnnouncements
extends RefCounted
signal changed(notice: Dictionary)
var epoch := ""
var revision := -1

func clear() -> void:
	epoch = ""
	revision = -1
	changed.emit({})

func receive(packet: Dictionary) -> bool:
	if packet.get("type") != "announcement.state" or not OnlineWorldClient._uuid(packet.get("epoch")) or not OnlineWorldClient._decimal(packet.get("revision")): return false
	var notice: Variant = packet.get("notice")
	if not packet.has("notice"): return false
	if notice != null:
		if not notice is Dictionary or not OnlineWorldClient._uuid(notice.get("id")) or not notice.get("text") is String: return false
		if not OnlineWorldClient._integer(notice.get("remaining_ms"), 1, 86400000) or not OnlineWorldClient._decimal(notice.get("expires_at_ms")): return false
		var text: String = notice.text
		if text.strip_edges().is_empty() or text.length() > 240 or text.to_utf8_buffer().size() > 960: return false
		for index in text.length():
			var c := text.unicode_at(index)
			if c < 32 or (c >= 127 and c <= 159) or (c >= 0x200b and c <= 0x200f) or (c >= 0x202a and c <= 0x202e) or (c >= 0x2060 and c <= 0x206f) or c == 0xfeff: return false
	var next := int(packet.revision)
	if packet.epoch == epoch and next <= revision: return next == revision
	epoch = packet.epoch
	revision = next
	changed.emit({} if notice == null else notice.duplicate(true))
	return true
