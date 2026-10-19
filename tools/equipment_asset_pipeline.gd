extends SceneTree
## Repeatable native frame slicing, no animation or original-resource rewriting.
const IconCleanup := preload("equipment_icon_cleanup.gd")
const ROOT := "res://../"
const REVIEW := ROOT + "work/ai-equipment-review-20261018-v3/"
const WORK := ROOT + "work/boneglow-production/"
const DATA := ROOT + "analysis/ai-generated/equipment/boneglow/"
const SETS := [
	["01_male_lishi", "mzs", "玄骸镇岳", 14, 2],
	["02_female_lishi", "wzs", "赤翎破军", 14, 2],
	["03_male_xiake", "mck", "紫冥斩魄", 1, 2],
	["04_female_xiake", "wck", "霜骨流萤", 1, 2],
	["05_male_yinzhe", "mfs", "幽篁摄灵", 2, 3],
	["06_female_yinzhe", "wfs", "苍灵月骨", 2, 3]
]
var data_dir := DATA
var work_dir := WORK
var family := "boneglow"
var definitions: Array = SETS
var sheet_rows := 5
var icon_start_cell := -1
var weapon_icon_ids: Array = []
var atlas_overrides: Dictionary = {}
var patch_only := false
const ICON_SLOTS := ["weapon","hat","armor","wrist","belt","pants","boots","pendant","ring","necklace"]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	patch_only = "--patch-only" in args
	var config_index := args.find("--config")
	if config_index >= 0:
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[config_index+1]))
		family = config.family
		data_dir = ROOT+"analysis/ai-generated/equipment/"+family+"/"
		work_dir = ROOT+"work/"+family+"-production/"
		definitions = config.sets
		sheet_rows = int(config.get("sheet_rows",5))
		icon_start_cell = int(config.get("icon_start_cell",-1))
		weapon_icon_ids = config.get("weapon_icon_ids",[])
		atlas_overrides = config.get("atlas_overrides",{})
		for override in atlas_overrides.values():
			override.cells = override.cells.map(func(value: Variant)->int:return int(value))
	if "build" in OS.get_cmdline_user_args():
		build_runtime()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(work_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data_dir))
	var parts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/hero-parts.json"))
	var manifest: Array = []
	for definition_index in definitions.size():
		var definition: Array = definitions[definition_index]
		var id: String = definition[0]
		var stem: String = definition[1]
		var recipe: Dictionary = parts.recipes[stem]
		var sources := [stem+"t"+str(int(definition[4])), recipe.sources[1], recipe.sources[3], recipe.sources[4], "e"+stem.substr(1)+str(int(definition[3]))]
		var atlas := Image.create(1024, 256*sheet_rows, false, Image.FORMAT_RGBA8)
		var cells: Array = []
		for source in sources:
			var info: Dictionary = parts.parts[source]
			var image := Image.load_from_file(ProjectSettings.globalize_path(info.texture))
			for frame in info.frames.size():
				var r: Array = info.frames[frame]
				var tile := image.get_region(Rect2i(r[0],r[1],r[2],r[3]))
				tile.resize(tile.get_width()*3, tile.get_height()*3, Image.INTERPOLATE_NEAREST)
				var index := cells.size()
				var pos := Vector2i((index%4)*256+(256-tile.get_width())/2, (index/4)*256+(256-tile.get_height())/2)
				atlas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), pos)
				cells.append({"source":source,"frame":frame,"original_region":r,"template_region":[pos.x,pos.y,tile.get_width(),tile.get_height()]})
		if icon_start_cell >= 0:
			var ids: Array = [weapon_icon_ids[definition_index],"original/if1","original/if2","original/if3","original/if4","original/if5","original/if6","original/if9","original/if7","original/if8"]
			var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/shop-v2.json"))
			for index in ids.size():
				var item: Dictionary = catalog.items.filter(func(entry: Dictionary)->bool:return entry.id==ids[index])[0]
				var image := Image.load_from_file(ProjectSettings.globalize_path(item.icon))
				image.resize(image.get_width()*4,image.get_height()*4,Image.INTERPOLATE_NEAREST)
				var cell := icon_start_cell+index
				var pos := Vector2i((cell%4)*256+(256-image.get_width())/2,(cell/4)*256+(256-image.get_height())/2)
				atlas.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),pos)
		atlas.save_png(work_dir+id+"-parts-template.png")
		manifest.append({"id":id,"stem":stem,"name":definition[2],"weapon_template":definition[3],"head_template":definition[4],"cells":cells})
	var file := FileAccess.open(data_dir+"native-frame-templates.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  ")+"\n")
	print("Prepared six exact native part atlases: ", ProjectSettings.globalize_path(work_dir))
	quit()

func clean_alpha(image: Image) -> void:
	# Remove generated antialias fringes at import, preserving solid pixel art.
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x,y)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			image.set_pixel(x,y,color if color.a > 0 else Color.TRANSPARENT)

func atlas_cell(image: Image, index: int, rows: int) -> Image:
	var x := roundi(float(index%4)*image.get_width()/4)
	var y := roundi(float(index/4)*image.get_height()/rows)
	var end_x := roundi(float(index%4+1)*image.get_width()/4)
	var end_y := roundi(float(index/4+1)*image.get_height()/rows)
	return image.get_region(Rect2i(x,y,end_x-x,end_y-y))

func build_runtime() -> void:
	var templates: Array = JSON.parse_string(FileAccess.get_file_as_string(data_dir+"native-frame-templates.json"))
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/hero-parts.json"))
	var report: Array = []
	var slots := ICON_SLOTS
	for entry in templates:
		if patch_only and not atlas_overrides.has(entry.id): continue
		var output: String = "res://assets/generated/equipment/"+family+"/"+entry.stem+"/"
		for folder in ["parts","icons"]: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output+folder))
		var paint_path: String = data_dir+entry.id+"-parts-painted.png"
		var painted := Image.load_from_file(ProjectSettings.globalize_path(paint_path))
		var design := painted if icon_start_cell >= 0 else Image.load_from_file(ProjectSettings.globalize_path(data_dir+entry.id+"-equipment-review.png"))
		clean_alpha(painted)
		clean_alpha(design)
		var override: Dictionary = atlas_overrides.get(entry.id,{})
		var override_image: Image
		if not override.is_empty():
			override_image = Image.load_from_file(ProjectSettings.globalize_path(data_dir+override.file))
			clean_alpha(override_image)
		var atlases := {}
		for index in entry.cells.size():
			if patch_only and index not in override.get("cells",[]): continue
			var cell: Dictionary = entry.cells[index]
			var info: Dictionary = original.parts[cell.source]
			var native := Image.load_from_file(ProjectSettings.globalize_path(info.texture))
			if not atlases.has(cell.source):
				if patch_only:
					var current: String = output+"parts/"+cell.source+".png"
					if not FileAccess.file_exists(current):
						push_error("Cannot patch missing runtime atlas: "+current);quit(1);return
					atlases[cell.source] = Image.load_from_file(ProjectSettings.globalize_path(current))
				else: atlases[cell.source] = Image.create(native.get_width(),native.get_height(),false,Image.FORMAT_RGBA8)
			var r: Array = cell.original_region
			var original_rect := Rect2i(r[0],r[1],r[2],r[3])
			var used := native.get_region(original_rect).get_used_rect()
			if used.size == Vector2i.ZERO: continue
			var input := override_image if index in override.get("cells",[]) else painted
			var tile := atlas_cell(input,index,sheet_rows)
			var new_used := tile.get_used_rect()
			if new_used.size == Vector2i.ZERO:
				push_error("Missing painted frame: "+entry.id+" / "+cell.source+" / "+str(cell.frame))
				quit(1)
				return
			var fitted := tile.get_region(new_used)
			var placement := original_rect.position+used.position
			if patch_only and override.get("preserve_aspect",false):
				var factor := minf(float(used.size.x)/fitted.get_width(),float(used.size.y)/fitted.get_height())
				fitted.resize(maxi(1,roundi(fitted.get_width()*factor)),maxi(1,roundi(fitted.get_height()*factor)),Image.INTERPOLATE_NEAREST)
				# Keep the neck at the native bottom anchor; never stretch eyes/jaw.
				placement += Vector2i((used.size.x-fitted.get_width())/2,used.size.y-fitted.get_height())
			else: fitted.resize(used.size.x, used.size.y, Image.INTERPOLATE_NEAREST)
			if patch_only: atlases[cell.source].fill_rect(original_rect,Color.TRANSPARENT)
			atlases[cell.source].blit_rect(fitted,Rect2i(Vector2i.ZERO,fitted.get_size()),placement)
		for source in atlases:
			var path: String = output+"parts/"+source+".png"
			atlases[source].save_png(path)
			report.append({"path":path,"sha256":FileAccess.get_sha256(path),"native_frames":original.parts[source].frames})
		for index in slots.size():
			if patch_only: continue # A part repair never republishes unrelated icons.
			var source_cell := icon_start_cell+index if icon_start_cell >= 0 else 4+index
			var rows := sheet_rows if icon_start_cell >= 0 else 4
			var input := override_image if source_cell in override.get("cells",[]) else design
			var cell := atlas_cell(input,source_cell,rows)
			var removed := IconCleanup.remove_border_fragments(cell)
			var icon := cell.get_region(cell.get_used_rect())
			var factor := minf(28.0/icon.get_width(),28.0/icon.get_height())
			icon.resize(maxi(1,roundi(icon.get_width()*factor)),maxi(1,roundi(icon.get_height()*factor)),Image.INTERPOLATE_NEAREST)
			var canvas := Image.create(32,32,false,Image.FORMAT_RGBA8)
			canvas.blit_rect(icon,Rect2i(Vector2i.ZERO,icon.get_size()),(Vector2i(32,32)-icon.get_size())/2)
			var path: String = output+"icons/"+slots[index]+".png"
			canvas.save_png(path)
			var record := {"path":path,"sha256":FileAccess.get_sha256(path),"source_cell":source_cell}
			if removed > 0: record["removed_border_pixels"] = removed
			report.append(record)
	var patched_count := report.size()
	if patch_only:
		if report.is_empty():push_error("No configured native frames were patched");quit(1);return
		var saved: Array = JSON.parse_string(FileAccess.get_file_as_string(data_dir+"runtime-import-report.json"))
		for record in report:
			var matches: Array = saved.filter(func(row: Dictionary)->bool:return row.path==record.path)
			if matches.size()!=1:push_error("Patch missing from import manifest: "+record.path);quit(1);return
			matches[0].sha256=record.sha256
		for record in saved:
			for key in ["source_cell","removed_border_pixels"]:
				if record.has(key):record[key]=int(record[key])
		report=saved
	var file := FileAccess.open(data_dir+"runtime-import-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	if patch_only: print("Patched ",patched_count," native runtime texture(s); retained ",report.size()," manifest entries")
	else: print("Published ",report.size()," native runtime textures (30 parts, 60 icons)")
	quit()
