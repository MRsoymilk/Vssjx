extends Node
const RULES=preload("res://scripts/skill_rules.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("SKILLS: "+message)
func _ready()->void:
	var vectors:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/skills_golden.json"))
	check(vectors.size()==37,"All reference, user-added and compatibility skills")
	for vector in vectors:
		var skill:Dictionary=RULES.item(vector.id)
		var state:Dictionary=RULES.new_state(int(skill.job),maxi(0,int(skill.school)),60,10)
		RULES.reset_turn(state)
		var cast:Dictionary=RULES.cast(skill,state,{"hp":1000,"mp":400,"attack":100,"defense":20},100,200,5,0)
		var after:Dictionary=RULES.after_player(state,int(cast.hp),1000)
		var hit:Vector2i=RULES.enemy_hit(state,100,100,false)
		RULES.end_turn(state)
		check(after.hp==vector.hp and cast.mp==vector.mp and cast.damage==vector.damage and after.damage==vector.dot,"Cross-language player effect "+skill.id)
		check(hit.x==int(vector.incoming) and hit.y==int(vector.reflected),"Cross-language defense/reflection "+skill.id)
		check(state.size()==vector.state.size() and state.keys().all(func(key:String)->bool:return state[key]==vector.state.get(key)),"Cross-language complete status "+skill.id)
		check(not RULES.check(skill.id,(int(skill.job)+1)%3,maxi(0,int(skill.school)),60).is_empty(),"Wrong class rejected "+skill.id)
		for school in 4:check(RULES.check(skill.id,int(skill.job),school,60)==("" if skill.active else "PASSIVE_SKILL"),"School does not restrict job skill "+skill.id)
		if int(skill.unlock_level)>1:check(not RULES.check(skill.id,int(skill.job),maxi(0,int(skill.school)),int(skill.unlock_level)-1).is_empty(),"Level gating "+skill.id)
	for job in 3:
		for level in [1,5,15,25,35,45,50,55,60]:
			for school in 3:
				check(RULES.list_for(job,school,level)==RULES.list_for(job,SchoolRules.UNJOINED,level),"Every school and unjoined identity share the same job/level skill pool")
	var reflection:Dictionary=RULES.new_state(0,3,60)
	for magical in [false,true]:
		for incoming in [1,50,5000]:
			check(RULES.enemy_hit(reflection,incoming,120,magical)==Vector2i(incoming,24),"Reflection uses own attack rather than incoming damage")
			check(RULES.enemy_hit(reflection,incoming,240,magical)==Vector2i(incoming,48),"Increasing own attack increases reflection")
	reflection.reflect_physical=2;reflection.physical_percent=60;reflection.reflect_magic=2;reflection.magic_percent=60
	reflection.defense=2;reflection.defense_percent=50
	for magical in [false,true]:
		check(RULES.enemy_hit(reflection,50,120,magical)==Vector2i(25,72),"Defense does not weaken own-attack reflection")
		check(RULES.enemy_hit(reflection,5000,120,magical)==Vector2i(2500,72),"Stronger enemy cannot inflate reflection")
		check(RULES.enemy_hit(reflection,50,119,magical)==Vector2i(25,71),"Reflection uses matching integer rounding")
		check(RULES.enemy_hit(reflection,0,120,magical)==Vector2i.ZERO,"No reflection on a miss or zero incoming hit")
		check(RULES.enemy_hit(reflection,50,0,magical)==Vector2i(25,0),"Zero attack cannot gain damage from the attacker")
	for id in ["sheet_011","sheet_033"]:
		var skill:Dictionary=RULES.item(id);var magical:bool=skill.effect=="reflect_magic"
		var state:Dictionary=RULES.new_state(0,3,60)
		check(skill.value==60 and skill.duration==2,"Active reflection catalog uses 60% for two turns")
		RULES.cast(skill,state,{"hp":1000,"mp":400,"attack":120,"defense":20},100,200,0,99)
		check(RULES.enemy_hit(state,500,120,magical)==Vector2i(500,72),"Actual cast uses 60%, not 60% plus passive 20%")
		check(RULES.enemy_hit(state,500,120,not magical)==Vector2i(500,24),"Other incoming type retains passive reflection")
		RULES.end_turn(state)
		check(RULES.enemy_hit(state,500,120,magical)==Vector2i(500,72),"Active reflection remains for the second turn")
		RULES.end_turn(state)
		check(RULES.enemy_hit(state,500,120,magical)==Vector2i(500,24),"Expired active reflection returns to passive 20%")
	print("SKILLS: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
