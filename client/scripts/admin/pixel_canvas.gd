extends Control
signal document_changed
signal color_picked(color: Color)
var document: RefCounted
var frame := 0
var tool := "pencil"
var color := Color("b64b79")
var zoom := 8
var move_all := true
var grid := true
var origin := Vector2(20,20)
var _painting := false
var _last := Vector2i.ZERO
var _texture: ImageTexture

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode=Control.FOCUS_ALL
	mouse_default_cursor_shape=Control.CURSOR_CROSS
	mouse_filter=Control.MOUSE_FILTER_STOP

func refresh() -> void:
	if document==null: return
	var region: Rect2i=document.region(frame)
	var offset:=Vector2(document.offsets[frame][0],document.offsets[frame][1])
	if not _painting:
		origin=Vector2(20,20)-offset.min(Vector2.ZERO)
		custom_minimum_size=(Vector2(region.size)+Vector2(40,40)+offset.abs())*zoom
	_texture=ImageTexture.create_from_image(document.image.get_region(region))
	queue_redraw()

func local_pixel(position: Vector2, with_offset := true) -> Vector2i:
	var offset:=Vector2(document.offsets[frame][0],document.offsets[frame][1]) if with_offset else Vector2.ZERO
	var pixel:=position/zoom-origin-offset
	return Vector2i(floori(pixel.x),floori(pixel.y))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101923"))
	if document==null: return
	for y in range(0,int(size.y),zoom*4):
		for x in range(0,int(size.x),zoom*4):
			if (x/(zoom*4)+y/(zoom*4))%2==0: draw_rect(Rect2(x,y,zoom*4,zoom*4),Color("233440"))
	var rect:=Rect2(origin*zoom,Vector2(document.region(frame).size)*zoom)
	draw_rect(rect,Color("bba36b"),false,1)
	var shifted:=rect
	shifted.position+=Vector2(document.offsets[frame][0],document.offsets[frame][1])*zoom
	if _texture: draw_texture_rect(_texture,shifted,false)
	if grid and zoom>=6:
		for x in range(int(shifted.size.x)/zoom+1): draw_line(shifted.position+Vector2(x*zoom,0),shifted.position+Vector2(x*zoom,shifted.size.y),Color(0.7,0.85,0.9,0.15))
		for y in range(int(shifted.size.y)/zoom+1): draw_line(shifted.position+Vector2(0,y*zoom),shifted.position+Vector2(shifted.size.x,y*zoom),Color(0.7,0.85,0.9,0.15))
	draw_rect(shifted,Color("60dfbd"),false,2)

func _stroke(a: Vector2i, b: Vector2i) -> void:
	var count:=maxi(absi(b.x-a.x),absi(b.y-a.y))
	for index in count+1:
		var point:=Vector2i(Vector2(a).lerp(Vector2(b),float(index)/maxi(count,1)).round())
		document.paint(frame,point,Color.TRANSPARENT if tool=="eraser" else color)

func _gui_input(event: InputEvent) -> void:
	if document==null: return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			grab_focus()
			var point:=local_pixel(event.position)
			if event.button_index==MOUSE_BUTTON_RIGHT or tool=="picker":
				color_picked.emit(document.sample(frame,point));accept_event();return
			if tool!="move" and not Rect2i(Vector2i.ZERO,document.region(frame).size).has_point(point): return
			document.checkpoint();_painting=true
			_last=local_pixel(event.position,tool!="move")
			if tool!="move": _stroke(_last,_last)
			refresh();document_changed.emit()
		else: finish_stroke()
		accept_event()
	elif event is InputEventMouseMotion and _painting:
		var point:=local_pixel(event.position,tool!="move")
		if tool=="move": document.move(frame,point-_last,move_all)
		else: _stroke(_last,point)
		_last=point;refresh();document_changed.emit();accept_event()

func finish_stroke() -> void:
	if _painting: _painting=false;refresh();document_changed.emit()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT: finish_stroke()
