extends AudioStreamPlayer
## One player owned by the game root, outside rebuilt UI and battle effect nodes.
var armed:=false
var waiting_for_gesture:=false
var started:=false

func begin(require_gesture:bool=OS.has_feature("web"))->void:
	if armed:return
	var original:=GameAudio.stream("background") as AudioStreamOggVorbis
	if original==null:return
	# Cached registry resources remain non-looping for finite admin auditions.
	var music:=original.duplicate() as AudioStreamOggVorbis
	music.loop=true;stream=music;volume_db=float(GameAudio.item("background").volume_db)
	armed=true;waiting_for_gesture=require_gesture
	Platform.context.lifecycle.changed.connect(_lifecycle_changed)
	_apply_lifecycle()

func _input(event:InputEvent)->void:
	if not armed or not waiting_for_gesture:return
	if event is InputEventKey and event.echo:return
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		waiting_for_gesture=false;_apply_lifecycle()

func _lifecycle_changed(_event:String)->void:_apply_lifecycle()
func _apply_lifecycle()->void:
	if not armed or waiting_for_gesture:return
	var inactive:=not Platform.context.lifecycle.focused or Platform.context.lifecycle.suspended
	if inactive:
		if started:stream_paused=true
		return
	stream_paused=false
	if not started:started=true;play()

func _exit_tree()->void:stop()
