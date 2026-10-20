extends VBoxContainer
const MAPPING := preload("res://scripts/admin/equipment_appearance.gd")
var equipment: Dictionary = {}
var pixel_editor: Window
@onready var before_preview = %BeforePreview
@onready var after_preview = %AfterPreview

func _ready() -> void:
	for chooser in [%Job, %Gender, %Action]: chooser.item_selected.connect(func(_index: int) -> void: _refresh())
	%SetPreview.toggled.connect(func(_value: bool) -> void: _refresh())
	%EditAppearance.pressed.connect(open_pixel_editor)

func open_pixel_editor() -> void:
	if is_instance_valid(pixel_editor): pixel_editor.grab_focus();return
	if equipment.is_empty(): return
	var full_set:bool=%SetPreview.visible and %SetPreview.button_pressed
	if equipment.slot not in ["weapon","armor","hat"] and not full_set: return
	var mapping:=MAPPING.variant(equipment,%Job.selected,%Gender.selected,full_set)
	if mapping.is_empty(): return
	mapping.edit_full_set=full_set
	pixel_editor=preload("res://scripts/admin/equipment_pixel_editor.gd").new()
	pixel_editor.mapping=mapping;pixel_editor.equipment=equipment.duplicate(true);pixel_editor.ui_theme=theme if theme!=null else get_theme()
	add_child(pixel_editor)
	pixel_editor.applied.connect(_refresh)
	pixel_editor.editor_closed.connect(_refresh)
	pixel_editor.popup_centered(Vector2i(1100,760))

func set_equipment(entry: Dictionary) -> void:
	equipment = entry
	%EditAppearance.visible=not entry.is_empty() and entry.get("slot") in ["weapon","armor","hat"]
	%SetPreview.visible = entry.has("set_id")
	%SetPreview.set_pressed_no_signal(false)
	visible = not entry.is_empty()
	if entry.is_empty():
		before_preview.display({})
		after_preview.display({})
		return
	var job := int(entry.get("job", -1))
	for index in 3: %Job.set_item_disabled(index, job >= 0 and index != job)
	if job >= 0: %Job.select(job)
	var gender := int(entry.get("gender", -1))
	for index in 2: %Gender.set_item_disabled(index, gender >= 0 and index != gender)
	if gender >= 0: %Gender.select(gender)
	_refresh()

func _refresh() -> void:
	if equipment.is_empty(): return
	var full_set: bool = %SetPreview.visible and %SetPreview.button_pressed
	%EditAppearance.visible=full_set or equipment.slot in ["weapon","armor","hat"]
	var mapping := MAPPING.variant(equipment, %Job.selected, %Gender.selected, full_set)
	if mapping.is_empty(): return
	%AfterCaption.text = "装备后 · 整套穿戴" if full_set else "装备后 · 仅当前装备"
	before_preview.display({"preview":{"kind":"actor", "art":mapping["装备前动画"]}})
	after_preview.display({"preview":{"kind":"actor", "art":mapping["装备后动画"]}})
	var action: String = ["idle", "walk", "attack"][%Action.selected]
	before_preview.play_animation(action)
	after_preview.play_animation(action)
	var slot: String = {"weapon":"武器", "armor":"衣服", "hat":"头饰"}.get(equipment.slot, "")
	if full_set:
		%Mapping.text = "%s · 武器、衣服、头饰整套对照" % equipment.set_name
	elif slot.is_empty():
		%Mapping.text = "该槽位只影响属性，人物外观保持不变。"
	else:
		var before: Array = mapping["装备前部件"][slot]
		var after: Array = mapping["装备后部件"][slot]
		%Mapping.text = "%s：%s → %s%s" % [slot, " / ".join(before) if not before.is_empty() else "空手", " / ".join(after), "（同部件）" if before == after else ""]
	%Mapping.tooltip_text = "%s\n%s → %s\n%s" % [MAPPING.changes(equipment), mapping["装备前动画"], mapping["装备后动画"], equipment.get("appearance_basis", "当前兼容装备重建映射")]
