extends Node
var checks:=0
func check(value:bool)->void:
	checks+=1
	assert(value,"Monster combat contract failed: %d"%checks)
func _ready()->void:
	var d:Dictionary=SharedWorldMap.population("ancient_ruins").filter(func(e:Dictionary)->bool:return e.id=="boss")[0]
	for roll in 100:
		check(MonsterCombat.solo_count(roll)==(1 if roll<60 else (2 if roll<88 else 3)))
	check(MonsterCombat.plan(d,0,false,false).hits==2)
	check(MonsterCombat.plan(d,30,false,false).all)
	check(not MonsterCombat.plan(d,30,false,true).all)
	check(MonsterCombat.plan(d,50,false,false).bleed)
	check(MonsterCombat.critical(d,100,14)=={"damage":150,"critical":true})
	check(MonsterCombat.critical(d,100,15)=={"damage":100,"critical":false})
	check(MonsterCombat.critical(d,0,0)=={"damage":0,"critical":false})
	print("MONSTER COMBAT: %d checks, 0 failures"%checks)
	get_tree().quit()
