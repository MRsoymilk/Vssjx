class_name OriginalCharacterSelection
extends Control
signal enter_requested(character_id: String)
signal create_requested
signal refresh_requested
signal back_requested
@export var online_mode := false
var characters: Array = []
var selected_index := 0
var preferred_id := ""
var locked := true
var can_create := false
var _entering := false
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
	$Options/Back.pressed.connect(func() -> void: back_requested.emit())
	_render()

func display_characters(values: Array) -> void:
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
	enter_button.disabled = locked or _entering or characters.is_empty()
	$Previous.disabled = locked or _entering or characters.size() < 2
	$Next.disabled = $Previous.disabled
	$Options/Create.disabled = locked or not can_create
	$Options/Refresh.disabled = locked or not online_mode
	for i in 3: get_node("Slot%d/Choose" % i).disabled = locked or _entering or selected_index + i - 1 < 0 or selected_index + i - 1 >= characters.size()

func select_index(offset: int) -> void:
	if locked or _entering or characters.is_empty(): return
	var index := selected_index + offset
	if index < 0 or index >= characters.size(): return
	selected_index = index
	_render()

func step(delta: int) -> void:
	if locked or _entering or characters.size() < 2: return
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
		var look: Array = character.get("appearance_v2",character.get("appearance",[1,0])) if online_mode else ShopRules.appearance(ShopRules.local_state(character))
		var actor := OriginalArt.actor(ShopRules.actor_key(int(character.get("job",0)),int(character.get("gender",0)),look))
		previews[i].sprite_frames = actor.sprite_frames
		previews[i].offset = actor.offset
		actor.free()
		previews[i].play("idle")
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

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var input_viewport := get_viewport()
	match event.keycode:
		KEY_LEFT: step(-1)
		KEY_RIGHT: step(1)
		KEY_ENTER: _enter()
		KEY_ESCAPE: back_requested.emit()
		_: return
	input_viewport.set_input_as_handled()
