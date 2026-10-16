extends "res://scripts/interface/adapters/common/godot_text_input.gd"
## Browser-native fields for touch keyboards, password entry and Chinese composition.
var _host: Node

func attach(owner: Node) -> void:
	if not OS.has_feature("web") or is_instance_valid(_host): return
	_host = load("res://scripts/interface/adapters/web/web_text_input_host.gd").new()
	owner.add_child(_host)

func request_focus(field: LineEdit, select_all: bool = false) -> PlatformResult:
	var result := super.request_focus(field, select_all)
	if result.ok and is_instance_valid(_host): _host.focus_field(field, select_all)
	return result

func release_focus(field: LineEdit) -> PlatformResult:
	var result := super.release_focus(field)
	if result.ok and is_instance_valid(_host): _host.blur_field(field)
	return result

func _is_composing(field: LineEdit) -> bool:
	return super._is_composing(field) or (is_instance_valid(_host) and _host.is_composing(field))
