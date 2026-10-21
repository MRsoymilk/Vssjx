class_name OriginalCharacterSelection
extends Control
signal enter_requested(character_id: String)
signal create_requested
signal refresh_requested
signal delete_requested(character_id: String, character_name: String)
signal back_requested
@export var online_mode := false
var characters: Array = []
var selected_index := 0
var preferred_id := ""
var locked := true
var can_create := false
var _entering := false
var _deleting := false
var _delete_target: Dictionary = {}
var previews: Array[AnimatedSprite2D] = []
@onready var enter_button: Button = $Enter
@onready var status: Label = $Status

func _ready() -> void:
	$GameMode.text = "联机模式" if online_mode else "本地模式"
	for i in 3:
		previews.append(get_node("Slot%d/Preview" % i))
		get_node("Slot%d/Choose" % i).pressed.connect(select_index.bind(i - 1))
	$Previous.pressed.connect(step.bind(-1))
	$Next.pressed.connect(step.bind(1))
	enter_button.pressed.connect(_enter)
	$Back.pressed.connect(func() -> void: back_requested.emit())
	$Menu.pressed.connect(func() -> void: $Options.visible = not $Options.visible)
	$Options/Create.pressed.connect(func() -> void: $Options.hide(); create_requested.emit())
	$Options/Refresh.pressed.connect(func() -> void: $Options.hide(); refresh_requested.emit())
	$Options/Delete.pressed.connect(_ask_delete)
	$DeleteConfirmation/Panel/Cancel.pressed.connect(_cancel_delete)
	$DeleteConfirmation/Panel/Confirm.pressed.connect(_confirm_delete)
	$Options/Back.pressed.connect(func() -> void: back_requested.emit())
	_render()

func display_characters(values: Array) -> void:
	if is_node_ready(): _cancel_delete()
	_deleting = false
	var selected := String(characters[selected_index].get("id", "")) if not characters.is_empty() else ""
	if not preferred_id.is_empty(): selected = preferred_id
	preferred_id = ""
	characters = values.duplicate(true)
	selected_index = clampi(selected_index, 0, maxi(0, characters.size() - 1))
	for i in characters.size():
		if String(characters[i].get("id", "")) == selected: selected_index = i
	_entering = false
	if is_node_ready(): _render()

func set_controls(is_locked: bool, allow_create: bool) -> void:
	locked = is_locked
	can_create = allow_create
	if not is_node_ready(): return
	var blocked := locked or _entering or _deleting or not _delete_target.is_empty()
	enter_button.disabled = blocked or characters.is_empty()
	$Previous.disabled = blocked or characters.size() < 2
	$Next.disabled = $Previous.disabled
	$Options/Create.disabled = blocked or not can_create
	$Options/Refresh.disabled = blocked or not online_mode
	$Options/Delete.disabled = blocked or characters.is_empty()
	$Back.disabled = _deleting
	$Menu.disabled = blocked
	$Options/Back.disabled = blocked
	$DeleteConfirmation/Panel/Confirm.disabled = locked or _delete_target.is_empty()
	for i in 3: get_node("Slot%d/Choose" % i).disabled = blocked or selected_index + i - 1 < 0 or selected_index + i - 1 >= characters.size()

func select_index(offset: int) -> void:
	if locked or _entering or _deleting or not _delete_target.is_empty() or characters.is_empty(): return
	var index := selected_index + offset
	if index < 0 or index >= characters.size(): return
	selected_index = index
	_render()

func step(delta: int) -> void:
	if locked or _entering or _deleting or not _delete_target.is_empty() or characters.size() < 2: return
	selected_index = posmod(selected_index + delta, characters.size())
	_render()

func _render() -> void:
	for i in 3:
		var index := selected_index + i - 1
		var present := index >= 0 and index < characters.size()
		previews[i].visible = present
		get_node("Slot%d/Empty" % i).visible = not present
		if not present: continue
		var character: Dictionary = characters[index]
		var keys := ["mzs", "mck", "mfs"] if int(character.get("gender", 0)) == 0 else ["wzs", "wck", "wfs"]
		var look: Array = character.get("appearance_v2",character.get("appearance",[1,0])) if online_mode else LootRules.look(character.get("loot_state",{}),ShopRules.appearance(ShopRules.local_state(character)))
		var actor := OriginalArt.actor(ShopRules.actor_key(int(character.get("job",0)),int(character.get("gender",0)),look))
		var previous:=previews[i];var parent:=previous.get_parent();var child_index:=previous.get_index()
		actor.name="Preview";actor.transform=previous.transform
		parent.remove_child(previous);previous.queue_free()
		parent.add_child(actor);parent.move_child(actor,child_index);previews[i]=actor
	for i in 5:
		get_node("Dot%d" % i).modulate = Color("ffe563") if i == selected_index and not characters.is_empty() else (Color("937c3c") if i < characters.size() else Color("58504a"))
	for key in ["Name", "Level", "Job", "Gender", "School", "Scene"]: get_node("Details/" + key).text = "—"
	if not characters.is_empty():
		var character: Dictionary = characters[selected_index]
		$Details/Name.text = String(character.get("display_name", character.get("name", "")))
		$Details/Level.text = str(int(character.get("level", 1)))
		$Details/Job.text = Game.JOBS[clampi(int(character.get("job", 0)), 0, 2)]
		$Details/Gender.text = "男" if int(character.get("gender", 0)) == 0 else "女"
		$Details/School.text = SchoolRules.label(int(character.get("school",SchoolRules.UNJOINED)))
		$Details/Scene.text = scene_name(character)
	set_controls(locked, can_create)

static func scene_name(character: Dictionary) -> String:
	if character.has("zone"): return "青云山道" if int(character.zone) == 0 else "古剑遗迹"
	return {"qingyun_trail":"青云山道", "ancient_ruins":"古剑遗迹"}.get(String(character.get("map_id", "")), "未知场景")

func _enter() -> void:
	if enter_button.disabled or _entering or characters.is_empty(): return
	_entering = true
	set_controls(locked, can_create)
	enter_requested.emit(String(characters[selected_index].get("id", "local")))

func _ask_delete() -> void:
	if $Options/Delete.disabled: return
	var character: Dictionary = characters[selected_index]
	_delete_target = {"id": String(character.id), "name": String(character.get("display_name", character.get("name", "")))}
	$Options.hide()
	$DeleteConfirmation/Panel/Description.text = "删除 %s（%d级）？\n角色的进度和道具将无法恢复。" % [_delete_target.name, int(character.get("level", 1))]
	$DeleteConfirmation.show()
	set_controls(locked, can_create)

func _cancel_delete() -> void:
	_delete_target = {}
	$DeleteConfirmation.hide()
	set_controls(locked, can_create)

func _confirm_delete() -> void:
	if locked or _deleting or $DeleteConfirmation/Panel/Confirm.disabled or _delete_target.is_empty(): return
	var target := _delete_target.duplicate()
	_deleting = true
	_cancel_delete()
	delete_requested.emit(target.id, target.name)

func finish_delete() -> void:
	_deleting = false
	set_controls(locked, can_create)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if _deleting: get_viewport().set_input_as_handled(); return
	if not _delete_target.is_empty():
		if event.keycode == KEY_ESCAPE: _cancel_delete()
		get_viewport().set_input_as_handled()
		return
	var input_viewport := get_viewport()
	match event.keycode:
		KEY_LEFT: step(-1)
		KEY_RIGHT: step(1)
		KEY_ENTER: _enter()
		KEY_ESCAPE: back_requested.emit()
		_: return
	input_viewport.set_input_as_handled()
