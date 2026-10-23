class_name GatheringPanel
extends Control
signal start_requested
signal cancel_requested
const Chrome=preload("res://scripts/social_chrome.gd")
var node:Dictionary={}
var frame:Panel
var description:Label
var progress:ProgressBar
var confirm:Button
var back:Button
var local_mode:=false
var auto_finished:=false
func _ready()->void:
	mouse_filter=MOUSE_FILTER_IGNORE;z_index=18
	frame=Chrome.frame(self,Rect2(28,155,264,175),"采矿／采药")
	description=OriginalSceneChrome.label(frame,"",Rect2(14,39,236,60),12,Chrome.INK);description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	progress=OriginalSceneChrome.progress(frame,Rect2(14,106,236,12),Color("40b5a0"));progress.max_value=1
	confirm=Chrome.placed_button(frame,"开始采集",Rect2(14,132,110,30));confirm.pressed.connect(func()->void:start_requested.emit())
	back=Chrome.placed_button(frame,"返回",Rect2(140,132,110,30));back.pressed.connect(func()->void:cancel_requested.emit())
	hide()
func present(value:Dictionary)->void:node=value.duplicate(true);progress.value=0;auto_finished=false;show()
func display(model:OnlinePve)->void:
	if node.is_empty():return
	var active:=GatheringRules.active(model)
	var pending:=model.pending()
	var now:=model.server_time_ms()
	var name:String=GatheringRules.MATERIALS.get(node.material,"材料")
	if not active.is_empty() and active.node_id==node.id:
		var left:=maxi(0,int(active.ready_at_ms)-now)
		progress.value=clampf(1.0-float(left)/float(active.duration_ms),0,1)
		description.text="%s · 正在%s\n剩余 %.1f 秒；移动、战斗或断线中断。\n完成后材料自动进入材料袋。"%[name,"采矿" if GatheringRules.kind(node.material)=="ore" else "采药",left/1000.0]
		confirm.text="领取材料" if left==0 else "采集中";confirm.disabled=left>0 or pending;back.text="取消采集"
	else:
		var cooldown:=maxi(0,ceili((int(node.get("available_at_ms",0))-now)/1000.0))
		description.text="%s · 每次 %d～%d 份\n采集 %.1f 秒，个人刷新 %d 秒。\n%s"%[name,int(node.min_quantity),int(node.max_quantity),int(node.duration_ms)/1000.0,int(node.respawn_ms)/1000,"剩余刷新 %d 秒"%cooldown if cooldown>0 else "点击“开始采集”确认；其他玩家不占用你的资源。"]
		confirm.text="开始采集";confirm.disabled=pending or cooldown>0;back.text="返回"

func _process(_delta:float)->void:
	if not local_mode or not visible or node.is_empty():return
	var active:Dictionary=Game.local_gather
	if active.is_empty():
		var remaining:=maxi(0,ceili((int(Game.player.get("gathering",{}).get("respawns",{}).get(node.id,0))-Time.get_unix_time_from_system()*1000)/1000.0))
		description.text="%s · 每次%d～%d份\n采集%.1f秒，个人刷新%d秒。\n%s"%[GatheringRules.MATERIALS[node.material],int(node.min_quantity),int(node.max_quantity),int(node.duration_ms)/1000.0,int(node.respawn_ms)/1000,"剩余刷新%d秒"%remaining if remaining>0 else "确认后开始；材料与刷新时间随本地存档保存。"]
		confirm.text="开始采集";confirm.disabled=Game.storage_busy or remaining>0
	else:
		var left:=maxi(0,int(node.duration_ms)-(Time.get_ticks_msec()-int(active.started)))
		progress.value=1.0-float(left)/int(node.duration_ms)
		description.text="正在采集%s\n剩余%.1f秒\n完成并保存成功后，材料进入材料袋。"%[GatheringRules.MATERIALS[node.material],left/1000.0]
		confirm.text="采集中" if left>0 else "领取材料";confirm.disabled=left>0 or Game.storage_busy
		if left==0 and not auto_finished and not Game.storage_busy:auto_finished=true;start_requested.emit()
	if not Game.storage_busy and (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D)):cancel_requested.emit()
func _unhandled_key_input(event:InputEvent)->void:
	if local_mode and visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel_requested.emit();get_viewport().set_input_as_handled()
