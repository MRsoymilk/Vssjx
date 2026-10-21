class_name HeroAppearance
extends RefCounted
## Compose original layers on demand, rather than shipping thousands of combinations.
static var _images: Dictionary = {}
static var _parts: Dictionary = {}
static var _prepared: Dictionary = {}
static var _order: Array[String] = []
static var _edit_revision := -1
static var _resource_revision := -1

static func outfit_for_key(key:String)->NativeHeroOutfit:
	var parsed:=RegEx.create_from_string("^(hero|creation)/([mw](zs|ck|fs))(_w([0-9]{1,3})_c([0-9]{1,3})(_h([0-9]{1,3}))?)?$").search(key)
	if parsed==null:return null
	if parsed.get_string(1)=="creation" and parsed.get_string(4).is_empty():return AppearanceResources.creation_outfit(parsed.get_string(2))
	var codes:=[1,0,0] if parsed.get_string(4).is_empty() else [int(parsed.get_string(5)),int(parsed.get_string(6)),0 if parsed.get_string(8).is_empty() else int(parsed.get_string(8))]
	return AppearanceResources.outfit(parsed.get_string(2),codes)

static func composition_key(key: String) -> String:
	var outfit:=outfit_for_key(key)
	return "" if outfit==null or outfit.uses_baked() else outfit.key()

static func is_key(key: String) -> bool:
	return outfit_for_key(key)!=null

static func _part(entry:NativeAppearancePart, frame: int, transform: int) -> Image:
	if entry==null or frame>=entry.regions.size():return null
	var source:=entry.source_id
	var id := "%s:%s:%s:%d:%d" % [source,entry.texture_path,str(entry.regions),frame,transform]
	if _parts.has(id): return _parts[id]
	var image_key:=entry.texture_path+"|"+source
	if not _images.has(image_key):
		var image:=AppearanceEdits.image_for(source)
		if image==null:
			var texture:=load(entry.texture_path) as Texture2D
			if texture==null:return null
			image=texture.get_image()
			if image.is_compressed():image.decompress()
			image.convert(Image.FORMAT_RGBA8)
		_images[image_key] = image
	if not Rect2i(Vector2i.ZERO,_images[image_key].get_size()).encloses(entry.regions[frame]):return null
	var part: Image = _images[image_key].get_region(entry.regions[frame])
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
	var outfit:=outfit_for_key(key)
	return {} if outfit==null else build_outfit(outfit,base)

static func build_outfit(outfit:NativeHeroOutfit,base:Dictionary)->Dictionary:
	AppearanceEdits.ensure_loaded()
	if _edit_revision!=AppearanceEdits.revision or _resource_revision!=AppearanceResources.revision:
		_images.clear();_parts.clear();_prepared.clear();_order.clear()
		_edit_revision=AppearanceEdits.revision;_resource_revision=AppearanceResources.revision
	if outfit==null or not outfit.valid():return {}
	if outfit.recipe.frames.size()!=int(base.get("count",0)):return {}
	var key:=outfit.signature()
	if _prepared.has(key): return _prepared[key]
	var recipe:=outfit.recipe
	var replacements:=outfit.replacements()
	var frames: Array = []
	var centers: Array = []
	var left := 0;var top := 0;var right := 1;var bottom := 1
	for layers in recipe.frames:
		var images: Array = []
		var center := 0
		for layer in layers:
			if outfit.weapon.parts.is_empty() and layer.source == recipe.sources[2]: continue
			var source:NativeAppearancePart=replacements.get(layer.source,AppearanceResources.part(layer.source))
			var part := _part(source,int(layer.frame),int(layer.transform))
			if part == null: return {}
			if layer.source == recipe.sources[0] and int(layer.frame) == 0: center = int(layer.x) + part.get_width()/2
			var shift:=AppearanceEdits.offset_for(source.source_id,int(layer.frame),int(layer.transform))
			images.append([part,int(layer.x)+shift.x,int(layer.y)+shift.y])
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
	# Fixed legacy looks kept the original head: changing only weapon/clothing
	# must not add new attack/cast root offsets when their atlases become dynamic.
	# Non-default heads retain the existing head-replacement stabilization rules.
	if outfit.head.visual_code!=0 or outfit.head.parts[0].source_id!=recipe.sources[0]:
		for animation in info.playback:
			info.native_battle.pose_x[animation] = info.playback[animation].map(func(step: Array) -> int: return int(centers[int(step[0])]))
	var result := {"info":info,"texture":ImageTexture.create_from_image(atlas)}
	_prepared[key] = result;_order.append(key)
	while _order.size()>6: _prepared.erase(_order.pop_front())
	return result

static func source_steps(info:Dictionary,index:int)->Array:
	var count:=int(info.get("native_battle",{}).get("source_frame_count",info.count));var steps:Array=[]
	for step in info.sequences[index]:steps.append([count-1-int(step[0]),step[1]])
	return steps

static func sprite_frames(info:Dictionary,texture:Texture2D)->SpriteFrames:
	var frames:=SpriteFrames.new();frames.remove_animation("default")
	var regions:Array[AtlasTexture]=[]
	for i in int(info.count):
		var region:=AtlasTexture.new();region.atlas=texture;region.filter_clip=true
		var r:Array=info.frame_regions[i];region.region=Rect2(r[0],r[1],r[2],r[3]);region.margin=Rect2(r[4],r[5],int(info.width)-int(r[2]),int(info.height)-int(r[3]));regions.append(region)
	for i in info.sequences.size():
		var name:="source_%d"%i;frames.add_animation(name);frames.set_animation_speed(name,10)
		for step in source_steps(info,i):frames.add_frame(name,regions[int(step[0])],maxf(1,float(step[1])))
	for mode in ["idle","walk","attack","cast","hurt"]:
		if mode in ["cast","hurt"] and not info.get("playback",{}).has(mode):continue
		frames.add_animation(mode);frames.set_animation_speed(mode,6 if mode=="idle" else (8 if mode=="cast" else 10));frames.set_animation_loop(mode,mode in ["idle","walk"])
		var steps:Array=info.get("playback",{}).get(mode,source_steps(info,maxi(0,info.sequences.size()-(6 if mode=="attack" else 1))))
		if steps.is_empty():steps=[[0,1]]
		for step in steps:frames.add_frame(mode,regions[int(step[0])],maxf(1,float(step[1])))
	return frames
