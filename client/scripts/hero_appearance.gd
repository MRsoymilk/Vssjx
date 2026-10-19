class_name HeroAppearance
extends RefCounted
## Compose original layers on demand, rather than shipping thousands of combinations.
static var _data: Dictionary = {}
static var _images: Dictionary = {}
static var _parts: Dictionary = {}
static var _prepared: Dictionary = {}
static var _order: Array[String] = []

static func is_key(key: String) -> bool:
	var parsed := RegEx.create_from_string("^hero/([mw](zs|ck|fs))_w([0-9]{1,3})_c([0-9]{1,3})_h([0-9]{1,3})$").search(key)
	return parsed != null and GeneratedEquipment.valid_key(parsed.get_string(1),[int(parsed.get_string(3)),int(parsed.get_string(4)),int(parsed.get_string(5))])

static func _part(source: String, frame: int, transform: int) -> Image:
	var id := "%s:%d:%d" % [source,frame,transform]
	if _parts.has(id): return _parts[id]
	if not _data.parts.has(source): return null
	var entry: Dictionary = _data.parts[source]
	if frame >= entry.frames.size(): return null
	if not _images.has(source):
		var texture: Texture2D = load(entry.texture)
		var image := texture.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_images[source] = image
	var r: Array = entry.frames[frame]
	var part: Image = _images[source].get_region(Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])))
	match transform:
		1: part.rotate_90(CLOCKWISE)
		2: part.rotate_180()
		3: part.rotate_90(COUNTERCLOCKWISE)
		4: part.flip_x()
		5: part.flip_x();part.rotate_90(CLOCKWISE)
		6: part.flip_y()
		7: part.flip_x();part.rotate_90(COUNTERCLOCKWISE)
	_parts[id] = part
	return part

static func build(key: String, base: Dictionary) -> Dictionary:
	if _prepared.has(key): return _prepared[key]
	if not is_key(key): return {}
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/hero-parts.json"))
		_data.parts.merge(GeneratedEquipment.manifest().parts)
	var fields := key.trim_prefix("hero/").split("_")
	var stem: String = fields[0]
	var weapon := int(fields[1].trim_prefix("w"))
	var clothing := int(fields[2].trim_prefix("c"))
	var head := int(fields[3].trim_prefix("h"))
	var recipe: Dictionary = _data.recipes[stem]
	var replacements := {recipe.sources[2]:"e"+stem.substr(1)+str(weapon)}
	if clothing > 0 and clothing <= 11:
		var body := clothing - 2 if clothing >= 3 else clothing + (2 if stem.ends_with("fs") else 1)
		for i in [[1,""],[3,"q"],[4,"x"]]: replacements[recipe.sources[i[0]]] = stem+str(body)+i[1]
	if head > 0 and head <= 9: replacements[recipe.sources[0]] = stem+"t"+str(head)
	var generated := GeneratedEquipment.replacements(stem, weapon, clothing, head, recipe.sources)
	# A foreign set code must not silently fall back to a native part.
	if (weapon >= 28 and not generated.has(recipe.sources[2])) or (clothing >= 12 and not generated.has(recipe.sources[1])) or (head >= 10 and not generated.has(recipe.sources[0])): return {}
	replacements.merge(generated, true)
	var frames: Array = []
	var centers: Array = []
	var left := 0;var top := 0;var right := 1;var bottom := 1
	for layers in recipe.frames:
		var images: Array = []
		var center := 0
		for layer in layers:
			if weapon == 0 and layer.source == recipe.sources[2]: continue
			var source: String = replacements.get(layer.source,layer.source)
			var part := _part(source,int(layer.frame),int(layer.transform))
			if part == null: return {}
			if layer.source == recipe.sources[0] and int(layer.frame) == 0: center = int(layer.x) + part.get_width()/2
			images.append([part,int(layer.x),int(layer.y)])
		centers.append(center)
		for image in images:
			image[1] -= center
			left = mini(left,image[1]);top = mini(top,image[2])
			right = maxi(right,image[1]+image[0].get_width());bottom = maxi(bottom,image[2]+image[0].get_height())
		frames.append(images)
	var trimmed: Array = []
	var placements: Array = []
	var x := 0;var y := 0;var shelf := 0;var atlas_width := 512
	for images in frames:
		var canvas := Image.create(right-left,bottom-top,false,Image.FORMAT_RGBA8)
		for image in images: canvas.blend_rect(image[0],Rect2i(Vector2i.ZERO,image[0].get_size()),Vector2i(image[1]-left,image[2]-top))
		var used := canvas.get_used_rect()
		if used.size == Vector2i.ZERO: used = Rect2i(0,0,1,1)
		if x + used.size.x > atlas_width: x = 0;y += shelf;shelf = 0
		placements.append([x,y,used.size.x,used.size.y,used.position.x,used.position.y])
		trimmed.append(canvas.get_region(used))
		x += used.size.x;shelf = maxi(shelf,used.size.y)
	var atlas := Image.create(atlas_width,y+shelf,false,Image.FORMAT_RGBA8)
	for i in trimmed.size(): atlas.blit_rect(trimmed[i],Rect2i(Vector2i.ZERO,trimmed[i].get_size()),Vector2i(placements[i][0],placements[i][1]))
	var info := base.duplicate(true)
	info.width = right-left;info.height = bottom-top;info.origin = [left,top]
	info.frame_regions = placements
	# Head replacement changes the stabilization center. Ground and recoil anchors
	# must use that same source center; attack root translation is unchanged.
	for animation in info.playback:
		info.native_battle.pose_x[animation] = info.playback[animation].map(func(step: Array) -> int: return int(centers[int(step[0])]))
	var result := {"info":info,"texture":ImageTexture.create_from_image(atlas)}
	_prepared[key] = result;_order.append(key)
	while _order.size()>6: _prepared.erase(_order.pop_front())
	return result
