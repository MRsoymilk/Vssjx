extends Control
## Render names outside the 320px world texture so Chinese glyphs are rasterized
## at the actual UI resolution while sprite/terrain pixels stay nearest-filtered.
const STYLE := preload("res://scripts/world_nameplate.gd")
var source_viewport: SubViewport
var entries: Dictionary = {}

static func attach(image: TextureRect, viewport: SubViewport) -> void:
	var layer := preload("res://scripts/world_nameplate_layer.gd").new()
	layer.name="WorldNameplates"
	layer.source_viewport=viewport
	image.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	process_priority=10 # Sample actor movement and camera transforms after the world.

func _process(_delta: float) -> void:
	if not is_instance_valid(source_viewport):return
	var ratio:=size/Vector2(source_viewport.size)
	var seen := {}
	var raised: Array[Label] = []
	for source in get_tree().get_nodes_in_group(STYLE.GROUP):
		if not source is Label or source.is_queued_for_deletion() or source.get_viewport()!=source_viewport:continue
		var id: int=source.get_instance_id()
		seen[id]=true
		if not entries.has(id):
			var proxy:=Label.new()
			proxy.text=source.text
			STYLE.apply(proxy,source.get_theme_color("font_color"),false)
			add_child(proxy)
			entries[id]={"source":source,"proxy":proxy,"modulate":source.self_modulate}
			# Keep source layout/visibility for the actor's existing facing logic.
			source.self_modulate=Color(1,1,1,0)
		var proxy: Label=entries[id].proxy
		var actor := source.get_parent() as CanvasItem
		if actor!=null and actor.z_index>0:raised.append(proxy)
		proxy.text=source.text
		proxy.size=source.size
		proxy.position=source.get_global_transform_with_canvas().origin*ratio
		proxy.scale=ratio
		proxy.visible=source.is_visible_in_tree()
		var color: Color=source.get_theme_color("font_color")
		if proxy.get_theme_color("font_color")!=color:proxy.add_theme_color_override("font_color",color)
	for id in entries.keys():
		if not seen.has(id):
			var entry: Dictionary=entries[id]
			if is_instance_valid(entry.source):entry.source.self_modulate=entry.modulate
			entry.proxy.queue_free();entries.erase(id)
	# Raise NPC names within this overlay, without raising them above the HUD.
	for i in range(raised.size()-1,-1,-1):
		var index:=get_child_count()-raised.size()+i
		if raised[i].get_index()!=index:move_child(raised[i],index)

func _exit_tree() -> void:
	for entry in entries.values():
		if is_instance_valid(entry.source):entry.source.self_modulate=entry.modulate
