class_name BattleStatusStrip
extends Control
## Read-only status badges: original effect artwork, authored semantic mapping.
signal selected(description:String)
const CATALOG_PATH:="res://assets/ui/battle_status/catalog.json"
static var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH)).icons
var entries:Array=[]
var page:=0
var buttons:Array[Button]=[]
func _init()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	theme=preload("res://scenes/ui/online_pve_theme.tres")
static func harmful(state:Dictionary,dots:Variant=null)->Array:
	var rows:Array=[]
	for id in ["bleed","poison","sleep","silence"]:
		var turns:=int(state.get("enemy_"+id,0))
		# Revised server PVE stores each source independently. Empty dots means expired,
		# even when legacy enemy_bleed/enemy_poison counters still have stale values.
		if dots is Dictionary and id in ["bleed","poison"]:
			turns=0
			for source in dots:
				if String(source).ends_with("/"+id):turns=maxi(turns,int(dots[source][0]))
		if turns>0:rows.append({"id":id,"turns":turns})
	return rows
static func beneficial(state:Dictionary)->Array:
	var rows:Array=[]
	for id in ["regen","defense","crit","reflect_physical","reflect_magic"]:
		if int(state.get(id,0))>0:rows.append({"id":id,"turns":int(state[id])})
	return rows
static func fighter(state:Dictionary,wound:Array=[])->Array:
	var rows:Array=[]
	if not wound.is_empty() and int(wound[0])>0:rows.append({"id":"bleed","turns":int(wound[0])})
	rows.append_array(beneficial(state))
	return rows
func set_statuses(rows:Array)->void:
	if rows==entries:return
	entries=rows.duplicate(true);page=0;_rebuild()
func description(row:Dictionary)->String:
	return "%s · 剩余%d回合"%[catalog[row.id].name,int(row.turns)]
func _rebuild()->void:
	for child in get_children():remove_child(child);child.queue_free()
	buttons.clear();visible=not entries.is_empty()
	var shown:=mini(3,entries.size()-page)
	size=Vector2(shown*18,18)
	for i in shown:
		var overflow:=i==2 and entries.size()-page>3
		var row:Dictionary=entries[page+i]
		var button:=Button.new();button.position=Vector2(i*18,0);button.size=Vector2(17,17);button.focus_mode=Control.FOCUS_NONE;button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;add_child(button);buttons.append(button)
		var bg:=StyleBoxFlat.new();bg.bg_color=Color(0.16,0.15,0.08,0.72);bg.set_border_width_all(1);bg.border_color=Color("c8ac69")
		for state in ["normal","hover","pressed","focus"]:button.add_theme_stylebox_override(state,bg)
		if overflow:
			button.text="+%d"%(entries.size()-page-2);button.add_theme_font_size_override("font_size",8);button.add_theme_color_override("font_color",Color("fff0a7"))
			var details:Array[String]=[]
			for extra in entries.slice(page+2):details.append(description(extra))
			button.tooltip_text="\n".join(details)+"\n点击切换状态"
			button.pressed.connect(func()->void:page+=2;_rebuild())
		else:
			button.tooltip_text=description(row)
			var art:=TextureRect.new();art.texture=load(catalog[row.id].texture);art.position=Vector2(1,1);art.size=Vector2(14,14);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(art)
			var number:=OriginalSceneChrome.label(button,str(int(row.turns)),Rect2(8,8,9,9),8,Color("fff9b0"));number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;number.add_theme_color_override("font_outline_color",Color("262718"));number.add_theme_constant_override("outline_size",1);number.mouse_filter=Control.MOUSE_FILTER_IGNORE
			button.pressed.connect(func()->void:selected.emit(description(row)))
	# The last page returns to the first when its final badge is clicked.
	if page>0 and entries.size()-page<=3 and not buttons.is_empty():
		buttons[-1].tooltip_text+="\n点击返回首组状态"
		buttons[-1].pressed.connect(func()->void:page=0;_rebuild())
