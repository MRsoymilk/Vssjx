extends RefCounted
## One native atlas and its independent frame placement offsets.
var source := ""
var image: Image
var frames: Array=[]
var offsets: Array=[]
var undo_stack: Array=[]
var redo_stack: Array=[]
var baseline := ""

func open(id: String) -> void:
	source=id
	frames=AppearanceEdits.specs()[source].frames
	image=AppearanceEdits.image_for(source)
	if image==null: image=AppearanceEdits.source_image(source)
	image=image.duplicate()
	offsets=AppearanceEdits.offsets_for(source)
	baseline=stamp()

func stamp() -> String:
	return AppearanceEdits.digest(image.get_data())+JSON.stringify(offsets)

func dirty() -> bool: return stamp()!=baseline

func checkpoint() -> void:
	undo_stack.append({"image":image.duplicate(),"offsets":offsets.duplicate(true)})
	if undo_stack.size()>64: undo_stack.pop_front()
	redo_stack.clear()

func _restore(from: Array, to: Array) -> bool:
	if from.is_empty(): return false
	to.append({"image":image.duplicate(),"offsets":offsets.duplicate(true)})
	var snapshot: Dictionary=from.pop_back()
	image=snapshot.image;offsets=snapshot.offsets
	return true

func undo() -> bool: return _restore(undo_stack,redo_stack)
func redo() -> bool: return _restore(redo_stack,undo_stack)

func region(frame: int) -> Rect2i:
	var r: Array=frames[frame]
	return Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3]))

func paint(frame: int, point: Vector2i, color: Color) -> void:
	var r:=region(frame)
	if Rect2i(Vector2i.ZERO,r.size).has_point(point): image.set_pixelv(r.position+point,color)

func sample(frame: int, point: Vector2i) -> Color:
	var r:=region(frame)
	return image.get_pixelv(r.position+point) if Rect2i(Vector2i.ZERO,r.size).has_point(point) else Color.TRANSPARENT

func move(frame: int, delta: Vector2i, all_frames: bool) -> void:
	for index in frames.size():
		if index!=frame and not all_frames: continue
		var old: Array=offsets[index]
		offsets[index]=[clampi(int(old[0])+delta.x,-128,128),clampi(int(old[1])+delta.y,-128,128)]

func restore_source() -> void:
	checkpoint()
	image=AppearanceEdits.source_image(source)
	for index in offsets.size(): offsets[index]=[0,0]

func data() -> Dictionary: return {"image":image,"offsets":offsets}
