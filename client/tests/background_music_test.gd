extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Platform.when_ready();await Game.when_ready()
	var lifecycle:PlatformLifecycleInterface=Platform.context.lifecycle
	var focused:=lifecycle.focused;var suspended:=lifecycle.suspended
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path
	Game.save_path="user://background_music_%d.json"%OS.get_process_id()
	Game.new_player("背景音乐验证",1,3)
	var source:=GameAudio.stream("background") as AudioStreamOggVorbis
	check(source!=null and source.get_length()>1 and not source.loop,"Shared OGG is imported with finite audition playback")
	check(FileAccess.get_sha256(GameAudio.item("background").path)=="ad7a04dca194d467b7f135b019b7e2b381b1e8cd2d21f38448df5bb2d145b211","Provided OGG is preserved byte for byte")
	print("BACKGROUND DURATION: %.3f seconds"%source.get_length())
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app)
	for i in 2:await get_tree().process_frame
	lifecycle.focused=true;lifecycle.suspended=false;lifecycle.changed.emit("focus_gained")
	var music:AudioStreamPlayer=app.get_node("BackgroundMusic")
	var identity:=music.get_instance_id()
	check(music.playing and music.max_polyphony==1 and music.volume_db==-18,"Actual game root starts one quiet background player")
	check(music.stream is AudioStreamOggVorbis and music.stream.loop and music.stream!=source and not source.loop,"Runtime loop does not mutate the shared audition resource")
	music.seek(3);music.begin()
	check(music.get_playback_position()>=2.9,"Repeated begin does not restart music")
	app._enter_world()
	check(app.get_node("BackgroundMusic").get_instance_id()==identity and music.playing and music.get_playback_position()>=2.9,"Entering local map preserves player and position")
	var wolf:Dictionary=SharedWorldMap.population("qingyun_trail").filter(func(d:Dictionary)->bool:return d.id=="wolf_a")[0]
	app._start_local_encounter([wolf])
	check(app.get_node("BackgroundMusic").get_instance_id()==identity and music.playing,"Battle UI changes keep the same background track")
	app._home()
	check(music.playing and app.find_children("BackgroundMusic","AudioStreamPlayer",true,false).size()==1,"Returning to login does not add another music player")
	lifecycle.focused=false;lifecycle.changed.emit("focus_lost")
	check(music.stream_paused,"Switching away pauses background music")
	lifecycle.focused=true;lifecycle.suspended=true;lifecycle.changed.emit("suspended")
	check(music.stream_paused,"Suspension remains paused even with focus")
	lifecycle.suspended=false;lifecycle.changed.emit("resumed")
	check(not music.stream_paused and music.get_playback_position()>=2.9,"Resume keeps the same playback position")
	music.seek(source.get_length()-0.12)
	await get_tree().create_timer(0.5).timeout
	check(music.playing and music.get_playback_position()<1,"End of OGG loops into the next playback")
	var reference:WeakRef=weakref(music)
	app.queue_free();await get_tree().process_frame
	check(reference.get_ref()==null,"Leaving game frees the root music player")
	# Use the same deferred-start branch as the Web build without changing platform globals.
	var web_music:AudioStreamPlayer=load("res://scenes/background_music.tscn").instantiate();add_child(web_music);web_music.begin(true)
	check(not web_music.playing and web_music.waiting_for_gesture,"Web startup waits for a real input gesture")
	web_music._input(InputEventMouseMotion.new())
	var key:=InputEventKey.new();key.pressed=true;key.echo=true;web_music._input(key)
	check(not web_music.playing,"Pointer motion and key repeats cannot trigger autoplay")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;web_music._input(click)
	check(web_music.playing and not web_music.waiting_for_gesture,"First click starts Web background playback")
	web_music.seek(4);web_music._input(click)
	check(web_music.get_playback_position()>=3.9,"Later UI clicks never restart the track")
	web_music.queue_free();await get_tree().process_frame
	lifecycle.focused=false
	var deferred:AudioStreamPlayer=load("res://scenes/background_music.tscn").instantiate();add_child(deferred);deferred.begin(false)
	check(not deferred.started and not deferred.playing,"Unfocused startup waits instead of losing a pending playback")
	lifecycle.focused=true;lifecycle.changed.emit("focus_gained")
	check(deferred.started and deferred.playing,"Returning focus starts music that has never played")
	deferred.queue_free();await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout # Let the audio mixer release stopped OGG playback.
	lifecycle.focused=focused;lifecycle.suspended=suspended;lifecycle.changed.emit("resumed")
	Game.player=old;Game.save_path=old_path
	print("BACKGROUND MUSIC: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
