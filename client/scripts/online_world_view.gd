class_name OnlineWorldView
extends Control
## Shared game interface backed by online state; never installs Game.player.
signal close_requested
signal resident_selected(id: String)
var character_id := ""
@onready var network: OnlineWorldClient = $Network
@onready var viewport: SubViewport = $Viewport
@onready var scene: Node2D = $Viewport/Scene
@onready var actor_layer: Node2D = $Viewport/Scene/Actors
@onready var camera: Camera2D = $Viewport/Scene/Camera
@onready var image: TextureRect = $Image
@onready var screen: GameWorldScreen = $Screen
@onready var status: Label = $Screen/Chrome/MessagePanel/LogLabel
@onready var count_label: Label = $Screen/CountLabel
var actors: Dictionary = {}
var residents: Dictionary = {}
var map_data: Dictionary
var portal_marker: Node2D
var shop: ShopPanel
var backpack: OriginalInventory
var bag_overlay: Control
var ai_panel: AIWorldPanel
var ai_station: Node2D
var _portal_latch := ""
var _portal_stop := ""
var _follow_trip := ""
var _motion_grid := AStarGrid2D.new()
var _key_timer := 0.0
var _was_keyboard := false
@onready var chat_panel: Panel = $Screen/Chat
@onready var chat_log: RichTextLabel = $Screen/Chat/ChatLog
@onready var chat_input: LineEdit = $Screen/Chat/ChatInput
@onready var chat_send: Button = $Screen/Chat/ChatSend
@onready var chat_status: Label = $Screen/Chrome/Hint
@onready var chat_button: Button = $Screen/Chrome/Toolbar/Social
@onready var emote_button: Button = $Screen/Chat/ChatEmotes
@onready var emote_picker: ChatEmotePicker = $Screen/Chat/EmotePicker
@onready var expanded_chat: ExpandedChatPanel = $Screen/ExpandedChat
@onready var menu: OriginalGameMenu = $GameMenu
@onready var details: Control = $Menu
@onready var attributes: OriginalCharacterAttributes = $Attributes
@onready var world_map: OriginalWorldMap = $WorldMap
@onready var move_target: WorldMoveTarget = $Viewport/Scene/MoveTarget
var _target_wait := 0.0
var _target_seen_motion := false
var _character: Dictionary = {}
var _system_text := "正在连接共享地图……"
var _rendered_chat := ""
@onready var encounter: OnlineEncounter = $Encounter
@onready var npc_dialog: OriginalNpcDialog = $NpcDialog
@onready var battle_view: OnlineBattleView = $Battle
var _approach: Dictionary = {}
var _pve_log := ""
var _closed_battle := ""
var _loading_battle := ""
var _battle_load_epoch := 0
var _battle_resource_request: PlatformResourceRequest
var _battle_load_failed := false
var _team_loading:=""
var _team_load_epoch:=0
var _team_resource_request:PlatformResourceRequest
var _restored_loot:=""
var _hidden_residents: Array = []
@onready var map_transition: OriginalMapTransition = $MapTransition
var _transfer_origin := ""
@onready var duel_battle: DuelBattleView = $DuelBattle
var duel_invitation: DuelInvitation
var _closed_duel := ""
var _duel_lines := ""
var social: RefCounted = preload("res://scripts/network/online_social.gd").new()
var social_panel: Control
var target:=OnlineTarget.new()
var target_view:PlayerTarget
var gathering_nodes:Dictionary={}
var gathering_panel:GatheringPanel
var _gather_cancel_requested:=false
var _gather_auto_token:=""
var _social_incoming: Array = []
var team:RefCounted=preload("res://scripts/network/online_team.gd").new()
var team_panel:Control
var solo_model:=SoloEncounter.new()
var solo_battle:Control
var help_panel:ControlHelp
var economy_panel:EconomyPanel
var _last_trade_invite:=""
var team_battle:Control
var team_notice:Panel
var team_notice_text:Label
var team_confirm:Button
var team_reject:Button
const SocialChrome = preload("res://scripts/social_chrome.gd")
var soul_markers: SoulMarkers
@onready var soul_overlay: CanvasLayer = $SoulOverlay
var _soul_transition_id := ""
var _soul_snap_pending := false
var day_night: WorldDayNight
var target_list: WorldTargetList
var _display_mode := ""

func _ready() -> void:
	WorldDisplaySettings.initialize()
	solo_model.attach(network.pve)
	solo_battle=preload("res://scenes/ui/team_battle_view.tscn").instantiate();solo_battle.model=solo_model;add_child(solo_battle)
	solo_battle.dismissed.connect(func()->void:
		if network.pve.state.get("battle") is Dictionary:_closed_battle=network.pve.state.battle.id
		screen.hud.show();count_label.show();screen.chrome.round_label.text="常规模式";_set_battle_layout(false)
	)
	team.bind_character(character_id)
	team.prepare_battles=true
	team.send_requested.connect(OnlineAccount.team_request)
	team_panel=preload("res://scenes/ui/team_panel.tscn").instantiate();team_panel.model=team;add_child(team_panel)
	team_panel.profile_requested.connect(func(id:String)->void:team_panel.dismiss();_open_social("profile",id))
	team_battle=preload("res://scenes/ui/team_battle_view.tscn").instantiate();team_battle.model=team;add_child(team_battle)
	team_battle.dismissed.connect(func()->void:screen.hud.show();count_label.show();_set_battle_layout(false);team.refresh())
	team_notice=SocialChrome.frame(self,Rect2(4,218,218,112),"组队邀请");team_notice.z_index=26
	team_notice_text=OriginalSceneChrome.label(team_notice,"",Rect2(14,36,190,32),12,SocialChrome.INK)
	team_notice_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	team_confirm=SocialChrome.placed_button(team_notice,"同意",Rect2(14,74,84,30))
	team_reject=SocialChrome.placed_button(team_notice,"拒绝",Rect2(120,74,84,30))
	team_confirm.pressed.connect(func()->void:if not team.state.incoming.is_empty():team.submit("accept",team.state.incoming[0].id))
	team_reject.pressed.connect(func()->void:if not team.state.incoming.is_empty():team.submit("reject",team.state.incoming[0].id))
	team_notice.hide()
	team.changed.connect(_team_changed)
	team.message.connect(func(text:String)->void:chat_status.text=text)
	social.bind_character(character_id)
	social.send_requested.connect(OnlineAccount.social_request)
	OnlineAccount.completed.connect(_social_completed)
	social_panel=preload("res://scenes/ui/social_panel.tscn").instantiate()
	social_panel.model=social
	add_child(social_panel)
	social_panel.duel_requested.connect(_invite_player)
	social_panel.team_requested.connect(func(id:String)->void:
		if not team.submit("invite",id):chat_status.text="正在同步队伍，请稍后再邀请。"
	)
	social.changed.connect(_social_changed)
	target.character_id=character_id
	target.send_requested.connect(OnlineAccount.target_profile_request)
	target_view=preload("res://scenes/ui/player_target.tscn").instantiate();add_child(target_view)
	target_view.action_requested.connect(_target_action)
	target_view.actions_opened.connect(func()->void:
		_cancel_approach();network.stop_moving();move_target.clear();_was_keyboard=false
	)
	target.changed.connect(_refresh_target)
	gathering_panel=GatheringPanel.new();add_child(gathering_panel)
	gathering_panel.hero_point=_hero_screen_point
	gathering_panel.start_requested.connect(_gather_confirm)
	gathering_panel.cancel_requested.connect(_cancel_gathering)
	duel_invitation = DuelInvitation.new()
	duel_invitation.channel = network.duel
	add_child(duel_invitation)
	duel_invitation.invite_requested.connect(_invite_player)
	duel_invitation.reply_requested.connect(func(action: String)->void:
		if action == "accept" and (network.pve.pending() or network.pve.active() or map_transition.blocking): return
		network.duel.submit(action)
	)
	network.duel.changed.connect(_duel_changed)
	network.duel.message.connect(func(text: String)->void:
		_system_text = text;_pve_log = text;expanded_chat.add_system(text);_chat_changed()
	)
	duel_battle.action_requested.connect(func(action: String)->void: network.duel.submit(action))
	duel_battle.skill_requested.connect(func(id: String)->void: network.duel.submit("skill",id))
	duel_battle.dismissed.connect(func()->void:
		_closed_duel = duel_battle.battle_id
		screen.hud.show();count_label.show();_set_battle_layout(false)
		if not _character.is_empty(): screen.chrome.display_character(_character)
	)
	if OS.has_feature("web"): Platform.context.lifecycle.changed.connect(_web_lifecycle)
	map_data = SharedWorldMap.load_data()
	_build_map()
	image.texture = viewport.get_texture()
	preload("res://scripts/world_nameplate_layer.gd").attach(image,viewport)
	image.gui_input.connect(_map_input)
	for character in OnlineAccount.characters:
		if character.id == character_id: _character = character.duplicate(true)
	if not _character.is_empty(): screen.chrome.display_character(_character)
	screen.action_requested.connect(_scene_action)
	screen.hud.get_node("MapName").text = "青云山道"
	screen.hud.get_node("Minimap").set_shared_world(map_data, {}, character_id)
	screen.hud.get_node("Minimap").map_requested.connect(_scene_action.bind("map"))
	menu.chosen.connect(func(action: String)->void:_scene_action("friends" if action=="social" else action))
	attributes.back_requested.connect(_close_attributes)
	world_map.back_requested.connect(_close_world_map)
	world_map.travel_requested.connect(_scroll_travel)
	attributes.allocation_requested.connect(_allocate_attributes)
	attributes.respec_requested.connect(func()->void:
		if attributes.allocation_enabled:network.pve.submit("respec")
	)
	$Menu/Panel/Continue.pressed.connect(func() -> void: details.hide())
	$Menu/Panel/Leave.pressed.connect(_leave_world)
	$Menu/Panel/Chat.pressed.connect(_focus_chat)
	screen.chat_expand_requested.connect(_open_expanded_chat)
	expanded_chat.dismissed.connect(_expanded_chat_dismissed)
	expanded_chat.emote_chosen.connect(_insert_emote)
	expanded_chat.focus_requested.connect(func() -> void: Platform.context.text_input.request_focus(chat_input))
	expanded_chat.add_system(_system_text)
	chat_send.pressed.connect(_send_chat)
	emote_button.pressed.connect(_toggle_emotes)
	emote_picker.chosen.connect(_insert_emote)
	emote_picker.dismissed.connect(func() -> void: Platform.context.text_input.request_focus(chat_input))
	chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat())
	chat_input.focus_entered.connect(func() -> void:
		if network.world_ready: network.stop_moving()
		_was_keyboard = false
		_cancel_approach()
	)
	chat_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if expanded_chat.visible and expanded_chat.picker.visible: expanded_chat.close_emotes()
			elif emote_picker.visible: emote_picker.hide()
			elif expanded_chat.visible: expanded_chat.dismiss()
			else: Platform.context.text_input.release_focus(chat_input)
			chat_input.accept_event()
	)
	resident_selected.connect(_select_resident)
	npc_dialog.action_requested.connect(_npc_action_chosen)
	npc_dialog.dismissed.connect(_cancel_approach)
	battle_view.settings_requested.connect(func() -> void: _scene_action("system"))
	battle_view.action_requested.connect(func(action: String) -> void: network.pve.submit(action))
	battle_view.skill_requested.connect(func(id:String)->void:network.pve.submit("skill",id))
	battle_view.dismissed.connect(func() -> void:
		_closed_battle = battle_view.battle_id
		screen.hud.show()
		count_label.show()
		screen.chrome.round_label.text = "常规模式"
		_set_battle_layout(false)
	)
	network.pve.changed.connect(_pve_changed)
	network.pve.changed.connect(_gathering_changed)
	network.pve.message.connect(func(text: String) -> void:
		if network.pve.last_action in ["transfer", "ai_travel", "school_join", "scroll_travel"] and not network.pve.last_code.is_empty(): map_transition.cancel()
		_pve_log = text
		_system_text = text
		expanded_chat.add_system(text)
		_chat_changed()
		if _loading_battle.is_empty(): encounter.hide()
		if network.pve.last_code.is_empty() and network.pve.last_action in ["accept", "claim", "restore","ai_accept","ai_claim","ai_restore","ai_interact","school_join"]: npc_dialog.hide()
	)
	network.map_changed.connect(_map_changed)
	network.map_rules.changed.connect(func()->void:
		if network.map_rules.map_id==String(map_data.map_id):
			_build_portals()
			_refresh_npc_finder()
	)
	network.map_transfer_started.connect(_begin_map_transition)
	network.connection_failed.connect(map_transition.cancel)
	network.pve.send_requested.connect(_map_command_sent)
	network.changed.connect(_snapshot)
	network.population.changed.connect(_population)
	network.status_changed.connect(_status_changed)
	network.movement_cancelled.connect(move_target.clear)
	network.chat.changed.connect(_chat_changed)
	network.chat.status_changed.connect(func(text_value: String) -> void:
		chat_status.text = text_value
		expanded_chat.set_status(text_value)
	)
	network.chat.confirmed.connect(func() -> void: chat_input.clear())
	chat_status.text = "公共频道 · 最多120字"
	network.start(character_id)

func _leave_world() -> void:
	if social_panel.visible:social_panel.dismiss()
	_close_inventory()
	_cancel_battle_preparation()
	network.leave()
	close_requested.emit()

func _scene_action(action: String) -> void:
	if map_transition.blocking: return
	if network.duel.active() or duel_battle.visible or team.active() or team_battle.visible: return
	_close_target_list()
	$Menu/Panel/SoundSettings.hide()
	$Menu/Panel/CrowdSettings.hide()
	if gathering_panel.visible:_cancel_gathering()
	_close_help()
	_close_economy()
	if team_panel.visible:team_panel.dismiss()
	if social_panel.visible: social_panel.dismiss()
	_close_inventory()
	_close_world_map()
	_close_attributes()
	if expanded_chat.visible: expanded_chat.dismiss()
	_cancel_approach()
	npc_dialog.hide()
	if _loading_battle.is_empty() and not network.pve.pending(): encounter.hide()
	if action == "menu":
		details.hide()
		emote_picker.hide()
		Platform.context.text_input.release_focus(chat_input)
		if network.world_ready: network.stop_moving()
		_was_keyboard = false
		if menu.visible: menu.dismiss()
		else: menu.open()
		return
	menu.hide()
	if action=="help":
		details.hide();emote_picker.hide();Platform.context.text_input.release_focus(chat_input)
		if network.world_ready:network.stop_moving()
		_was_keyboard=false
		help_panel=preload("res://scenes/ui/control_help.tscn").instantiate();help_panel.online_mode=true;add_child(help_panel)
		help_panel.dismissed.connect(_close_help)
		return
	if action == "find":
		_open_npc_finder()
		return
	if action == "social":
		_toggle_chat()
		return
	if action in ["friends","guild"]:
		_open_social("friends" if action=="friends" else "guild")
		return
	if action=="team":
		_open_team();return
	if network.world_ready: network.stop_moving()
	emote_picker.hide()
	Platform.context.text_input.release_focus(chat_input)
	_was_keyboard = false
	if action == "properties":
		_open_attributes()
		return
	if action == "map":
		_open_world_map()
		return
	if action == "quest" and (not AIWorld.map_data(String(map_data.map_id)).is_empty() or not network.pve.state.get("ai_world",{}).get("active",{}).is_empty()):
		_open_ai("quests")
		return
	if action == "shop":
		_open_shop()
		return
	if action == "bag":
		_open_inventory()
		return
	if action=="craft":
		if team.active() or network.duel.active():chat_status.text=OnlinePve.error_text("BATTLE_ACTIVE");return
		_open_inventory()
		if backpack!=null:backpack.open_loot();backpack.loot_panel.status.text="选择一件装备，再点“养成”。"
		return
	if action=="trade":
		if network.pve.active() or team.active() or network.duel.active():chat_status.text=OnlinePve.error_text("BATTLE_ACTIVE");return
		if is_instance_valid(economy_panel):return
		economy_panel=EconomyPanel.new();economy_panel.online_model=network.pve
		if network.pve.state.get("economy",{}).get("incoming_trade")!=null:economy_panel.section="direct"
		add_child(economy_panel);economy_panel.dismissed.connect(_close_economy);return
	var titles := {"system": "系统", "properties": "人物属性", "quest": "任务", "bag": "背包", "map": "地图", "mail": "邮件", "reward": "奖励", "shop": "商城", "craft": "炼制", "team": "队伍", "guild": "帮会", "trade": "交易"}
	$Menu/Panel/Title.text = titles.get(action, "提示")
	var body := "同图%d人 · 点击地图移动 / WASD\n公共消息在底部直接发送。\n线上进度由服务器保存。" % actors.size()
	$Menu/Panel/SoundSettings.visible = action == "system"
	$Menu/Panel/CrowdSettings.visible = action == "system"
	if action == "system": body = "线上进度由服务器自动保存。\n声音设置仅影响当前设备。"
	elif action == "quest": body = network.pve.quest_text()
	elif action == "bag" and not network.pve.state.is_empty(): body = "回春散 ×%d\n战斗中可恢复45点生命。\n铜钱：%d" % [int(network.pve.state.potions), int(_character.get("gold", 0))]
	elif action in ["bag", "reward", "shop", "craft", "team", "guild", "trade"]: body = "线上%s尚未开放。\n可在当前地图移动，与同图玩家聊天。" % titles[action]
	elif action == "mail": body = "暂无邮件。"
	$Menu/Panel/Body.text = body
	details.show()

func _close_help()->void:
	if is_instance_valid(help_panel):remove_child(help_panel);help_panel.queue_free()
	help_panel=null
func _close_economy()->void:
	if is_instance_valid(economy_panel):economy_panel.queue_free()
	economy_panel=null

func _status_changed(text_value: String) -> void:
	status.text = text_value
	_system_text = text_value
	expanded_chat.add_system(text_value)
	if not network.world_ready:
		_close_target_list()
		_cancel_approach()
		target.clear()
		move_target.clear()
		for actor in actors.values():
			if actor.root.visible: actor.sprite.play("idle")
			else: actor.sprite.pause()
	_chat_changed()

func _map_command_sent(packet: Dictionary) -> void:
	if packet.get("command", {}).get("action") in ["transfer", "ai_travel", "school_join", "scroll_travel"]:
		_begin_map_transition()

func _select_player(id: String) -> void:
	if id == character_id or not network.entities.has(id) or not network.world_ready or network.pve.active() or network.pve.pending() or team.active() or network.duel.active() or map_transition.blocking:return
	if not actors.has(id) or not actors[id].root.visible: return
	_cancel_approach();target.select(id);target_view.close_actions();_refresh_target()

func _refresh_target()->void:
	if not is_instance_valid(target_view):return
	if target.selected.is_empty():target_view.display("",{},{});return
	if not network.world_ready or not network.entities.has(target.selected) or map_transition.blocking or network.pve.active() or team.active() or network.duel.active():
		target.clear();return
	target_view.display(target.selected,network.entities[target.selected],target.profile,target.last_code)
	target_view.visible=not (is_instance_valid(target_list) or is_instance_valid(economy_panel) or gathering_panel.visible or is_instance_valid(help_panel) or team_panel.visible or social_panel.visible or bag_overlay!=null or menu.visible or details.visible or npc_dialog.visible or encounter.visible or battle_view.visible or solo_battle.visible or duel_battle.visible or team_battle.visible or expanded_chat.visible or attributes.visible or world_map.visible)
	if not target_view.visible:target_view.close_actions()
	target_view.buttons.duel.disabled=not network.duel.enabled or network.duel.pending()
	var friends:bool=social.state.get("friends",[]).any(func(p:Dictionary)->bool:return p.id==target.selected)
	target_view.buttons.friend.text="已是好友" if friends else "加为好友"
	target_view.buttons.friend.disabled=friends or social.pending() or social.inflight or not social.request.is_empty()
	target_view.buttons.team.disabled=not team.can_submit()

func _target_action(action:String)->void:
	var id:=target.selected
	if action=="clear":target.clear();return
	if id.is_empty() or not network.world_ready or not network.entities.has(id) or not target_view.is_visible_in_tree() or network.pve.pending() or network.pve.active() or team.active() or network.duel.active() or map_transition.blocking:return
	match action:
		"profile":_open_social("profile",id)
		"friend":
			if not social.submit("friend_request",id):chat_status.text="正在同步社交信息，请稍后再试。"
		"team":
			if not team.submit("invite",id):chat_status.text="正在同步队伍，请稍后再邀请。"
		"duel":_invite_player(id)

func _open_social(section: String, target: String="") -> void:
	if team_panel.visible:team_panel.dismiss()
	_close_inventory();_close_world_map();_close_attributes();_cancel_approach()
	menu.hide();details.hide();npc_dialog.hide();encounter.hide();duel_invitation.selected=""
	if expanded_chat.visible:expanded_chat.dismiss()
	if network.world_ready:network.stop_moving()
	Platform.context.text_input.release_focus(chat_input)
	_was_keyboard=false
	social_panel.open(section,target)
	if not social.supported:social_panel.notice.text="当前服务尚未支持，请更新并重启游戏服务。"

func _social_completed(action: String, result: Dictionary) -> void:
	if action=="social":social.receive(result)
	elif action=="teams":team.receive(result)
	elif action=="target_profile":target.receive(result)

func _open_team()->void:
	if social_panel.visible:social_panel.dismiss()
	_close_inventory();_close_attributes();_close_world_map();_cancel_approach()
	menu.hide();details.hide();npc_dialog.hide();encounter.hide()
	if expanded_chat.visible:expanded_chat.dismiss()
	Platform.context.text_input.release_focus(chat_input)
	network.stop_moving();_was_keyboard=false;team_panel.open()

func _team_changed()->void:
	_refresh_player_display()
	network.team_active=team.active()
	menu.rows[5].text="队伍（%d）"%team.party().get("members",[]).size() if not team.party().is_empty() else "队伍"
	team_notice.visible=not team.state.incoming.is_empty() and not team.active() and not network.pve.active() and not network.duel.active()
	if team_notice.visible:
		team_notice_text.text="%s 邀请组队"%team.state.incoming[0].name
		team_confirm.disabled=team.pending() or team.inflight;team_reject.disabled=team_confirm.disabled
	if team.active():
		_close_target_list()
		_close_economy()
		if not team.presentation_ready() and _team_loading!=team.battle().id:_prepare_team_battle(team.battle())
		network._pending_motion.clear();move_target.clear();_was_keyboard=false;_cancel_approach()
		_close_inventory();_close_world_map();_close_attributes();menu.hide();details.hide();npc_dialog.hide()
		if team.presentation_ready():encounter.hide()
		if social_panel.visible:social_panel.dismiss()
		if team_panel.visible:team_panel.dismiss()
		if expanded_chat.visible:expanded_chat.dismiss()
		screen.hud.hide();count_label.hide();_set_battle_layout(true);screen.chrome.round_label.text="组队战斗"
	else:
		if not _team_loading.is_empty():_cancel_team_preparation()
		if team.loot_pending() and team_battle.battle_id!=team.battle().id and _restored_loot!=team.battle().id:
			_restored_loot=team.battle().id;TeamLootPanel.open_for(team_battle,team)

func _cancel_team_preparation()->void:
	_team_load_epoch+=1
	if _team_resource_request!=null:_team_resource_request.cancel()
	_team_resource_request=null;_team_loading=""
	if is_instance_valid(encounter) and _loading_battle.is_empty():encounter.hide()
	if is_instance_valid(screen) and not team.active() and not network.pve.active() and not network.duel.active():
		screen.hud.show();count_label.show();_set_battle_layout(false)

func _team_preparation_current(epoch:int,id:String)->bool:
	return is_inside_tree() and not is_queued_for_deletion() and epoch==_team_load_epoch and team.active() and team.battle().get("id")==id

func _prepare_team_battle(snapshot:Dictionary)->void:
	_cancel_team_preparation()
	team_battle.hide()
	var epoch:=_team_load_epoch;var id:=String(snapshot.id);_team_loading=id
	encounter.present("challenge",String(snapshot.enemies[0].definition.name),_hero_screen_point())
	encounter.set_progress(0.0,"准备队伍战斗资源")
	await get_tree().process_frame
	if not _team_preparation_current(epoch,id):return
	var keys:Array[String]=["effect/flash",BattleDeathPlayback.ART_KEY]
	keys.append_array(BattleResultView.ART_KEYS)
	for f in snapshot.fighters:
		var key:=ShopRules.actor_key(int(f.job),int(f.gender),f.appearance)
		if not keys.has(key):keys.append(key)
		for effect in BattleEffects.preload_keys(int(f.job),int(f.school),int(f.level),false):
			if not keys.has(effect):keys.append(effect)
	for e in snapshot.enemies:
		if not keys.has(String(e.definition.art)):keys.append(String(e.definition.art))
	var paths:Array[String]=["res://assets/tiles/original_tiles.png"]
	var frame_started:=Time.get_ticks_usec()
	for key in keys:
		var info:=OriginalArt.actor_info(key)
		if info.is_empty():
			_cancel_team_preparation();chat_status.text="战斗资源读取失败，请检查游戏文件后重试。";return
		for path in [String(info.texture),OriginalArt.scene_path(key)]:
			if not paths.has(path):paths.append(path)
		if Time.get_ticks_usec()-frame_started>=4000:
			await get_tree().process_frame;frame_started=Time.get_ticks_usec()
			if not _team_preparation_current(epoch,id):return
	# Five different jobs/styles can need more than one loader batch.
	# Keep earlier batches alive until warming consumes their resources; Godot's
	# resource cache is weak and the next request otherwise releases that batch.
	var prepared_requests:Array[PlatformResourceRequest]=[]
	for start in range(0,paths.size(),96):
		var request:=Platform.context.resource_loader.prepare(PackedStringArray(paths.slice(start,start+96)),self,epoch,"Resource")
		prepared_requests.append(request)
		_team_resource_request=request
		while not request.is_finished():
			encounter.set_progress(.75*(start+request.progress*min(96,paths.size()-start))/paths.size(),"准备队伍战斗资源")
			await get_tree().process_frame
			if not _team_preparation_current(epoch,id):request.cancel();return
		if not request.result.ok:
			_cancel_team_preparation();chat_status.text="战斗资源读取失败，进度已保留，正在重试。";return
	frame_started=Time.get_ticks_usec()
	for i in keys.size():
		if not OriginalArt.is_prepared(keys[i]):
			var actor:=OriginalArt.actor(keys[i]);actor.free()
		encounter.set_progress(.75+.25*float(i+1)/keys.size(),"准备队友动作与招式")
		if Time.get_ticks_usec()-frame_started>=4000:
			await get_tree().process_frame;frame_started=Time.get_ticks_usec()
			if not _team_preparation_current(epoch,id):return
	if not _team_preparation_current(epoch,id):return
	_team_resource_request=null;_team_loading="";team.display_ready=true
	encounter.hide();team_battle.present()

func _social_changed() -> void:
	var incoming: Array=[]
	for entry in social.state.get("incoming",[]):incoming.append(entry.id)
	menu.rows[3].text="社交（%d）"%incoming.size() if not incoming.is_empty() else "社交"
	for id in incoming:
		if not _social_incoming.has(id):
			expanded_chat.add_system("收到好友申请，请在菜单 → 社交 → 申请中查看。")
			break
	_social_incoming=incoming

func _invite_player(id: String) -> void:
	if not network.duel.enabled:
		chat_status.text="服务器尚未支持玩家决斗。";return
	if not network.entities.has(id):
		chat_status.text="只能邀请同地图的在线玩家决斗。";return
	if not network.world_ready or not network.entities.has(id) or network.pve.pending() or network.pve.active() or map_transition.blocking: return
	network.duel.submit("invite",id)

func _duel_changed() -> void:
	duel_invitation.refresh()
	var data: Variant = network.duel.state.get("battle")
	if not data is Dictionary:
		if (network.duel.connected or not network.duel.enabled) and duel_battle.visible:
			duel_battle._cancel_motion();duel_battle.hide()
			screen.hud.show();count_label.show();_set_battle_layout(false)
			if not _character.is_empty(): screen.chrome.display_character(_character)
		return
	if data.status != "active" and (data.id == _closed_duel or duel_battle.battle_id != data.id):
		_closed_duel = data.id
		return
	if data.status == "active":
		_close_economy()
		if social_panel.visible:social_panel.dismiss()
		_cancel_approach();move_target.clear();_was_keyboard=false
		_close_inventory();_close_world_map();_close_attributes()
		npc_dialog.hide();menu.hide();details.hide()
		if expanded_chat.visible: expanded_chat.dismiss()
		Platform.context.text_input.release_focus(chat_input)
	duel_battle.present_duel(network.duel)
	var me: Dictionary = data.fighters[0] if data.fighters[0].id == character_id else data.fighters[1]
	screen.chrome.display_character({"level":me.level,"hp":me.hp,"mp":me.mp,"max_hp":me.stats.hp,"max_mp":me.stats.mp})
	screen.hud.hide();count_label.hide();_set_battle_layout(true)
	screen.chrome.round_label.text = "玩家决斗"
	screen.chrome.round_label.add_theme_color_override("font_color",Color("fff3b5"))
	var lines: String = "\n".join(PackedStringArray(data.lines))
	if lines != _duel_lines:
		_duel_lines = lines;_system_text = lines;_pve_log = lines;expanded_chat.add_system(lines);_chat_changed()

func _begin_map_transition() -> void:
	_close_target_list()
	if map_transition.blocking: return
	target.clear()
	_cancel_gathering()
	_transfer_origin = String(map_data.map_id)
	_cancel_approach()
	_close_inventory()
	_close_world_map()
	_close_attributes()
	menu.hide()
	details.hide()
	npc_dialog.hide()
	if expanded_chat.visible: expanded_chat.dismiss()
	emote_picker.hide()
	Platform.context.text_input.release_focus(chat_input)
	move_target.clear()
	_was_keyboard = false
	map_transition.begin(ShopRules.actor_key(int(_character.get("job", 0)), int(_character.get("gender", 0)), _character.get("appearance", [1, 0])))
	map_transition.set_progress(0.15)

func _advance_map_transition() -> void:
	if not map_transition.blocking: return
	# auth.ready changes terrain before the baseline and population have arrived.
	# Do not reveal the new map until all three authoritative channels agree.
	if network.map_id == _transfer_origin: return
	map_transition.set_progress(0.50)
	if not network.world_ready or not actors.has(character_id): return
	map_transition.set_progress(0.70)
	if not network.pve.ready or network.pve.state.get("character", {}).get("map_id") != network.map_id or network.pve.pending(): return
	map_transition.set_progress(0.85)
	if network.population.revision < 0 or String(map_data.map_id) != network.map_id: return
	map_transition.complete()

func _build_map() -> void:
	if not is_instance_valid(day_night):
		day_night = WorldDayNight.new()
		day_night.name = "DayNight"
		day_night.time_source = network.world_time_seconds
		scene.add_child(day_night)
	day_night.set_map(map_data)
	SharedWorldMap.build($Viewport/Scene/Terrain, _motion_grid, map_data)
	soul_markers=preload("res://scenes/actors/soul_markers.tscn").instantiate()
	actor_layer.add_child(soul_markers)
	soul_markers.display(String(map_data.map_id))
	SharedWorldMap.add_scenery(actor_layer, map_data)
	_build_portals()

func _build_portals()->void:
	for child in actor_layer.get_children():
		if child.has_meta("online_portal"):actor_layer.remove_child(child);child.queue_free()
	portal_marker=null;ai_station=null;_portal_latch="";_portal_stop=""
	for gate in network.map_rules.exits(String(map_data.map_id)):
		var node:=Node2D.new();node.set_script(preload("res://scripts/portal.gd"));node.set("gate",gate);node.set_meta("online_portal",true)
		node.position=Vector2(gate.cell[0]*16+8,gate.cell[1]*16+8);actor_layer.add_child(node)
		if portal_marker==null:portal_marker=node
		var label:=Label.new();label.text=SharedWorldMap.exit_label(gate);label.position=Vector2(-65,-24);label.size=Vector2(130,16);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",10);preload("res://scripts/world_nameplate.gd").apply(label,Color("c2f7f4"));node.add_child(label)

func _map_changed(id: String) -> void:
	_close_target_list()
	target.clear()
	gathering_panel.hide();gathering_nodes.clear();_gather_auto_token=""
	if social_panel.visible:social_panel.dismiss()
	duel_invitation.selected = ""
	_portal_latch=""
	_portal_stop=""
	_cancel_approach()
	_cancel_battle_preparation()
	_close_inventory()
	ai_station = null
	npc_dialog.hide()
	move_target.clear()
	actors.clear()
	residents.clear()
	for child in actor_layer.get_children():
		actor_layer.remove_child(child)
		child.queue_free()
	map_data = SharedWorldMap.load_data(id)
	_build_map()
	screen.hud.get_node("MapName").text = SharedWorldMap.title(id)
	screen.hud.get_node("MapName").size.x = 78 if AIWorld.map_data(id).is_empty() else 220
	screen.hud.get_node("Minimap").set_shared_world(map_data, {}, character_id)
	screen.hud.get_node("Minimap").set_shared_population({})
	_was_keyboard = false


func _population(values: Dictionary) -> void:
	var visible_values := values.duplicate()
	_hidden_residents = network.pve.unavailable_monsters()
	for id in _hidden_residents: visible_values.erase(id)
	for id in residents.keys():
		if not visible_values.has(id):
			residents[id].queue_free()
			residents.erase(id)
	for id in visible_values:
		if not residents.has(id):
			var resident: OnlineResident = preload("res://scenes/actors/online_resident.tscn").instantiate()
			actor_layer.add_child(resident)
			residents[id] = resident
		residents[id].receive(visible_values[id], _motion_grid)
		residents[id].set_quest_stage(int(network.pve.state.get("character", {}).get("quest_stage", -1)) if network.pve.ready else -1)
		if id=="qingwei" and network.pve.ready and int(_character.get("school",SchoolRules.UNJOINED))==SchoolRules.UNJOINED:
			residents[id].set_quest_stage(0,"与清微道人交谈，选择门派。")
		if not AIWorld.resident(id).is_empty():
			var marker := AIWorld.npc_marker(id,network.pve.state.get("ai_world",{}),int(_character.get("level",1))) if network.pve.ready else {"stage":-1,"hint":""}
			residents[id].set_quest_stage(marker.stage,marker.hint)
	screen.hud.get_node("Minimap").set_shared_population(visible_values)
	_refresh_npc_finder()

func _apply_player_display(id: String) -> void:
	var actor: Dictionary = actors[id]
	var protected: bool = id == character_id or team.party().get("members", []).any(func(member: Dictionary) -> bool: return member.id == id)
	actor.root.visible = protected or WorldDisplaySettings.mode != "hidden"
	actor.root.modulate.a = 1.0 if protected or WorldDisplaySettings.mode != "faded" else 0.25
	if not actor.root.visible:
		actor.sprite.pause()
		if target.selected == id: target.clear()
	else:
		var entity: Dictionary = network.entities.get(id, {})
		if not entity.is_empty():
			OriginalArt.apply_appearance(actor.sprite, ShopRules.actor_key(int(entity.job), int(entity.gender), network.appearances.get(id, [1, 0])))

func _refresh_player_display() -> void:
	_display_mode = WorldDisplaySettings.mode
	for id in actors: _apply_player_display(id)

func _snapshot(values: Dictionary) -> void:
	for id in actors.keys():
		if not values.has(id):
			actors[id].root.queue_free()
			actors.erase(id)
	for id in values:
		var entity: Dictionary = values[id]
		var point := Vector2(entity.cell[0] * 16 + 8, entity.cell[1] * 16 + 8)
		if entity.next_cell != null:
			point = point.lerp(Vector2(entity.next_cell[0] * 16 + 8, entity.next_cell[1] * 16 + 8), float(entity.segment_progress) / 1000.0)
		if not actors.has(id):
			var root := Node2D.new()
			root.position = point
			actor_layer.add_child(root)
			var key: String = (["mzs", "mck", "mfs"] if int(entity.gender) == 0 else ["wzs", "wck", "wfs"])[int(entity.job)]
			var sprite := OriginalArt.actor("hero/" + key)
			root.add_child(sprite)
			if id == character_id: root.add_child(preload("res://scenes/actors/player_ring.tscn").instantiate())
			var label := OriginalSceneChrome.label(root, entity.display_name, Rect2(-65, -72, 130, 18), 11, Color("fff0a5") if id == character_id else Color("9ef6ff"))
			label.position.y=-74
			preload("res://scripts/world_nameplate.gd").apply(label,Color("fff0a5") if id==character_id else Color("9ef6ff"))
			var flag:=Sprite2D.new();flag.set_script(preload("res://scripts/team_marker.gd"));root.add_child(flag)
			flag.position=Vector2(-ceilf(label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x/2.0)-10,-63)
			actors[id] = {"flag":flag,"root": root, "sprite": sprite, "target": point, "distance": 0.0, "motion": OnlineActorMotion.new()}
		actors[id].flag.update_state(network.team_marks.get(id,{}))
		_apply_player_display(id)
		actors[id].target = point
		if id==character_id and _soul_snap_pending and network.pve.is_soul():
			var character:Dictionary=network.pve.state.character
			if Vector2i(entity.cell[0],entity.cell[1])==Vector2i(character.cell_x,character.cell_y):
				actors[id].motion=OnlineActorMotion.new();_soul_snap_pending=false
		actors[id].motion.receive(entity, _motion_grid)
		actors[id].root.position = actors[id].motion.position
	if not duel_invitation.selected.is_empty() and not values.has(duel_invitation.selected): duel_invitation.selected = ""
	if not target.selected.is_empty() and not values.has(target.selected):target.clear()
	count_label.text = "同图%d人" % actors.size()
	screen.hud.get_node("Minimap").set_shared_world(map_data, values, character_id)
	if values.has(character_id):
		var own: Dictionary = values[character_id]
		screen.hud.get_node("MapCoordinates").text = "%d  %d" % [int(own.cell[0]), int(own.cell[1])]
		screen.hud.get_node("WorldIdentity").text = "等级 %d\n%s" % [int(_character.get("level",1)),SchoolRules.label(int(_character.get("school",SchoolRules.UNJOINED)))]
	if _pve_log.is_empty(): _system_text = "同图%d人 · 点击移动 / WASD" % actors.size()
	status.text = _system_text
	_chat_changed()

func _toggle_chat() -> void:
	menu.hide()
	details.hide()
	emote_picker.hide()
	if chat_input.has_focus(): Platform.context.text_input.release_focus(chat_input)
	else: _focus_chat()

func _focus_chat() -> void:
	expanded_chat.close_emotes()
	menu.hide()
	details.hide()
	emote_picker.hide()
	Platform.context.text_input.request_focus(chat_input)

func _toggle_emotes() -> void:
	if not _can_insert_emote(): return
	menu.hide()
	details.hide()
	Platform.context.text_input.request_focus(chat_input)
	if network.world_ready: network.stop_moving()
	_was_keyboard = false
	if expanded_chat.visible: expanded_chat.toggle_emotes()
	else: emote_picker.visible = not emote_picker.visible

func _insert_emote(token: String) -> void:
	if not _can_insert_emote() or not chat_input.editable or ChatEmotePicker.CATALOG.texture_for(token) == null: return
	var start := chat_input.get_selection_from_column() if chat_input.has_selection() else chat_input.caret_column
	var end := chat_input.get_selection_to_column() if chat_input.has_selection() else start
	var draft := chat_input.text.left(start) + token + chat_input.text.substr(end)
	if draft.length() > 120 or draft.to_utf8_buffer().size() > 480:
		chat_status.text = "消息最多120字，请删减后再添加表情。"
		expanded_chat.set_status(chat_status.text)
		return
	chat_input.text = draft
	expanded_chat.close_emotes()
	chat_input.deselect()
	chat_input.caret_column = start + token.length()
	emote_picker.hide()
	Platform.context.text_input.request_focus(chat_input)

func _can_insert_emote() -> bool:
	return network.world_ready and network.chat.connected and network.chat.pending.is_empty() and Platform.context.text_input.check_submission([chat_input]).ok

func _send_chat() -> void:
	var input_result := Platform.context.text_input.check_submission([chat_input])
	if not input_result.ok:
		chat_status.text = input_result.message
		expanded_chat.set_status(input_result.message)
		return
	emote_picker.hide()
	expanded_chat.close_emotes()
	network.chat.submit(chat_input.text)
	_update_chat_controls()

func _chat_changed() -> void:
	expanded_chat.sync_messages(network.chat.messages)
	var lines := PackedStringArray()
	if not _pve_log.is_empty() or network.chat.messages.is_empty() or not network.world_ready: lines.append("[系统] " + _system_text)
	for message in network.chat.messages: lines.append("[系统] " + message.text if message.get("system", false) else "[公共] %s：%s" % [message.display_name, message.text])
	var text_value := "\n".join(lines)
	if text_value != _rendered_chat:
		_rendered_chat = text_value
		chat_log.clear()
		if not _pve_log.is_empty() or network.chat.messages.is_empty() or not network.world_ready:
			chat_log.add_text("[系统] " + _system_text)
			if not network.chat.messages.is_empty(): chat_log.add_text("\n")
		for index in network.chat.messages.size():
			if index > 0: chat_log.add_text("\n")
			var message: Dictionary = network.chat.messages[index]
			chat_log.add_text("[系统] " if message.get("system", false) else "[公共] %s：" % message.display_name)
			ChatEmotePicker.CATALOG.append_body(chat_log, message.text)
	chat_button.tooltip_text = "公共聊天 · %d条消息" % network.chat.messages.size()

func _update_chat_controls() -> void:
	if network != null:
		chat_send.disabled = not network.world_ready or not network.chat.connected or not network.chat.pending.is_empty()
		chat_input.editable = network.chat.pending.is_empty()
		emote_button.disabled = chat_send.disabled
		expanded_chat.set_emotes_enabled(not emote_button.disabled)
		if emote_button.disabled: emote_picker.hide()

func _process(delta: float) -> void:
	if _display_mode != WorldDisplaySettings.mode: _refresh_player_display()
	if is_instance_valid(target_list) and (network.pve.active() or network.pve.pending() or team.active() or network.duel.active() or network.pve.is_soul()): _close_target_list()
	_update_soul_visuals()
	var social_available:=network.world_ready and OnlineAccount.is_logged_in() and not OnlineAccount.busy and not OnlineAccount.network_suspended
	if Platform.context.lifecycle.suspended:social_available=false
	if OS.has_feature("web") and (not Platform.context.lifecycle.focused or Platform.context.lifecycle.suspended):social_available=false
	social.tick(social_available)
	team.tick(social_available and not OnlineAccount.busy)
	_update_chat_controls()
	_update_allocation_controls()
	_advance_map_transition()
	_gather_tick()
	_refresh_target()
	target.tick(social_available and not OnlineAccount.busy and target_view.visible)
	if network == null or not network.world_ready: return
	if network.pve.ready and network.pve.unavailable_monsters() != _hidden_residents:
		_population(network.population.entities)
	for resident in residents.values(): resident.advance(delta)
	for id in actors:
		var actor: Dictionary = actors[id]
		var old: Vector2 = actor.root.position
		var motion: OnlineActorMotion = actor.motion
		motion.advance(delta)
		actor.root.position = motion.position
		if not actor.root.visible: continue
		var distance := motion.travelled
		if distance > 0.001:
			actor.distance += distance
			if absf(actor.root.position.x - old.x) > 0.001: actor.sprite.scale.x = 1.0 if actor.root.position.x < old.x else -1.0
			actor.sprite.animation = "walk"
			actor.sprite.pause()
			var phase: float = actor.distance / 32.0 * actor.sprite.sprite_frames.get_frame_count("walk")
			actor.sprite.set_frame_and_progress(int(phase) % actor.sprite.sprite_frames.get_frame_count("walk"), fposmod(phase, 1.0))
		elif motion.has_motion():
			actor.sprite.animation = "walk"
			actor.sprite.pause()
		elif actor.sprite.animation != "idle" or not actor.sprite.is_playing():
			actor.distance = 0.0
			actor.sprite.play("idle")
	if actors.has(character_id): camera.position = actors[character_id].root.position
	if encounter.visible: encounter.set_hero_point(_hero_screen_point())
	_update_move_target(delta)
	if map_transition.blocking: return
	if network.duel.active() or duel_battle.visible or team.active() or team_battle.visible: return
	if OS.has_feature("web") and (not Platform.context.lifecycle.focused or Platform.context.lifecycle.suspended): return
	if _follow_transfer():return
	_advance_approach()
	if gathering_panel.visible and GatheringPanel.movement_pressed():_cancel_gathering()
	if is_instance_valid(target_list) or is_instance_valid(economy_panel) or gathering_panel.visible or target_view.actions.visible or is_instance_valid(help_panel) or team_panel.visible or social_panel.visible or bag_overlay != null or chat_input.has_focus() or menu.visible or details.visible or npc_dialog.visible or emote_picker.visible or encounter.visible or (battle_view.visible or solo_battle.visible) or expanded_chat.visible or attributes.visible or world_map.visible or network.pve.pending() or network.pve.active():
		_was_keyboard = false
		return
	if network.team_following: return
	if _auto_transfer(): return
	_key_timer -= delta
	var direction := Vector2i(int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if direction.x != 0: direction.y = 0
	if direction != Vector2i.ZERO: _cancel_approach()
	if direction != Vector2i.ZERO: move_target.clear()
	if direction != Vector2i.ZERO and _key_timer <= 0 and network.entities.has(character_id):
		_key_timer = 0.15
		var own: Dictionary = network.entities[character_id]
		var cell: Array = own.next_cell if own.next_cell != null else own.cell
		var destination := Vector2i(cell[0], cell[1]) + direction
		if _motion_grid.region.has_point(destination) and not _motion_grid.is_point_solid(destination): network.move_to(destination)
		else: network.stop_moving()
		_was_keyboard = true
	elif direction == Vector2i.ZERO and _was_keyboard:
		network.stop_moving()
		_was_keyboard = false

func _map_input(event: InputEvent) -> void:
	if map_transition.blocking: return
	if network.duel.active() or duel_battle.visible or team.active() or team_battle.visible or team_panel.visible: return
	if _battle_load_failed:
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed): _pve_changed()
		return
	if is_instance_valid(target_list) or is_instance_valid(economy_panel) or is_instance_valid(help_panel) or social_panel.visible or bag_overlay != null or not network.world_ready or menu.visible or details.visible or npc_dialog.visible or encounter.visible or (battle_view.visible or solo_battle.visible) or expanded_chat.visible or attributes.visible or world_map.visible or network.pve.pending() or network.pve.active(): return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: point = event.position
	elif event is InputEventScreenTouch and event.pressed: point = event.position
	else: return
	if target_view.actions.visible:
		target_view.close_actions()
		return # Dismissal consumes the click; never also move or select a different player.
	if gathering_panel.visible:_cancel_gathering();return
	if emote_picker.visible:
		emote_picker.hide()
		return
	Platform.context.text_input.release_focus(chat_input)
	_was_keyboard = false
	var world_point := camera.get_screen_center_position() + point - Vector2(viewport.size) / 2.0
	if network.pve.is_soul():
		if soul_markers.hit(world_point):
			_resident_action("revive",network.pve.state.character.corpse.id)
			return
		_cancel_approach()
		var destination:=Vector2i(floori(world_point.x/16.0),floori(world_point.y/16.0))
		if _motion_grid.region.has_point(destination) and not _motion_grid.is_point_solid(destination):network.move_to(destination);_mark_destination(destination)
		return
	var hits := _targets_at(world_point)
	if hits.size() > 1:
		_open_target_list(hits)
		return
	if hits.size() == 1:
		_choose_world_target(hits[0].kind, hits[0].id)
		return
	if network.team_following:
		chat_status.text="跟随中由队长控制移动，可在队伍界面暂离。"
		return
	for gate in network.map_rules.exits(String(map_data.map_id)):
		var center:=Vector2(gate.cell[0]*16+8,gate.cell[1]*16+8)
		if Rect2(center-Vector2(8,8),Vector2(16,16)).has_point(world_point):
			_cancel_approach();network.move_to(Vector2i(gate.cell[0],gate.cell[1]));_mark_destination(Vector2i(gate.cell[0],gate.cell[1]));return
	for id in residents:
		if residents[id].hit(world_point):
			resident_selected.emit(id)
			return
	for id in gathering_nodes:
		if gathering_nodes[id].hit(world_point):_resident_action("gather",id);return
	duel_invitation.selected = ""
	_cancel_approach()
	var destination := Vector2i(floori(world_point.x / 16.0), floori(world_point.y / 16.0))
	if _motion_grid.region.has_point(destination) and not _motion_grid.is_point_solid(destination):
		network.move_to(destination)
		_mark_destination(destination)
	else:
		network.stop_moving()
		chat_status.text = "目标不可达，已停止原路线。"

func _targets_at(point: Vector2) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if not network.team_following:
		for id in residents:
			var resident: OnlineResident = residents[id]
			if resident.is_queued_for_deletion() or not resident.is_visible_in_tree() or not resident.hit(point): continue
			hits.append({"kind":"resident", "id":id, "name":resident.data.name, "detail":"NPC · 对话" if resident.data.kind == "npc" else "怪物 · 前往挑战"})
	for id in actors:
		if id == character_id or not actors[id].root.visible: continue
		if Rect2(actors[id].root.position - Vector2(20, 60), Vector2(40, 64)).has_point(point):
			hits.append({"kind":"player", "id":id, "name":network.entities[id].display_name, "detail":"玩家 · 查看目标"})
	return hits

func _open_target_list(entries: Array[Dictionary], caption: String = "重叠目标，请选择") -> void:
	_close_target_list()
	_cancel_approach()
	if network.world_ready and not network.team_following: network.stop_moving()
	move_target.clear(); _was_keyboard = false
	target_list = WorldTargetList.new()
	target_list.entries = entries; target_list.caption = caption
	add_child(target_list)
	var picker := target_list
	target_list.dismissed.connect(func() -> void:
		if target_list == picker: _close_target_list()
	)
	var source_map: String = map_data.map_id
	target_list.chosen.connect(func(kind: String, id: String) -> void:
		if target_list == picker and String(map_data.map_id) == source_map: _choose_world_target(kind, id)
	)

func _close_target_list() -> void:
	if is_instance_valid(target_list): remove_child(target_list); target_list.queue_free()
	target_list = null

func _choose_world_target(kind: String, id: String) -> void:
	_close_target_list()
	if map_transition.blocking or not network.world_ready or network.pve.active() or network.pve.pending() or team.active() or network.duel.active() or network.pve.is_soul(): return
	if kind == "player":
		_select_player(id)
	elif kind == "npc_find":
		_start_npc_find(id)
	elif kind == "resident" and not network.team_following and residents.has(id) and not residents[id].is_queued_for_deletion() and id not in network.pve.unavailable_monsters():
		resident_selected.emit(id)
	else:
		chat_status.text = "目标已离开或当前不能交互，请重新选择。"

func _npc_find_available(id: String) -> bool:
	var resident: Dictionary = network.population.entities.get(id, {})
	if resident.get("kind") != "npc" or not residents.has(id) or residents[id].is_queued_for_deletion(): return false
	if network.map_rules.map_id == String(map_data.map_id):
		for rule in network.map_rules.rules.get("residents", []):
			if rule.id == id: return rule.enabled
	return true

func _npc_finder_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not network.entities.has(character_id): return entries
	var own: Dictionary = network.entities[character_id]
	var origin := Vector2i(own.cell[0], own.cell[1])
	for id in network.population.entities:
		if not _npc_find_available(id): continue
		var resident: Dictionary = network.population.entities[id]
		var marker: NpcQuestMarker = residents[id].get_node("QuestMarker")
		entries.append(NpcFinder.row(resident, origin, marker.quest_stage, marker.tooltip_text if marker.visible else ""))
	return entries

func _refresh_npc_finder() -> void:
	if not is_instance_valid(target_list) or not target_list.get_meta("npc_finder", false): return
	target_list.entries = _npc_finder_entries()
	target_list._refresh()

func _open_npc_finder() -> void:
	if not network.world_ready or not network.pve.ready or network.pve.pending() or network.pve.active():
		chat_status.text = "正在同步或战斗中，暂时不能寻找NPC。"; return
	if network.pve.is_soul(): chat_status.text = OnlinePve.error_text("SOUL_STATE"); return
	if network.team_following: chat_status.text = "跟随中请先在队伍界面暂离，再寻找NPC。"; return
	if not network.entities.has(character_id): return
	_open_target_list(_npc_finder_entries(), "寻找NPC · 当前地图")
	target_list.set_meta("npc_finder", true)

func _start_npc_find(id: String) -> void:
	if not network.pve.ready or network.team_following or not _npc_find_available(id):
		chat_status.text = "目标已离开、禁用或当前处于跟随中，请重新选择。"; return
	target.clear()
	_select_resident(id)
	if not _approach.is_empty():
		_approach.npc_find = true; _approach.map_id = String(map_data.map_id)
		# The full-map route may need longer than the legacy 30-second click approach.
		_approach.deadline = Time.get_unix_time_from_system() + 240.0
		chat_status.text = "正在寻找%s，手动移动或按Esc取消。" % String(network.population.entities[id].name)

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(target_list):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_target_list(); get_viewport().set_input_as_handled()
		return
	if is_instance_valid(economy_panel):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			if economy_panel.confirmation.visible:economy_panel.confirmation.hide()
			else:_close_economy()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(help_panel):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_close_help();get_viewport().set_input_as_handled()
		return
	if map_transition.blocking: return
	if network.duel.active() or duel_battle.visible or team.active() or team_battle.visible: return
	if not event is InputEventKey or not event.pressed: return
	if gathering_panel.visible and event.keycode==KEY_ESCAPE:
		_cancel_gathering();get_viewport().set_input_as_handled();return
	if event.keycode==KEY_ESCAPE and not target.selected.is_empty() and target_view.visible:
		if target_view.actions.visible:target_view.close_actions()
		else:target.clear()
		get_viewport().set_input_as_handled();return
	if team_panel.visible:
		if event.keycode==KEY_ESCAPE:team_panel.dismiss();get_viewport().set_input_as_handled()
		return
	if social_panel.visible:
		if event.keycode==KEY_ESCAPE:
			social_panel.dismiss();get_viewport().set_input_as_handled()
		return
	if ai_panel != null:
		if event.keycode == KEY_ESCAPE: _close_inventory(); get_viewport().set_input_as_handled()
		return
	if shop != null:
		if event.keycode == KEY_ESCAPE:
			_close_inventory()
			get_viewport().set_input_as_handled()
		return
	if backpack != null:
		if event.keycode == KEY_ESCAPE and backpack.item_menu == null:
			_close_inventory()
			get_viewport().set_input_as_handled()
		return
	if npc_dialog.visible:
		if event.keycode == KEY_ESCAPE:
			npc_dialog.dismiss()
			get_viewport().set_input_as_handled()
		return
	if world_map.visible:
		world_map._unhandled_key_input(event)
		return
	if attributes.visible:
		if event.keycode == KEY_ESCAPE:
			_close_attributes()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if expanded_chat.visible:
			if expanded_chat.picker.visible: expanded_chat.close_emotes()
			else: expanded_chat.dismiss()
			get_viewport().set_input_as_handled()
			return
		if (battle_view.visible or solo_battle.visible): return
		if not _approach.is_empty():
			_cancel_approach()
		elif emote_picker.visible: emote_picker.hide()
		elif menu.visible: menu.dismiss()
		elif details.visible: details.hide()
		elif chat_input.has_focus(): Platform.context.text_input.release_focus(chat_input)
		else: _scene_action("menu")
	elif event.keycode == KEY_C and not expanded_chat.visible and not (battle_view.visible or solo_battle.visible) and not chat_input.has_focus(): _scene_action("properties")
	elif event.keycode == KEY_3 and not expanded_chat.visible and not (battle_view.visible or solo_battle.visible) and not chat_input.has_focus(): _scene_action("map")
	elif event.keycode == KEY_ENTER: _focus_chat()
	else: return
	get_viewport().set_input_as_handled()

func _pve_changed() -> void:
	var model := network.pve
	if model.is_soul() and model.state.character.corpse.id!=_soul_transition_id:
		_soul_transition_id=model.state.character.corpse.id;_soul_snap_pending=true
		network._pending_motion.clear();move_target.clear();_cancel_approach()
	elif not model.is_soul():_soul_transition_id="";_soul_snap_pending=false
	if not model.ready or model.active(): move_target.clear()
	if model.active():
		_close_target_list()
		if social_panel.visible:social_panel.dismiss()
		_close_economy()
		_close_world_map()
		_close_inventory()
	if model.active(): npc_dialog.hide()
	if not model.ready:
		_cancel_approach()
		_cancel_battle_preparation()
	elif not _loading_battle.is_empty() and (not model.state.get("battle") is Dictionary or model.state.battle.id != _loading_battle):
		_cancel_battle_preparation()
	if not model.state.is_empty():
		_character = model.state.character.duplicate(true)
		_character.appearance = model.appearance()
		_character.max_hp = model.state.stats.hp
		_character.max_mp = model.state.stats.mp
		_character.next_xp = int(_character.level) * 40
		if attributes.visible: attributes.display_online(_character, model.state.stats, model.state.get("attributes", {}))
		screen.chrome.display_character(_character)
		screen.hud.get_node("WorldIdentity").text = "等级 %d\n%s" % [int(_character.level),SchoolRules.label(int(_character.school))]
		_population(network.population.entities)
		if model.state.battle is Dictionary and (model.active() or model.state.battle.id != _closed_battle):
			if battle_view.battle_id == model.state.battle.id or (model.state.battle.get("formation") is Dictionary and solo_battle.battle_id==model.state.battle.formation.id):
				_present_battle()
			elif model.ready and _loading_battle != model.state.battle.id:
				_prepare_battle(model.state.battle)
		elif (battle_view.visible or solo_battle.visible):
			battle_view.hide();solo_battle.hide()
			_set_battle_layout(false)
			screen.hud.show()
			count_label.show()
	if _loading_battle.is_empty(): _refresh_interaction_wait()
	npc_dialog.refresh()
	battle_view.refresh()
	_update_soul_visuals()
	var invitation:Variant=model.state.get("economy",{}).get("incoming_trade")
	if invitation!=null and invitation!=_last_trade_invite:
		_last_trade_invite=invitation;chat_status.text="收到当面交易邀请：菜单 → 交易 → 当面，可接受或拒绝。"

func _update_soul_visuals() -> void:
	if network==null or soul_overlay==null:return
	var spirit:=network.pve.is_soul()
	soul_overlay.visible=spirit and not (battle_view.visible or solo_battle.visible) and (team_battle==null or not team_battle.visible)
	if spirit:
		soul_overlay.get_node("Hint").text=SoulRules.hint(network.pve.state.character.corpse)
		network.team_following=false
	screen.hud.get_node("Minimap").shared_corpse=network.pve.state.character.corpse if spirit else {}
	if is_instance_valid(soul_markers):soul_markers.display(String(map_data.map_id),network.pve.state.character.corpse if spirit else {})
	if actors.has(character_id):actors[character_id].sprite.modulate=Color(0.8,0.9,1.0,0.5) if spirit else Color.WHITE

func _select_resident(id: String) -> void:
	if network.pve.is_soul():chat_status.text=OnlinePve.error_text("SOUL_STATE");return
	if team.active():return
	if not team.party().is_empty() and not team.party().get("leader",false) and network.population.entities.get(id,{}).get("kind")!="npc":
		chat_status.text="组队时请由队长发起战斗。";return
	if not network.world_ready or not network.pve.ready or not residents.has(id) or network.pve.active() or network.pve.pending(): return
	_cancel_approach()
	if network.world_ready: network.stop_moving()
	menu.hide()
	details.hide()
	emote_picker.hide()
	npc_dialog.hide()
	_resident_action("ai_npc" if not AIWorld.resident(id).is_empty() and AIWorld.resident(id).kind=="npc" else ("npc" if id=="qingwei" else "challenge"),id)

func _cancel_approach() -> void:
	if _approach.get("npc_find", false): chat_status.text = "已取消寻找NPC。"
	if not _approach.is_empty() and network.world_ready: network.stop_moving()
	_approach = {}
	if npc_dialog != null:
		npc_dialog.approaching = false
		npc_dialog.refresh()

func _follow_transfer()->bool:
	if network.pve.is_soul():return false
	if not network.team_following:
		_follow_trip=""
		return false
	_cancel_approach();move_target.clear();_was_keyboard=false
	var travel:Dictionary=network.team_travel
	if travel.is_empty():_follow_trip="";return false
	if not network.world_ready or not network.pve.ready or network.pve.pending() or network.pve.active() or not network.entities.has(character_id):return false
	var own:Dictionary=network.entities[character_id]
	if own.next_cell!=null or Vector2i(own.cell[0],own.cell[1])!=Vector2i(travel.cell[0],travel.cell[1]):return false
	var key:=String(map_data.map_id)+JSON.stringify(travel)
	if _follow_trip==key:return false
	if actors.has(character_id) and actors[character_id].motion.has_motion():return true
	if network.pve.submit(travel.action,travel.target):_follow_trip=key
	return true

func _auto_transfer() -> bool:
	if _approach.get("npc_find", false): return false
	if network.pve.is_soul():return false
	if not network.pve.ready or not network.entities.has(character_id): return false
	var own: Dictionary=network.entities[character_id]
	if own.next_cell!=null:
		return not network.map_rules.exit_at(String(map_data.map_id),Vector2i(own.next_cell[0],own.next_cell[1])).is_empty()
	var cell:=Vector2i(own.cell[0],own.cell[1])
	var gate:=network.map_rules.exit_at(String(map_data.map_id),cell)
	if gate.is_empty():_portal_latch="";_portal_stop="";return false
	var key: String=String(map_data.map_id)+":"+str(cell)
	if _portal_latch==key:return false
	if _portal_stop!=key:
		_portal_stop=key;network.stop_moving();return true
	if not network._pending_motion.is_empty() or int(own.last_input_seq)<network._input_seq:return true
	if actors.has(character_id) and actors[character_id].motion.has_motion():return true
	_portal_latch=key
	_cancel_approach();move_target.clear()
	if gate.get("legacy",false):network.pve.submit("transfer",gate.get("id",SharedWorldMap.portal(String(map_data.map_id)).id))
	else:network.pve.submit("ai_travel",gate.target_map)
	return true

func _npc_action_chosen(action: String, target: String) -> void:
	if not npc_dialog.visible or not _approach.is_empty() or not network.world_ready or not network.pve.ready or network.pve.pending() or network.pve.active(): return
	if not npc_dialog.allows(action,target): return
	if action=="endless" and not team.party().is_empty():npc_dialog.hint.text=OnlinePve.error_text("ENDLESS_SOLO_ONLY");return
	_resident_action(action, target)
	npc_dialog.approaching = true
	npc_dialog.refresh()

func _resident_action(action: String, target: String) -> void:
	if not network.pve.ready or network.pve.pending(): return
	if network.pve.is_soul() and action!="revive":return
	_approach = {"action": action, "target": target, "deadline": Time.get_unix_time_from_system() + 30.0, "stopped": true}
	network.stop_moving()

func _gathering_changed()->void:
	var values:Array=network.pve.state.get("gathering",{}).get("nodes",[])
	var present:={}
	for value in values:
		if value.map_id!=String(map_data.map_id):continue
		present[value.id]=true
		if not gathering_nodes.has(value.id):
			var resource:=GatheringNode.new();actor_layer.add_child(resource);gathering_nodes[value.id]=resource
		gathering_nodes[value.id].display(value,network.pve.server_time_ms())
		if gathering_panel.node.get("id")==value.id:gathering_panel.node=value.duplicate(true)
	for id in gathering_nodes.keys():
		if not present.has(id):gathering_nodes[id].queue_free();gathering_nodes.erase(id)
	if network.pve.last_action in ["gather_start","gather_finish","gather_cancel"] and not network.pve.pending():
		if not network.pve.last_code.is_empty():
			gathering_panel.hide();chat_status.text=OnlinePve.error_text(network.pve.last_code)
		elif network.pve.last_action!="gather_start":gathering_panel.hide()
	_gather_tick()

func _gather_compatible(active:Dictionary)->bool:
	if active.is_empty() or not network.world_ready or not network.pve.ready or network.pve.active() or team.active() or network.duel.active() or network.pve.is_soul() or map_transition.blocking:return false
	var own:Dictionary=network.entities.get(character_id,{})
	return not own.is_empty() and active.map_id==network.map_id and active.owner_epoch==network.world_epoch and active.connection_epoch==network.connection_epoch and active.position_revision==own.entity_revision and Vector2i(int(active.cell[0]),int(active.cell[1]))==Vector2i(int(own.cell[0]),int(own.cell[1])) and own.next_cell==null and active.revision==network.pve.state.character.state_revision and network.pve.server_time_ms()<=int(active.expires_at_ms)

func _gather_confirm()->void:
	if not gathering_panel.visible or network.pve.pending():return
	var active:=GatheringRules.active(network.pve)
	if not active.is_empty():
		if _gather_compatible(active):network.pve.submit("gather_finish",active.token)
		return
	if not gathering_nodes.has(gathering_panel.node.get("id","")):return
	_gather_cancel_requested=false;_gather_auto_token=""
	network.pve.submit("gather_start",gathering_panel.node.id)

func _cancel_gathering()->void:
	if not is_instance_valid(gathering_panel):return
	gathering_panel.hide();_gather_cancel_requested=true
	var active:=GatheringRules.active(network.pve)
	if not active.is_empty() and network.world_ready and network.pve.ready and not network.pve.pending():
		_gather_cancel_requested=false;network.pve.submit("gather_cancel",active.token)

func _gather_tick()->void:
	if not is_instance_valid(gathering_panel):return
	for resource in gathering_nodes.values():resource.display(resource.data,network.pve.server_time_ms())
	var active:=GatheringRules.active(network.pve)
	if not network.world_ready or network.pve.active() or team.active() or network.duel.active() or map_transition.blocking:
		gathering_panel.hide();return
	if _gather_cancel_requested:
		if not active.is_empty() and network.pve.ready and not network.pve.pending():
			_gather_cancel_requested=false;network.pve.submit("gather_cancel",active.token)
		return
	if not active.is_empty() and not _gather_compatible(active):
		_cancel_gathering();return
	if gathering_panel.visible:
		gathering_panel.display(network.pve)
		if not active.is_empty() and not network.pve.pending() and network.pve.server_time_ms()>=int(active.ready_at_ms)+150 and _gather_auto_token!=active.token:
			_gather_auto_token=active.token;network.pve.submit("gather_finish",active.token)

func _advance_approach() -> void:
	if _approach.is_empty(): return
	var finding: bool = _approach.get("npc_find", false)
	if finding and GatheringPanel.movement_pressed():
		_cancel_approach(); return
	if finding and (network.team_following or String(map_data.map_id) != _approach.map_id or not _npc_find_available(_approach.target)):
		_cancel_approach(); chat_status.text = "寻路已取消：目标离开、禁用或角色状态改变。"; return
	if network.pve.active() or network.pve.pending():
		_cancel_approach()
		return
	if not network.world_ready or not network.pve.ready or Time.get_unix_time_from_system() > float(_approach.deadline):
		_cancel_approach()
		chat_status.text = "未能抵达，请重新选择目标。"
		return
	var transfer: bool = _approach.action == "transfer"
	var ai_travel: bool = _approach.action == "ai_travel"
	var recovering:bool=_approach.action=="revive"
	var gathering:bool=_approach.action=="gather"
	var resident_id: String = "qingwei" if _approach.action=="school_join" else String(AIWorld.quest(_approach.target).get("giver",_approach.target))
	if (gathering and not gathering_nodes.has(_approach.target)) or (not gathering and not recovering and not transfer and not ai_travel and not network.population.entities.has(resident_id)) or not network.entities.has(character_id):
		_cancel_approach()
		return
	var own: Dictionary = network.entities[character_id]
	if own.next_cell != null or not network._pending_motion.is_empty() or int(own.last_input_seq) < network._input_seq: return
	var cell := Vector2i(own.cell[0], own.cell[1])
	if recovering and (not network.pve.is_soul() or _approach.target!=network.pve.state.character.corpse.id):_cancel_approach();return
	if transfer and network.map_rules.portal(String(map_data.map_id)).is_empty() or ai_travel and not network.map_rules.station_enabled(String(map_data.map_id)):_cancel_approach();return
	var station:=network.map_rules.station(String(map_data.map_id))
	var resident: Dictionary = gathering_nodes[_approach.target].data if gathering else (network.pve.state.character.corpse if recovering else (network.map_rules.portal(String(map_data.map_id)) if transfer else ({"cell":[station.x,station.y]} if ai_travel else network.population.entities[resident_id])))
	var target := Vector2i(resident.cell[0], resident.cell[1])
	# Moving wolves can cross a cell while the challenge is in flight.
	var reach := 1 if gathering or resident.get("kind") == "wolf" else 2
	if absi(cell.x - target.x) + absi(cell.y - target.y) <= reach:
		if finding and actors.has(character_id) and actors[character_id].motion.has_motion(): return
		if not _approach.stopped:
			_approach.stopped = true
			network.stop_moving()
			return
		var request := _approach
		_approach = {}
		if finding: chat_status.text = "已抵达%s。" % String(resident.get("name", "NPC"))
		var action: String = request.action
		if action=="gather":
			_gather_cancel_requested=false;_gather_auto_token="";gathering_panel.present(resident);_gather_confirm();return
		if action == "npc":
			npc_dialog.present(request.target, resident, network.pve)
			return
		if action == "ai_npc":
			npc_dialog.present_ai(request.target,AIWorld.resident(request.target),network.pve.state.get("ai_world",{}),int(_character.get("level",1)),network.pve)
			return
		npc_dialog.approaching = false
		if action=="challenge" and not team.party().is_empty():
			if not team.submit("challenge",request.target):chat_status.text="正在同步队伍，请稍后重试。"
		else:network.pve.submit(action, request.target)
		return
	var best := Vector2i(-1, -1)
	var shortest := 9999
	if finding:
		var path := NpcFinder.route(_motion_grid, cell, target, network.map_rules.exits(String(map_data.map_id)))
		if not path.is_empty(): best = NpcFinder.waypoint(path)
	else:
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var goal: Vector2i = target + offset
			if not _motion_grid.region.has_point(goal) or _motion_grid.is_point_solid(goal): continue
			var path := _motion_grid.get_id_path(cell, goal)
			if not path.is_empty() and path.size() < shortest:
				best = goal
				shortest = path.size()
	if best.x < 0:
		_cancel_approach()
		chat_status.text = "目标不可达，请更换路线。"
	else:
		_approach.stopped = false
		network.move_to(best)
		_mark_destination(best)

func _hero_screen_point() -> Vector2:
	if not actors.has(character_id): return Vector2(160, 216)
	return actors[character_id].root.get_global_transform_with_canvas().origin + image.position

func _refresh_interaction_wait() -> void:
	if not network.pve.pending():
		encounter.hide()
		return
	var command: Dictionary = OnlineAccount.pending_pve.command
	if command.action != "challenge":
		encounter.hide()
		return
	var resident: Dictionary = network.population.entities.get(command.get("target", ""), {})
	encounter.present("challenge", resident.get("name", "妖物"), _hero_screen_point())
	if not network.pve.ready: encounter.set_waiting("连接中断，正在确认交互结果……")

func _cancel_battle_preparation() -> void:
	_battle_load_epoch += 1
	if _battle_resource_request != null: _battle_resource_request.cancel()
	_battle_resource_request = null
	_loading_battle = ""
	_battle_load_failed = false
	if encounter != null: encounter.hide()

func _battle_preparation_current(epoch: int, id: String) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and epoch == _battle_load_epoch and network.pve.ready and network.pve.state.get("battle") is Dictionary and network.pve.state.battle.id == id

func _battle_preparation_failed() -> void:
	_cancel_battle_preparation()
	_battle_load_failed = true
	chat_status.text = "战斗资源读取失败，点击地图重试；战斗进度已由服务器保存。"

func _prepare_battle(snapshot: Dictionary) -> void:
	_cancel_battle_preparation()
	npc_dialog.hide()
	battle_view.hide();solo_battle.hide()
	_set_battle_layout(false)
	screen.chrome.round_label.text = "常规模式"
	screen.hud.show()
	count_label.show()
	var epoch := _battle_load_epoch
	var id: String = snapshot.id
	_loading_battle = id
	encounter.present("challenge", snapshot.enemy.name, _hero_screen_point())
	encounter.set_progress(0.0, "准备战斗图像与场景")
	await get_tree().process_frame
	if not _battle_preparation_current(epoch, id): return
	var c: Dictionary = network.pve.state.character
	var key: String = (["mzs", "mck", "mfs"] if int(c.gender) == 0 else ["wzs", "wck", "wfs"])[int(c.job)]
	var keys: Array[String] = [ShopRules.actor_key(int(c.job),int(c.gender),network.pve.appearance()) if network.pve.state.has("shop") else "hero/" + key, String(snapshot.enemy.art), "effect/flash", BattleDeathPlayback.ART_KEY]
	if snapshot.get("formation") is Dictionary:
		for e in snapshot.formation.enemies:
			if not keys.has(String(e.definition.art)):keys.append(String(e.definition.art))
	keys.append_array(BattleResultView.ART_KEYS)
	keys.append_array(BattleEffects.preload_keys(int(c.job),int(c.school),int(c.level),not network.pve.state.has("skills")))
	var paths: Array[String] = ["res://assets/tiles/original_tiles.png"]
	var metadata_frame:=Time.get_ticks_usec()
	for actor_key in keys:
		var info := OriginalArt.actor_info(actor_key)
		if info.is_empty():
			_battle_preparation_failed()
			return
		if not paths.has(info.texture): paths.append(info.texture)
		var scene_path:=OriginalArt.scene_path(actor_key)
		if not paths.has(scene_path):paths.append(scene_path)
		if Time.get_ticks_usec()-metadata_frame>=4000:
			await get_tree().process_frame;metadata_frame=Time.get_ticks_usec()
			if not _battle_preparation_current(epoch,id):return
	var request := Platform.context.resource_loader.prepare(PackedStringArray(paths), self, epoch,"Resource")
	_battle_resource_request = request
	while not request.is_finished():
		encounter.set_progress(0.75 * request.progress, "准备战斗图像与场景")
		await get_tree().process_frame
		if not _battle_preparation_current(epoch, id):
			request.cancel()
			return
	if not request.result.ok:
		_battle_preparation_failed()
		return
	var frame_started:=Time.get_ticks_usec()
	for index in keys.size():
		if not OriginalArt.is_prepared(keys[index]):
			var prepared := OriginalArt.actor(keys[index]);prepared.free()
		encounter.set_progress(0.75 + 0.20 * float(index + 1) / keys.size(), "准备角色动作与招式")
		if Time.get_ticks_usec()-frame_started>=4000:
			await get_tree().process_frame;frame_started=Time.get_ticks_usec()
		if not _battle_preparation_current(epoch, id): return
	encounter.set_progress(1.0, "准备就绪")
	await get_tree().process_frame
	if not _battle_preparation_current(epoch, id): return
	_battle_resource_request = null
	_loading_battle = ""
	encounter.hide()
	# Use the latest authoritative revision, including receipts arriving while loading.
	_present_battle()

func _present_battle() -> void:
	if network.pve.state.battle.get("formation") is Dictionary:
		battle_view.hide();solo_model.display_ready=true;solo_battle.present()
	else:
		solo_battle.hide();battle_view.present(network.pve)
	screen.chrome.round_label.text = "回合：%d/30" % int(network.pve.state.battle.round)
	_set_battle_layout(true)
	screen.hud.hide()
	count_label.hide()

func _exit_tree() -> void:
	_cancel_battle_preparation()
	_cancel_team_preparation()

func _web_lifecycle(event: String) -> void:
	if event not in ["focus_lost", "suspended"]: return
	_cancel_approach()
	move_target.clear()
	_was_keyboard = false
	if network.world_ready: network.stop_moving()

func _mark_destination(cell: Vector2i) -> void:
	move_target.clear()
	if not network.world_ready or network.pve.active() or network.pve.pending() or not network.entities.has(character_id): return
	var own: Dictionary = network.entities[character_id]
	var origin: Array = own.cell if own.next_cell == null else own.next_cell
	var start := Vector2i(origin[0], origin[1])
	if not _motion_grid.region.has_point(cell) or _motion_grid.is_point_solid(cell): return
	if (cell == start and own.next_cell == null) or _motion_grid.get_id_path(start, cell).is_empty(): return
	move_target.set_destination(cell)
	_target_wait = 0.0
	_target_seen_motion = false

func _update_move_target(delta: float) -> void:
	if not move_target.visible: return
	if not network.world_ready or network.pve.active() or not actors.has(character_id):
		move_target.clear()
		return
	var own: Dictionary = network.entities[character_id]
	# Old idle snapshots must not erase a click awaiting send or acknowledgement.
	if not network._pending_motion.is_empty() or int(own.last_input_seq) < network._input_seq: return
	_target_wait += delta
	var motion: OnlineActorMotion = actors[character_id].motion
	if motion.has_motion():
		_target_seen_motion = true
		return
	if motion.position.distance_to(move_target.position) < 0.5 or _target_seen_motion or _target_wait > 1.0:
		move_target.clear()

func _set_battle_layout(active: bool) -> void:
	screen.chrome.toolbar.visible = not active
	for name_value in ["Reward", "SceneReward13", "Panel11"]: screen.chrome.get_node(name_value).visible = not active
	screen.chrome.round_label.position.x = 205.0 if active else 210.0
	screen.chrome.round_label.size.x = 114.0 if active else 77.0
	screen.chrome.round_label.add_theme_color_override("font_color", Color("294d74") if active else Color("efe82e"))
	chat_panel.position.y = 424.0 if active else 403.0
	expanded_chat.get_node("Shade").size.y = chat_panel.position.y

func _open_expanded_chat() -> void:
	if team_panel.visible:team_panel.dismiss()
	if social_panel.visible:social_panel.dismiss()
	_close_inventory()
	_close_world_map()
	_close_attributes()
	_cancel_approach()
	npc_dialog.hide()
	if network.world_ready: network.stop_moving()
	_was_keyboard = false
	menu.hide()
	details.hide()
	if _loading_battle.is_empty() and not network.pve.pending(): encounter.hide()
	emote_picker.hide()
	Platform.context.text_input.release_focus(chat_input)
	battle_view.set_process_unhandled_key_input(false)
	expanded_chat.open()

func _expanded_chat_dismissed() -> void:
	Platform.context.text_input.release_focus(chat_input)
	battle_view.set_process_unhandled_key_input(true)

func _open_attributes() -> void:
	_close_inventory()
	_close_world_map()
	details.hide()
	if _character.is_empty():
		chat_status.text = "角色数据正在同步，请稍候。"
		return
	attributes.display_online(_character, network.pve.state.get("stats", {}), network.pve.state.get("attributes", {}))
	attributes.show()
	_update_allocation_controls()
	battle_view.set_process_unhandled_key_input(false)

func _close_attributes() -> void:
	if not attributes.visible: return
	Platform.context.text_input.release_focus(attributes.signature)
	attributes.hide()
	battle_view.set_process_unhandled_key_input(true)

func _open_world_map() -> void:
	_close_inventory()
	if (battle_view.visible or solo_battle.visible) or network.pve.active(): return
	details.hide()
	Platform.context.text_input.release_focus(chat_input)
	var own:Dictionary=network.entities.get(character_id,{})
	var cell:=Vector2i(own.cell[0],own.cell[1]) if own.has("cell") else Vector2i(-1,-1)
	world_map.present(String(map_data.map_id),cell,network.pve)
	battle_view.set_process_unhandled_key_input(false)

func _scroll_travel(destination: String) -> void:
	if not network.world_ready or not network.pve.submit("scroll_travel",destination):
		world_map.finish_travel("暂时无法传送，请确认连接、神行符数量和角色状态。")

func _open_shop() -> void:
	if network.pve.state.get("shop",{}).get("version") not in ["shop-v1","shop-v2"] or network.pve.active():
		$Menu/Panel/Title.text = "商城"
		$Menu/Panel/Body.text = "当前服务器尚未开放商店，或正在战斗中。"
		details.show()
		return
	bag_overlay = preload("res://scenes/ui/modal_overlay.tscn").instantiate()
	bag_overlay.z_index = 16
	add_child(bag_overlay)
	shop = preload("res://scenes/ui/shop_panel.tscn").instantiate()
	shop.online_model = network.pve
	bag_overlay.add_child(shop)
	shop.back_requested.connect(_close_inventory)
	battle_view.set_process_unhandled_key_input(false)

func _open_inventory() -> void:
	if network.pve.state.is_empty() or network.pve.active():
		chat_status.text = "请等待角色数据同步，战斗中请使用战斗道具菜单。"
		return
	details.hide()
	bag_overlay = preload("res://scenes/ui/modal_overlay.tscn").instantiate()
	bag_overlay.z_index = 16
	add_child(bag_overlay)
	backpack = preload("res://scenes/ui/inventory.tscn").instantiate()
	backpack.online_model = network.pve
	bag_overlay.add_child(backpack)
	backpack.back_requested.connect(_close_inventory)
	backpack._online_changed()
	battle_view.set_process_unhandled_key_input(false)

func _close_inventory() -> void:
	if bag_overlay != null:
		remove_child(bag_overlay)
		bag_overlay.queue_free()
		battle_view.set_process_unhandled_key_input(true)
	bag_overlay = null
	backpack = null
	shop = null
	ai_panel = null

func _open_ai(section: String = "quests", npc: String = "") -> void:
	if section=="maps":_open_world_map();return
	if section=="quests" and not npc.is_empty():
		_close_inventory();_resident_action("ai_npc",npc);return
	_close_inventory(); _close_world_map()
	if not network.pve.ready or network.pve.active(): return
	if not network.pve.state.has("ai_world"):
		chat_status.text = "当前服务尚未启用AI生成扩展；本分支构建服务后可用。"
		return
	network.stop_moving(); _was_keyboard=false
	details.hide(); menu.hide(); npc_dialog.hide()
	ai_panel = AIWorldPanel.new(); bag_overlay = ai_panel
	ai_panel.present(String(map_data.map_id),network.pve.state.ai_world,int(_character.get("level",1)),npc)
	add_child(ai_panel)
	ai_panel.back_requested.connect(_close_inventory)
	ai_panel.requested.connect(_ai_requested)
	battle_view.set_process_unhandled_key_input(false)

func _ai_requested(action: String, target: String) -> void:
	_close_inventory()
	if not network.pve.ready or network.pve.pending() or network.pve.active(): return
	if action=="ai_talk":
		if target.left(6)!=String(map_data.map_id):_resident_action("ai_travel",target.left(6))
		else:_select_resident(target)
		return
	if action == "ai_track":
		if target.left(6)!=String(map_data.map_id): _resident_action("ai_travel",target.left(6))
		else: _select_resident(target)
		return
	if action!="ai_travel" and target.left(6)!=String(map_data.map_id): _resident_action("ai_travel",target.left(6)); return
	_resident_action(action,target)

func _close_world_map() -> void:
	if not world_map.visible: return
	world_map.dismiss()
	battle_view.set_process_unhandled_key_input(true)

func _can_allocate() -> bool:
	if network == null or not network.world_ready or not network.pve.ready or network.pve.pending() or network.pve.active() or not network.entities.has(character_id): return false
	var own: Dictionary = network.entities[character_id]
	return own.next_cell == null and network._pending_motion.is_empty() and int(own.last_input_seq) >= network._input_seq

func _update_allocation_controls() -> void:
	if not attributes.visible: return
	var hint := "停稳后可加点"
	if network.pve.pending(): hint = "正在保存，请稍候"
	elif not network.world_ready or not network.pve.ready: hint = "重新连接后可加点"
	elif network.pve.active(): hint = "战斗结束后可加点"
	attributes.set_allocation_enabled(_can_allocate(), hint)

func _allocate_attributes(points: Array) -> void:
	if not _can_allocate(): return
	if network.pve.submit("allocate", "", points):
		attributes.set_allocation_enabled(false, "正在保存，请稍候")
		chat_status.text = "正在保存属性点……"
