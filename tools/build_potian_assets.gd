extends SceneTree
## Pack the user-approved bitmap into the existing lishi weapon coordinates.
const SOURCE := "res://../analysis/ai-generated/equipment/legendary/potian-approved.png"
const OUTPUT := "res://assets/generated/equipment/legendary/"
const GRIP := Vector2(400,196)
const SHAFT_ANGLE := 34.47

func save_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t")+"\n")

func _init() -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	source.convert(Image.FORMAT_RGBA8)
	var opaque: Array[Vector2] = []
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x,y)
			# The supplied cutout has a soft removal matte around the edge.
			# Retain its solid pixel clusters, not nearly-transparent fringe noise.
			color.a = 1.0 if color.a>=250.0/255.0 else 0.0
			source.set_pixel(x,y,color if color.a else Color.TRANSPARENT)
			if color.a: opaque.append(Vector2(x,y)+Vector2(0.5,0.5)-GRIP)
	assert(not opaque.is_empty())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var atlas := Image.create(148,47,false,Image.FORMAT_RGBA8)
	var poses := [
		{"rect":[0,0,74,38],"grip":[13,18],"angle":0.0},
		{"rect":[74,0,74,47],"grip":[13,33],"angle":-27.0}
	]
	for pose in poses:
		var r: Array = pose.rect
		var anchor := Vector2(pose.grip[0],pose.grip[1])
		var angle := deg_to_rad(float(pose.angle)-SHAFT_ANGLE)
		var low := Vector2.INF
		var high := -Vector2.INF
		for pixel in opaque:
			var point := pixel.rotated(angle)
			low=low.min(point);high=high.max(point)
		var factor := 0.045
		if low.x<0: factor=minf(factor,(anchor.x-1)/-low.x)
		if low.y<0: factor=minf(factor,(anchor.y-1)/-low.y)
		if high.x>0: factor=minf(factor,(float(r[2])-1-anchor.x)/high.x)
		if high.y>0: factor=minf(factor,(float(r[3])-1-anchor.y)/high.y)
		pose.scale=factor
		# Inverse sample at native pixel centers: one uniform scale, no stretching.
		for y in int(r[3]):
			for x in int(r[2]):
				var point := ((Vector2(x,y)+Vector2(0.5,0.5)-anchor)/factor).rotated(-angle)+GRIP
				var at := Vector2i(floori(point.x),floori(point.y))
				if Rect2i(Vector2i.ZERO,source.get_size()).has_point(at):
					atlas.set_pixel(int(r[0])+x,int(r[1])+y,source.get_pixelv(at))
	assert(atlas.save_png(OUTPUT+"potian-axe.png")==OK)
	var icon := source.get_region(source.get_used_rect())
	var icon_factor := minf(28.0/icon.get_width(),28.0/icon.get_height())
	icon.resize(roundi(icon.get_width()*icon_factor),roundi(icon.get_height()*icon_factor),Image.INTERPOLATE_NEAREST)
	var icon_canvas := Image.create(32,32,false,Image.FORMAT_RGBA8)
	icon_canvas.blit_rect(icon,Rect2i(Vector2i.ZERO,icon.get_size()),(Vector2i(32,32)-icon.get_size())/2)
	assert(icon_canvas.save_png(OUTPUT+"potian-icon.png")==OK)
	save_json("res://../analysis/ai-generated/equipment/legendary/potian-import.json",{
		"source":SOURCE,"source_sha256":FileAccess.get_sha256(SOURCE),
		"source_grip":[GRIP.x,GRIP.y],"source_shaft_angle":SHAFT_ANGLE,"alpha_cutoff":250,"poses":poses,
		"outputs":[
			{"path":OUTPUT+"potian-axe.png","sha256":FileAccess.get_sha256(OUTPUT+"potian-axe.png")},
			{"path":OUTPUT+"potian-icon.png","sha256":FileAccess.get_sha256(OUTPUT+"potian-icon.png")}
		],
		"basis":"用户确认图片；仅透明阈值、等比最近邻采样和原版力士武器握持坐标适配，不重绘设计。"
	})
	print("POTIAN: imported approved axe into two native poses and a 32px inventory icon")
	quit()
