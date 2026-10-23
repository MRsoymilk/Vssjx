extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("LISHI REFLECTION: "+text)
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true)
	Game.new_player("反弹测试",0,3,0);Game.player.level=60;Game.player.hp=10000;Game.player.mp=400
	for own_attack in [120,240]:
		for enemy_attack in [50,500]:
			for active in [false,true]:
				var source:Dictionary=SharedWorldMap.population("qingyun_trail")[1].duplicate(true);source.hp=10000;source.attack=enemy_attack
				var stats:={"hp":10000,"mp":400,"attack":own_attack,"defense":20}
				var effects:Dictionary=SkillRules.new_state(0,3,60)
				effects.defense=2;effects.defense_percent=50
				if active:effects.reflect_physical=2;effects.physical_percent=int(SkillRules.item("sheet_011").value)
				var expected:int=own_attack*(60 if active else 20)/100+(0 if active else 6)
				var legacy:=ShushanBattle.new(source);legacy.enemy=source.duplicate(true);legacy.enemy_hp=10000;legacy.frozen_stats=stats;legacy.skills=effects.duplicate(true);legacy.guarding=not active;legacy.phase="enemy"
				var result:=legacy.resolve_enemy()
				check(result.reflected==expected and legacy.enemy_hp==10000-expected,"Legacy offline battle uses own attack %d, not enemy attack %d"%[own_attack,enemy_attack])
				var formation:=SoloEncounter.new();formation.start([source]);formation.engine.frozen_stats=stats;formation.engine.skills=effects.duplicate(true);formation.engine.guarding=not active
				formation.state.enemies[0].definition=source.duplicate(true);formation.state.enemies[0].hp=10000
				formation._enemy_round()
				check(formation.state.enemies[0].hp==10000-expected,"Offline formation uses defender attack and keeps guard bonus")
	Game.player=old
	print("LISHI REFLECTION CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
