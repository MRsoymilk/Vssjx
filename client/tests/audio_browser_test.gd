extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func _ready()->void:_run.call_deferred()
func _run()->void:
	var before:=Game.player.duplicate(true)
	var browser=load("res://scenes/admin/data_browser.tscn").instantiate();add_child(browser)
	browser.select_category("audio")
	var audio=browser.get_node("%AudioPreview")
	check(browser.visible_entries.size()==1 and browser.current.id=="thunder","Audio category exposes the shared thunder resource")
	check(audio.visible and not browser.get_node("%Preview").visible,"Audio uses an authored preview instead of an empty image")
	check(browser.current.data["采样率"]==48000 and browser.current.data["声道"]=="双声道" and browser.current.data["WAV编码"]=="16位PCM","Audio metadata comes from the imported stream")
	check(browser.current.data.skill_id=="sheet_010" and browser.current.data.trigger=="cast_impact","Skill binding is visible in resource details")
	check(not audio.get_node("Player").playing,"Selecting an audio resource does not autoplay")
	audio.get_node("Controls/Play").pressed.emit()
	check(audio.get_node("Player").playing,"Audition starts the selected WAV")
	audio.get_node("Timeline").value=0.5
	check(audio.get_node("Player").get_playback_position()>=0.49,"Timeline seeks the active audition")
	audio.get_node("Volume/Slider").value=-12
	check(audio.get_node("Player").volume_db==-12,"Preview volume changes the audition only")
	audio.get_node("Controls/Stop").pressed.emit()
	check(not audio.get_node("Player").playing and audio.get_node("Timeline").value==0,"Stop resets playback and progress")
	browser.get_node("%Search").text="雷霆"
	browser._fill_list()
	check(browser.visible_entries.size()==1,"Audio names participate in the normal search")
	audio.get_node("Controls/Play").pressed.emit()
	browser.get_node("%Search").text="missing-audio"
	browser._fill_list()
	check(browser.visible_entries.is_empty() and not audio.visible and not audio.get_node("Player").playing,"Empty search stops old audio and clears its preview")
	browser.select_category("audio")
	audio.get_node("Controls/Play").pressed.emit()
	browser.select_category("weapons")
	check(not audio.visible and not audio.get_node("Player").playing,"Changing categories stops audition")
	browser.select_category("audio")
	audio.get_node("Controls/Play").pressed.emit()
	await get_tree().create_timer(2.2).timeout
	for frame in 4:await get_tree().process_frame
	check(not audio.get_node("Player").playing and audio.get_node("Timeline").value==0,"Finished WAV resets instead of looping")
	var output:=OS.get_environment("SSJX_AUDIO_BROWSER_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 4:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output)==OK,"Actual admin UI capture saved")
		check(get_viewport().get_visible_rect().encloses(audio.get_global_rect()),"Audio controls fit the admin window")
	check(Game.player==before,"Resource management never changes the character")
	browser.queue_free();await get_tree().process_frame
	print("AUDIO BROWSER: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
