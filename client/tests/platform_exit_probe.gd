extends Node
## Separate native process: verify real exit, not only a test backend's counter.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	if OS.get_cmdline_user_args().has("--window-close"):
		Game.new_player("退出验证", 1, 0)
		app._enter_world()
		Game.player.gold = 73
		app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		app._cover_exit()
		var confirmation := _confirm_button(app.modal)
		if confirmation == null:
			push_error("Native cover exit confirmation is missing")
			get_tree().quit(1)
			return
		confirmation.pressed.emit()
	print("PLATFORM EXIT: native request issued")

func _confirm_button(parent: Node) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == "确定": return child
		var nested := _confirm_button(child)
		if nested != null: return nested
	return null
