class_name AnnouncementBanner
extends Control
const SPEED := 36.0
@onready var clip: Control = $Panel/Clip
@onready var message: Label = $Panel/Clip/Message
var notice_id := ""
var _expires_at := 0

func present(notice: Dictionary) -> void:
	if notice.is_empty():
		notice_id = ""
		hide()
		return
	_expires_at = Time.get_ticks_msec() + int(notice.remaining_ms)
	if notice_id != notice.id or message.text != notice.text:
		notice_id = notice.id
		message.text = notice.text
		message.size.x = message.get_minimum_size().x
		message.position.x = clip.size.x
	show()

func _process(delta: float) -> void:
	if not visible: return
	if Time.get_ticks_msec() >= _expires_at:
		present({})
		return
	message.position.x -= SPEED * delta
	if message.position.x + message.size.x < 0: message.position.x = clip.size.x
