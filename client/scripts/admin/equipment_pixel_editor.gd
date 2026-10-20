extends Window
signal applied
signal editor_closed
const DOCUMENT := preload("res://scripts/admin/pixel_document.gd")
const CANVAS := preload("res://scripts/admin/pixel_canvas.gd")
const PREVIEW := preload("res://scripts/admin/data_preview.gd")
const LAYOUT := preload("res://scripts/admin/admin_window_layout.gd")
var mapping: Dictionary={}
var equipment: Dictionary={}
var ui_theme: Theme
var documents: Dictionary={}
var part_choice: OptionButton
var frame_choice: OptionButton
var canvas: Control
var canvas_scroll: ScrollContainer
var preview: Control
var palette: ColorPickerButton
var offset_x: SpinBox
var offset_y: SpinBox
var status: Label
var tool_buttons: Dictionary={}
var action_choice: OptionButton
var playback: CheckButton
var pose_frame: SpinBox
var preview_timer: Timer
var save_button: Button
var undo_button: Button
var redo_button: Button
var discard_dialog: ConfirmationDialog
var expected_fingerprint := ""
var _closing := false

func _ready() -> void:
	title="装备像素编辑";size=Vector2i(1100,760);min_size=Vector2i(920,680)
	close_requested.connect(request_close)
	AppearanceEdits.reload_saved()
	expected_fingerprint=AppearanceEdits.fingerprint()
	_build()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button:=Button.new();button.text=text;parent.add_child(button);button.pressed.connect(callback);return button

func _label(parent: Node, text: String) -> Label:
	var label:=Label.new();label.text=text;parent.add_child(label);return label

func _row(parent: Node) -> HBoxContainer:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);parent.add_child(row);return row

func _spin(parent: Node, low: int, high: int, value: int) -> SpinBox:
	var spin:=SpinBox.new();spin.min_value=low;spin.max_value=high;spin.step=1;spin.value=value;spin.custom_minimum_size.x=76;parent.add_child(spin);return spin

func _build() -> void:
	var panel:=PanelContainer.new();add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box:=StyleBoxFlat.new();box.bg_color=Color("1a2a37");box.set_content_margin_all(14);panel.add_theme_stylebox_override("panel",box)
	panel.theme=ui_theme
	var root:=VBoxContainer.new();root.add_theme_constant_override("separation",8);panel.add_child(root)
	_label(root,"像素编辑 · "+str(equipment.get("name","装备"))).add_theme_font_size_override("font_size",20)
	var note:=_label(root,"部件被多个装备或动作共用，保存后共同生效。可随时撤销；源图保留。")
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var choices:=_row(root)
	_label(choices,"部件")
	part_choice=OptionButton.new();part_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choices.add_child(part_choice)
	_label(choices,"部件帧")
	frame_choice=OptionButton.new();frame_choice.custom_minimum_size.x=180;choices.add_child(frame_choice)
	var tools:=_row(root)
	for definition in [["pencil","铅笔 (P)"],["eraser","橡皮擦 (E)"],["picker","取色器 (I)"],["move","移动部件 (V)"]]:
		var id: String=definition[0]
		var button:=_button(tools,definition[1],func()->void:set_tool(id))
		button.toggle_mode=true;tool_buttons[id]=button
	palette=ColorPickerButton.new();palette.color=Color("b64b79");palette.custom_minimum_size=Vector2(50,30);tools.add_child(palette)
	palette.color_changed.connect(func(value:Color)->void:canvas.color=value)
	var zoom_row:=_row(root)
	_label(zoom_row,"放大")
	var zoom:=_spin(zoom_row,3,24,8)
	var grid:=CheckButton.new();grid.text="像素网格";grid.button_pressed=true;zoom_row.add_child(grid)
	var linked:=CheckButton.new();linked.text="移动时联动本部件所有帧";linked.button_pressed=true;zoom_row.add_child(linked)
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.split_offset=690;root.add_child(split)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(430,320);scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;split.add_child(scroll)
	canvas_scroll=scroll
	canvas=CANVAS.new();scroll.add_child(canvas)
	var right:=VBoxContainer.new();right.custom_minimum_size.x=280;split.add_child(right)
	_label(right,"整个人物 · 实时预览")
	action_choice=OptionButton.new();right.add_child(action_choice)
	var actor_info:=OriginalArt.actor_info(mapping.get("装备后动画",""))
	for definition in [["idle","待机"],["walk","行走"],["attack","攻击"],["cast","施法"],["hurt","受击"]]:
		if actor_info.get("playback",{}).has(definition[0]):
			action_choice.add_item(definition[1]);action_choice.set_item_metadata(action_choice.item_count-1,definition[0])
	var play_row:=_row(right)
	playback=CheckButton.new();playback.text="播放";playback.button_pressed=true;play_row.add_child(playback)
	_label(play_row,"动作帧");pose_frame=_spin(play_row,0,100,0)
	preview=PREVIEW.new();preview.custom_minimum_size=Vector2(240,230);preview.fit_visible_animation=true;preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(preview)
	var position_row:=_row(right)
	_label(position_row,"X");offset_x=_spin(position_row,-128,128,0)
	_label(position_row,"Y");offset_y=_spin(position_row,-128,128,0)
	_label(right,"青框：当前部件  /  黄框：原位置\n方向键微调；右键临时取色。\n画布编辑当前帧，人物预览检查接缝。").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_button(right,"位置归零",func()->void:_set_offset(Vector2i.ZERO))
	_button(right,"恢复本部件源图",_restore_source)
	var bottom:=_row(root)
	undo_button=_button(bottom,"撤销 Ctrl+Z",_undo)
	redo_button=_button(bottom,"重做 Ctrl+Y",_redo)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bottom.add_child(spacer)
	save_button=_button(bottom,"保存并应用",save_changes)
	_button(bottom,"关闭",request_close)
	status=_label(root,"请选择部件。");status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	discard_dialog=ConfirmationDialog.new();discard_dialog.dialog_text="仍有未保存修改，关闭并丢弃这些修改？";discard_dialog.ok_button_text="丢弃并关闭";discard_dialog.cancel_button_text="继续编辑";add_child(discard_dialog);discard_dialog.confirmed.connect(discard_and_close)
	preview_timer=Timer.new();preview_timer.one_shot=true;preview_timer.wait_time=0.12;add_child(preview_timer);preview_timer.timeout.connect(_preview)
	part_choice.item_selected.connect(func(_index:int)->void:_select_part())
	frame_choice.item_selected.connect(func(_index:int)->void:_select_frame())
	zoom.value_changed.connect(func(value:float)->void:canvas.zoom=int(value);canvas.refresh();_center_canvas())
	grid.toggled.connect(func(value:bool)->void:canvas.grid=value;canvas.queue_redraw())
	linked.toggled.connect(func(value:bool)->void:canvas.move_all=value)
	canvas.document_changed.connect(_changed)
	canvas.color_picked.connect(func(value:Color)->void:palette.color=value;canvas.color=value;set_tool("pencil"))
	offset_x.value_changed.connect(func(_value:float)->void:_set_offset(Vector2i(int(offset_x.value),int(offset_y.value))))
	offset_y.value_changed.connect(func(_value:float)->void:_set_offset(Vector2i(int(offset_x.value),int(offset_y.value))))
	for chooser in [action_choice]: chooser.item_selected.connect(func(_index:int)->void:_preview())
	playback.toggled.connect(func(_value:bool)->void:_preview())
	pose_frame.value_changed.connect(func(_value:float)->void:_preview())
	set_tool("pencil")
	var slot: String={"weapon":"武器","armor":"衣服","hat":"头饰"}.get(equipment.get("slot",""),"")
	var initial_part:=0
	for group in ["武器","衣服","头饰"]:
		if group!=slot and not mapping.get("edit_full_set",false): continue
		for source in mapping.get("装备后部件",{}).get(group,[]):
			if not AppearanceEdits.specs().has(source) or documents.has(source): continue
			var doc:=DOCUMENT.new();doc.open(source);documents[source]=doc
			part_choice.add_item(group+" · "+source);part_choice.set_item_metadata(part_choice.item_count-1,source)
			if group==slot: initial_part=part_choice.item_count-1
	if part_choice.item_count>0: part_choice.select(initial_part);_select_part()
	else: status.text="该装备没有可编辑的外观部件。";save_button.disabled=true

func document() -> RefCounted:
	return documents.get(part_choice.get_item_metadata(part_choice.selected)) if part_choice.selected>=0 else null

func _select_part() -> void:
	canvas.finish_stroke()
	var doc:=document()
	frame_choice.clear()
	if doc==null: return
	for index in doc.frames.size():
		var label:="帧 %d"%index
		if doc.source in mapping.get("装备后部件",{}).get("头饰",[]) and doc.frames.size()==2: label+=" · 主头部" if index==0 else " · 下方发尾"
		var rect:Rect2i=doc.region(index)
		frame_choice.add_item("%s (%d×%d)"%[label,rect.size.x,rect.size.y])
	frame_choice.select(0);canvas.document=doc;_select_frame()

func _select_frame() -> void:
	canvas.finish_stroke();canvas.frame=frame_choice.selected;canvas.refresh();_changed();_center_canvas()

func _center_canvas() -> void:
	await get_tree().process_frame
	if not is_instance_valid(canvas) or canvas.document==null: return
	var bounds:Rect2i=canvas.document.image.get_region(canvas.document.region(canvas.frame)).get_used_rect()
	var point:=Vector2(bounds.get_center()) if bounds.has_area() else Vector2(canvas.document.region(canvas.frame).size)/2
	point+=canvas.origin+Vector2(canvas.document.offsets[canvas.frame][0],canvas.document.offsets[canvas.frame][1])
	canvas_scroll.scroll_horizontal=maxi(0,roundi(point.x*canvas.zoom-canvas_scroll.size.x/2))
	canvas_scroll.scroll_vertical=maxi(0,roundi(point.y*canvas.zoom-canvas_scroll.size.y/2))

func set_tool(id: String) -> void:
	canvas.tool=id
	for key in tool_buttons: tool_buttons[key].set_pressed_no_signal(key==id)

func _dirty() -> bool:
	for doc in documents.values():
		if doc.dirty(): return true
	return false

func _changed() -> void:
	var doc:=document()
	if doc==null: return
	offset_x.set_value_no_signal(doc.offsets[canvas.frame][0]);offset_y.set_value_no_signal(doc.offsets[canvas.frame][1])
	undo_button.disabled=doc.undo_stack.is_empty();redo_button.disabled=doc.redo_stack.is_empty()
	title=("● " if _dirty() else "")+"装备像素编辑 · "+str(equipment.get("name",""))
	save_button.disabled=not _dirty()
	status.text="未保存修改 · 可撤销，保存后应用到此项目。" if _dirty() else "当前部件已与保存版本一致。"
	if preview_timer.is_stopped(): preview_timer.start()

func _preview() -> void:
	if documents.is_empty(): return
	var draft:Dictionary={}
	for id in documents: draft[id]=documents[id].data()
	AppearanceEdits.set_draft(draft)
	preview.display({"preview":{"kind":"actor","art":mapping["装备后动画"]}})
	var action:String=action_choice.get_item_metadata(action_choice.selected)
	preview.play_animation(action)
	if is_instance_valid(preview.sprite):
		pose_frame.max_value=preview.sprite.sprite_frames.get_frame_count(preview.sprite.animation)-1
		if not playback.button_pressed:
			preview.sprite.pause();preview.sprite.frame=int(pose_frame.value)

func _set_offset(value: Vector2i) -> void:
	var doc:=document()
	if doc==null: return
	var old:=Vector2i(doc.offsets[canvas.frame][0],doc.offsets[canvas.frame][1])
	if value==old: return
	doc.checkpoint();doc.move(canvas.frame,value-old,canvas.move_all);canvas.refresh();_changed()

func _restore_source() -> void:
	document().restore_source();canvas.refresh();_changed()

func _undo() -> void:
	if document()!=null and document().undo(): canvas.refresh();_changed()

func _redo() -> void:
	if document()!=null and document().redo(): canvas.refresh();_changed()

func save_changes() -> void:
	canvas.finish_stroke();preview_timer.stop()
	var changed:Dictionary={}
	for id in documents:
		if documents[id].dirty(): changed[id]=documents[id].data()
	if changed.is_empty(): return
	var result:=AppearanceEdits.save(changed,expected_fingerprint)
	if result.ok:
		expected_fingerprint=AppearanceEdits.fingerprint()
		for doc in documents.values(): doc.baseline=doc.stamp()
		_changed();status.text=result.message;_preview();applied.emit()
	else: status.text=result.message

func request_close() -> void:
	if _dirty(): discard_dialog.popup_centered()
	else: discard_and_close()

func discard_and_close() -> void:
	if _closing: return
	_closing=true;preview_timer.stop();AppearanceEdits.clear_draft();editor_closed.emit();queue_free()

func _exit_tree() -> void:
	if not _closing: AppearanceEdits.clear_draft()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if gui_get_focus_owner() is LineEdit: return
	if event.ctrl_pressed:
		if event.keycode==KEY_Z: _undo()
		elif event.keycode==KEY_Y: _redo()
		elif event.keycode==KEY_S: save_changes()
		else: return
	elif event.keycode in [KEY_P,KEY_E,KEY_I,KEY_V]:
		set_tool({KEY_P:"pencil",KEY_E:"eraser",KEY_I:"picker",KEY_V:"move"}[event.keycode])
	elif event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN] and document()!=null:
		var delta: Vector2i={KEY_LEFT:Vector2i.LEFT,KEY_RIGHT:Vector2i.RIGHT,KEY_UP:Vector2i.UP,KEY_DOWN:Vector2i.DOWN}[event.keycode]
		var old:Array=document().offsets[canvas.frame]
		_set_offset(Vector2i(int(old[0]),int(old[1]))+delta)
	else: return
	set_input_as_handled()
