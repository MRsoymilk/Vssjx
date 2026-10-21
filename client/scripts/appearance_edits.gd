class_name AppearanceEdits
extends RefCounted
## Runtime reads saved overrides; only the desktop admin editor writes them.
static var manifest_path := "res://assets/appearance_resources/overrides.tres"
static var image_folder := "res://assets/edited/equipment"
static var revision := 0
static var _loaded := false
static var _saved: Dictionary = {}
static var _draft: Dictionary = {}
static var _images: Dictionary = {}
static var _specs: Dictionary = {}
static var load_error := ""

static func digest(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()

static func specs() -> Dictionary:
	if _specs.is_empty():
		_specs = AppearanceResources.part_specs()
	return _specs

static func fingerprint() -> String:
	return FileAccess.get_sha256(manifest_path) if FileAccess.file_exists(manifest_path) else ""

static func _offsets_valid(value: Variant, count: int) -> bool:
	if not value is Array or value.size()!=count: return false
	for point in value:
		if not point is Array or point.size()!=2: return false
		for number in point:
			if not (number is int or number is float) or not is_finite(float(number)) or floor(float(number))!=float(number) or absf(float(number))>128: return false
	return true

static func reload_saved() -> void:
	_saved={};_images={};_loaded=true;load_error="";revision+=1
	if not FileAccess.file_exists(manifest_path): return
	var data:=ResourceLoader.load(manifest_path,"",ResourceLoader.CACHE_MODE_IGNORE) as NativeAppearanceOverrides
	if data==null or data.format_version!=1:
		load_error="修改清单格式无效，已保留源资源。";return
	for source in data.parts:
		var entry: Variant = data.parts[source]
		if not specs().has(source) or not entry is Dictionary or not entry.get("texture") is String or not entry.texture.begins_with(image_folder+"/") or entry.texture.contains("..") or not entry.texture.ends_with(".png") or not _offsets_valid(entry.get("offsets"),specs()[source].frames.size()):
			load_error="修改清单含无效部件，已忽略："+str(source);continue
		entry.offsets=entry.offsets.map(func(point:Array)->Array:return [int(point[0]),int(point[1])])
		_saved[source]=entry

static func ensure_loaded() -> void:
	if not _loaded: reload_saved()

static func any() -> bool:
	ensure_loaded()
	return not _saved.is_empty() or not _draft.is_empty()

static func source_image(source: String) -> Image:
	var part:=AppearanceResources.part(source)
	if part==null: return null
	var texture: Texture2D = load(part.texture_path)
	var image := texture.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

static func image_for(source: String) -> Image:
	ensure_loaded()
	if _draft.has(source): return _draft[source].image
	if not _saved.has(source): return null
	if _images.has(source): return _images[source]
	var path: String = _saved[source].texture
	# Fresh files work before editor reimport; exported games use imported textures.
	var image: Image
	if FileAccess.file_exists(path):
		image=Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))!=OK: image=null
	if image==null and ResourceLoader.exists(path):
		var texture := ResourceLoader.load(path,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		if texture: image=texture.get_image()
	var original:=source_image(source)
	if image==null or image.get_size()!=original.get_size():
		load_error="修改图片缺失或尺寸不匹配："+source
		return null
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	_images[source]=image
	return image

static func offsets_for(source: String) -> Array:
	ensure_loaded()
	if _draft.has(source): return _draft[source].offsets.duplicate(true)
	if _saved.has(source) and image_for(source)!=null: return _saved[source].offsets.duplicate(true)
	var result: Array=[]
	for frame in specs()[source].frames: result.append([0,0])
	return result

static func offset_for(source: String, frame: int, transform: int) -> Vector2i:
	ensure_loaded()
	if not _draft.has(source) and not _saved.has(source): return Vector2i.ZERO
	var points:=offsets_for(source)
	var point:=Vector2i(int(points[frame][0]),int(points[frame][1]))
	match transform:
		1: return Vector2i(-point.y,point.x)
		2: return -point
		3: return Vector2i(point.y,-point.x)
		4: return Vector2i(-point.x,point.y)
		5: return Vector2i(-point.y,-point.x)
		6: return Vector2i(point.x,-point.y)
		7: return Vector2i(point.y,point.x)
	return point

static func set_draft(documents: Dictionary) -> void:
	_draft=documents;revision+=1

static func clear_draft() -> void:
	if not _draft.is_empty(): _draft={};revision+=1

static func save(documents: Dictionary, expected_fingerprint: String) -> Dictionary:
	ensure_loaded()
	if OS.has_feature("web") or OS.has_feature("Android") or OS.has_feature("iOS"):
		return {"ok":false,"message":"请从本地Godot项目的数据管理器保存资源。"}
	if fingerprint()!=expected_fingerprint:
		return {"ok":false,"message":"资源清单已被其他窗口修改，请关闭并重新打开编辑器，避免覆盖。"}
	if not load_error.is_empty(): return {"ok":false,"message":load_error}
	var next:=_saved.duplicate(true)
	for source in documents:
		var document: Dictionary=documents[source]
		if not specs().has(source) or not document.get("image") is Image or document.image.get_size()!=source_image(source).get_size() or not _offsets_valid(document.get("offsets"),specs()[source].frames.size()):
			return {"ok":false,"message":"部件尺寸或位移无效："+str(source)}
	# Content-addressed PNGs preserve previous versions and never overwrite sources.
	var error:=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(image_folder))
	if error!=OK: return {"ok":false,"message":"无法创建资源目录："+error_string(error)}
	for source in documents:
		var image: Image=documents[source].image
		var bytes:=image.save_png_to_buffer()
		var path:String=image_folder+"/"+str(source).sha256_text().left(12)+"-"+digest(bytes).left(20)+".png"
		if not FileAccess.file_exists(path):
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file==null: return {"ok":false,"message":"无法写入图片："+path}
			file.store_buffer(bytes)
			var write_error:=file.get_error()
			file.close()
			if write_error!=OK: return {"ok":false,"message":"图片写入失败："+error_string(write_error)}
		next[source]={"texture":path,"offsets":documents[source].offsets}
	if FileAccess.file_exists(manifest_path):
		var history:=image_folder+"/history"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(history))
		var backup:=FileAccess.open(history+"/"+str(Time.get_unix_time_from_system()).replace(".","-")+"-"+str(Time.get_ticks_usec())+".tres",FileAccess.WRITE)
		if backup==null: return {"ok":false,"message":"无法备份现有修改清单，未应用。"}
		backup.store_buffer(FileAccess.get_file_as_bytes(manifest_path))
		var backup_error:=backup.get_error()
		backup.close()
		if backup_error!=OK: return {"ok":false,"message":"备份写入失败，未应用："+error_string(backup_error)}
	var output:=NativeAppearanceOverrides.new();output.parts=next
	var pending:=manifest_path+".pending.tres"
	var manifest_error:=ResourceSaver.save(output,pending)
	if manifest_error!=OK: return {"ok":false,"message":"清单写入失败："+error_string(manifest_error)}
	if fingerprint()!=expected_fingerprint:
		DirAccess.remove_absolute(pending)
		return {"ok":false,"message":"保存期间清单发生变化，请重新打开编辑器。"}
	error=DirAccess.rename_absolute(pending,manifest_path)
	if error!=OK: return {"ok":false,"message":"应用清单失败："+error_string(error)}
	clear_draft();reload_saved()
	return {"ok":true,"message":"已保存并应用。游戏重新创建人物时读取此版本；网页/APK需重新打包后分发。"}
