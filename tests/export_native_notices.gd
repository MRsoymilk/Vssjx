extends SceneTree
## Build-time only, run in a blank isolated project; never ships as a game script.
func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected one owned notices output path")
		quit(1)
		return
	var file := FileAccess.open(arguments[0], FileAccess.WRITE)
	if file == null:
		push_error("Unable to write build notices")
		quit(1)
		return
	file.store_string(Engine.get_license_text() + "\n\nGodot engine component notices (build editor):\n")
	file.store_string(JSON.stringify(Engine.get_copyright_info(), "  ") + "\n")
	file.store_string(JSON.stringify(Engine.get_license_info(), "  ") + "\n")
	file.close()
	print("NATIVE NOTICES: written")
	quit()
