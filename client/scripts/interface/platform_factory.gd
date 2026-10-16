extends RefCounted
## Do not let Web silently inherit native storage durability or OS config.

static func create(target: String = "") -> PlatformContext:
	var selected := target if not target.is_empty() else ("web" if OS.has_feature("web") else "native")
	if OS.has_feature("web"):
		if selected != "web": return null
		return PlatformContext.new("web",
			load("res://scripts/interface/adapters/web/web_storage.gd").new(),
			load("res://scripts/interface/adapters/web/web_runtime_config.gd").new(),
			load("res://scripts/interface/adapters/web/web_display.gd").new(),
			load("res://scripts/interface/adapters/web/web_lifecycle.gd").new(),
			load("res://scripts/interface/adapters/web/web_resource_loader.gd").new(),
			load("res://scripts/interface/adapters/web/web_text_input.gd").new(),
			load("res://scripts/interface/adapters/web/web_system_actions.gd").new())
	if selected != "native": return null
	return PlatformContext.new("native",
		preload("res://scripts/interface/adapters/native/native_storage.gd").new(),
		preload("res://scripts/interface/adapters/native/native_runtime_config.gd").new(),
		preload("res://scripts/interface/adapters/native/native_display.gd").new(),
		preload("res://scripts/interface/adapters/native/native_lifecycle.gd").new(),
		preload("res://scripts/interface/adapters/native/native_resource_loader.gd").new(),
		preload("res://scripts/interface/adapters/common/godot_text_input.gd").new(),
		preload("res://scripts/interface/adapters/native/native_system_actions.gd").new())
