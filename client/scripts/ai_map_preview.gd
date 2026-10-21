extends Control
## Runtime preview; deliberately independent of editor-only admin resources.
const ATLAS := preload("res://assets/tiles/original_tiles.png")
static var textures: Dictionary = {}

static func held_texture(path: String) -> Texture2D:
	if not textures.has(path): textures[path]=load(path)
	return textures[path]
var map_data: Dictionary = {}

static func draw_scenery(canvas: CanvasItem, data: Dictionary, start: Vector2, zoom: float) -> void:
	var native:=NativeWorldMaps.preview(String(data.get("map_id","")))
	var props: Array = native.get("scenery",data.get("scenery",[])).duplicate()
	props.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.y<b.y)
	for prop in props:
		var info := OriginalArt.actor_info(prop.art)
		if info.is_empty(): continue
		var texture: Texture2D = held_texture(info.texture)
		var size := Vector2(info.width,info.height)
		var offset := Vector2(info.origin[0],info.origin[1])
		canvas.draw_texture_rect_region(texture,Rect2(start+(Vector2(prop.x,prop.y)+offset)*zoom,size*zoom),Rect2(Vector2.ZERO,size))

static func draw_spawn(canvas: CanvasItem, data: Dictionary, start: Vector2, zoom: float) -> void:
	var tile: Texture2D=preload("res://assets/ui/portal_tile.png")
	for gate in data.get("exits",[]):
		for point in gate.get("cells",[gate.cell]):
			canvas.draw_texture_rect(tile,Rect2(start+Vector2(point[0]*16,point[1]*16)*zoom,Vector2(16,16)*zoom),false)
	var point:=start+Vector2(data.spawn[0]*16+8,data.spawn[1]*16+8)*zoom
	# One entry landing per scene; the cyan spiral tiles above are transfer exits.
	canvas.draw_circle(point,maxf(1.5,zoom*2),Color("f7ed21"))

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true
	resized.connect(queue_redraw)

func display(data: Dictionary) -> void:
	map_data=data
	queue_redraw()

func _draw() -> void:
	if map_data.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO,size),Color("14282e"))
	var cell:=minf((size.x-12)/32.0,(size.y-12)/32.0)
	var start:Vector2=(size-Vector2.ONE*cell*32.0)/2.0
	var tiles:PackedInt32Array=NativeWorldMaps.preview(String(map_data.map_id)).tiles
	for index in 1024:
		var tile:=int(tiles[index])
		draw_texture_rect_region(ATLAS,Rect2(start+Vector2(index%32,index/32)*cell,Vector2.ONE*cell),Rect2(tile%32*16,tile/32*16,16,16))
	draw_scenery(self,map_data,start,cell/16.0)
	draw_spawn(self,map_data,start,cell/16.0)
	for r in map_data.residents:
		var point:Vector2=start+(Vector2(r.cell[0],r.cell[1])+Vector2.ONE*0.5)*cell
		draw_circle(point,maxf(2.0,cell*0.6),Color("ffe390") if r.kind=="npc" else Color("ff5e5e"))
		var font: Font=preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
		draw_string_outline(font,point+Vector2(4,-3),r.name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,2,Color("14282e"))
		draw_string(font,point+Vector2(4,-3),r.name,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff2cf"))
