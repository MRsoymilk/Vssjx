extends RefCounted
## Per-window desktop layout; never change the game's project viewport settings.

const RESIZE_CALLBACK := &"admin_layout_resize_callback"
const DESKTOP_SIZE := Vector2i(960, 540)

static func configure_scene(scene: Control, title: String, desktop_size: Vector2i = DESKTOP_SIZE) -> void:
	var window := scene.get_window()
	if window == scene.get_tree().root and DisplayServer.get_name() != "headless" and Engine.is_embedded_in_editor():
		# F6's Game view owns --wid and keeps enforcing its portrait resolution.
		# Keep the same debug process, but put the tool in a real desktop window.
		_open_desktop_window.call_deferred(scene, title, desktop_size)
	else:
		configure(window, title, desktop_size, desktop_size)

static func _open_desktop_window(scene: Control, title: String, desktop_size: Vector2i) -> void:
	if not is_instance_valid(scene) or not scene.is_inside_tree(): return
	var tree := scene.get_tree()
	var was_current_scene := tree.current_scene == scene
	var window := Window.new()
	window.name = "AdminDesktopWindow"
	window.title = title
	window.size = desktop_size
	window.visible = false
	window.gui_embed_subwindows = false
	tree.root.gui_embed_subwindows = false
	tree.root.add_child(window)
	scene.reparent(window)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if was_current_scene: tree.current_scene = window
	window.close_requested.connect(tree.quit)
	window.show()
	configure(window, title, desktop_size, desktop_size)

static func configure(window: Window, title: String, minimum_canvas: Vector2i, preferred_size: Vector2i) -> void:
	window.title = title
	window.min_size = Vector2i(320, 240)
	var target := preferred_size
	if DisplayServer.get_name() != "headless":
		# These are separate desktop tools, including their overview popup.
		window.gui_embed_subwindows = false
		var available := DisplayServer.screen_get_usable_rect(window.current_screen).size - Vector2i(48, 96)
		target = target.min(available.max(Vector2i(320, 240)))
	window.size = target
	window.min_size = minimum_canvas.min(target)
	window.move_to_center()
	adapt(window, minimum_canvas)

static func adapt(window: Window, minimum_canvas: Vector2i) -> void:
	var previous: Variant = window.get_meta(RESIZE_CALLBACK) if window.has_meta(RESIZE_CALLBACK) else null
	if previous is Callable and window.size_changed.is_connected(previous):
		window.size_changed.disconnect(previous)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_factor = 1.0
	var callback := _resize.bind(window, minimum_canvas)
	window.set_meta(RESIZE_CALLBACK, callback)
	window.size_changed.connect(callback)
	_resize(window, minimum_canvas)

static func _resize(window: Window, minimum_canvas: Vector2i) -> void:
	# Native pixels at desktop sizes; scale the full desktop down only when its
	# physical window is smaller than the desktop layout.
	var canvas := window.size.max(minimum_canvas)
	if window.content_scale_size != canvas:
		window.content_scale_size = canvas
