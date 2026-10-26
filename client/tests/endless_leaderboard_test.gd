extends Node
const SELF:="10000000-0000-4000-8000-000000000001"
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func fixture()->Dictionary:
	return {"version":"endless-board-v1","character_id":SELF,"total":2,"self":{"rank":2,"best":100},"entries":[
		{"rank":1,"character_id":"10000000-0000-4000-8000-000000000002","display_name":"登峰修士","job":2,"level":60,"best":120},
		{"rank":2,"character_id":SELF,"display_name":"榜单验证","job":0,"level":30,"best":100}]}
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://endless_board_%d.json"%OS.get_process_id();Game.new_player("榜单验证",0,3)
	Game.player.endless_state={"stage":1,"best":100,"level":0,"in_progress":false}
	var dialog:OriginalNpcDialog=load("res://scenes/ui/npc_dialog.tscn").instantiate();add_child(dialog)
	dialog.present_local(EndlessRules.rules.npc)
	check(dialog.restore_button.visible and dialog.restore_button.text.contains("排行榜"),"Actual guardian dialogue exposes ranking")
	check(dialog.restore_button.get_rect().end.y<=dialog.hint.position.y,"Rank button does not overlap hint")
	dialog.restore_button.pressed.emit()
	var board:EndlessLeaderboard=dialog.get_node("EndlessLeaderboard")
	check(board.local_mode and board.entries.size()==1 and board.entries[0].best==100,"Local rank reads saved best without online requests")
	check(board.status.text.contains("第1名") and board.status.text.contains("100层"),"Local player sees their own rank and best")
	board.queue_free();await get_tree().process_frame
	board=EndlessLeaderboard.new();dialog.add_child(board);board.character_id=SELF;board.local_mode=false
	var good:=fixture();check(EndlessLeaderboard.valid(good,SELF),"Strict online ranking fixture is accepted")
	board.waiting=true;board._completed("endless_board",{"ok":true,"leaderboard":good})
	check(board.rows.get_child_count()==2 and board.status.text.contains("第2名"),"Actual online ranking renders ordered rows and personal rank")
	var bad:=good.duplicate(true);bad.entries[0].best=90;check(not EndlessLeaderboard.valid(bad,SELF),"Unsorted ranks are rejected")
	bad=good.duplicate(true);bad.entries[1].character_id=bad.entries[0].character_id;check(not EndlessLeaderboard.valid(bad,SELF),"Duplicate identities are rejected")
	bad=good.duplicate(true);bad.self.rank=1;check(not EndlessLeaderboard.valid(bad,SELF),"Personal rank must match the corresponding row")
	bad=good.duplicate(true);bad.entries[0].display_name="[url]伪造";check(not EndlessLeaderboard.valid(bad,SELF),"Malformed names are rejected")
	bad=good.duplicate(true);bad.entries[0].display_name={"invalid":true};check(not EndlessLeaderboard.valid(bad,SELF),"Non-string names cannot crash the response validator")
	bad=good.duplicate(true);bad.character_id="10000000-0000-4000-8000-000000000099";check(not EndlessLeaderboard.valid(bad,SELF),"Replies for another character are rejected")
	var output:=OS.get_environment("SSJX_ENDLESS_BOARD_FIXTURE")
	if not output.is_empty():
		var real:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output));board.character_id=real.character_id
		check(EndlessLeaderboard.valid(real,real.character_id),"Real server leaderboard validates in Godot")
		board.waiting=true;board._completed("endless_board",{"ok":true,"leaderboard":real})
		check(board.entries.size()==mini(100,int(real.total)),"All hundred top rows render in the scroll list")
	var capture:=OS.get_environment("SSJX_ENDLESS_BOARD_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 4:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(capture)==OK,"Capture actual ranking UI")
	dialog.queue_free();Game.player=old;Game.save_path=path
	print("ENDLESS LEADERBOARD: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
