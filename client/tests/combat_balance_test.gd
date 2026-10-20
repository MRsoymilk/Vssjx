extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("BALANCE: "+text)
func _ready()->void:_run.call_deferred()
func matches(actual:Dictionary,expected:Dictionary)->bool:
	if actual.size()!=expected.size():return false
	for key in expected:
		if not actual.has(key) or actual[key]!=expected[key]:return false
	return true
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true)
	var v:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/balance-v1-vectors.json"))
	for row in v.stats:check(matches(CombatBalance.profile(int(row.job),int(row.level),row.points).value,row.expected),"Shared class/level/attribute vector")
	for row in v.damage:check(matches(CombatBalance.damage(row.input).value,row.expected),"Shared damage, penetration, caps and rounding vector")
	for row in v.ratings:check(CombatBalance.critical_chance(int(row.level),int(row.rating),int(row.bonus_bp)).value==row.expected,"Shared diminishing critical rating")
	for row in v.hit:check(CombatBalance.hit_chance(int(row.level),int(row.hit),int(row.evasion)).value==row.expected,"Shared hit/evasion rating")
	for row in v.aoe:check(CombatBalance.aoe_coefficient(int(row.coefficient_bp),int(row.targets)).value==row.expected,"Shared AoE total budget")
	for row in v.boss:check(CombatBalance.boss_hp(int(row.hp),int(row.members)).value==row.expected,"Shared boss HP budget")
	for bad in [{"level":0},{"attack":-1},{"attack":1000001},{"attack":1.5},{"critical":1},{"reward":999},{"coefficient_bp":30001}]:check(not CombatBalance.damage(bad).ok,"Reject malformed, out-of-range or non-integer input")
	check(not CombatBalance.profile(0,1,[6,0,0,0,0]).ok,"No excess point allocation")
	check(not CombatBalance.profile(3,1,[0,0,0,0,0]).ok,"No unknown class")
	for level in range(1,61):
		var previous:=1000
		for defense in range(0,10001,100):
			var d:Dictionary=CombatBalance.damage({"attack":1000,"defense":defense,"level":level}).value
			check(d.damage<=previous and d.damage>=400,"Defense curve is monotonic, capped and never degenerates to one damage")
			previous=d.damage
		for job in 3:check(CombatBalance.profile(job,level,[level*5,0,0,0,0]).value.available==0,"All class levels retain a valid five-point budget")
	for targets in range(1,6):check(int(CombatBalance.aoe_coefficient(8000,targets).value)*targets<=24000,"Actor count cannot multiply AoE beyond its total budget")
	var server_vectors:=OS.get_environment("SSJX_BALANCE_RUST_VECTORS")
	if not server_vectors.is_empty():
		var corpus:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(server_vectors))
		check(corpus.version==CombatBalance.rules.version and corpus.rules_sha256==FileAccess.get_file_as_string("res://assets/data/balance-v1.json").sha256_text(),"Rust and Godot use identical rule bytes and versions")
		for row in corpus.damage:check(matches(CombatBalance.damage(row.input).value,row.expected),"Real Rust/Godot integer damage parity")
	var panel:=PanelContainer.new();panel.position=Vector2(12,18);panel.size=Vector2(296,440);add_child(panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",14);panel.add_child(column)
	for text in ["数值底座 V1 · 候选规则", "未切换现有战斗／存档", "30级 · 攻击300 · 技能150%", "增伤20% · 目标防御280", "普通伤害 324　暴击 486", "防御指令后伤害 162", "防御减伤上限 60%", "暴击率 5%～50%", "五目标群攻每体48%／总240%", "五人首领总血量 ×4.2", "验证：%d项　失败：%d项"%[checks,failures]]:
		var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",13);column.add_child(label)
	var output:=OS.get_environment("SSJX_BALANCE_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw()
		var image:=get_viewport().get_texture().get_image()
		check(not image.is_empty() and image.save_png(output)==OK,"Actual rendered balance preview is captured")
	check(Game.player==old,"Candidate tests never mutate existing character state")
	print("COMBAT BALANCE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
