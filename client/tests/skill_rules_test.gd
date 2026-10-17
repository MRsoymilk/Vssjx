extends Node
const RULES=preload("res://scripts/skill_rules.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("SKILLS: "+message)
func _ready()->void:
	var vectors:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/skills_golden.json"))
	check(vectors.size()==33,"All 30 reference skills plus three legacy skills")
	for vector in vectors:
		var skill:Dictionary=RULES.item(vector.id)
		var state:Dictionary=RULES.new_state(int(skill.job),maxi(0,int(skill.school)),60,10)
		RULES.reset_turn(state)
		var cast:Dictionary=RULES.cast(skill,state,{"hp":1000,"mp":400,"attack":100,"defense":20},100,200,5,0)
		var after:Dictionary=RULES.after_player(state,int(cast.hp),1000)
		var hit:Vector2i=RULES.enemy_hit(state,100,false)
		RULES.end_turn(state)
		check(after.hp==vector.hp and cast.mp==vector.mp and cast.damage==vector.damage and after.damage==vector.dot,"Cross-language player effect "+skill.id)
		check(hit.x==int(vector.incoming) and hit.y==int(vector.reflected),"Cross-language defense/reflection "+skill.id)
		check(state.size()==vector.state.size() and state.keys().all(func(key:String)->bool:return state[key]==vector.state.get(key)),"Cross-language complete status "+skill.id)
		check(not RULES.check(skill.id,(int(skill.job)+1)%3,maxi(0,int(skill.school)),60).is_empty(),"Wrong class rejected "+skill.id)
		if int(skill.school)>=0:check(not RULES.check(skill.id,int(skill.job),(int(skill.school)+1)%3,60).is_empty(),"Wrong school rejected "+skill.id)
		if int(skill.unlock_level)>1:check(not RULES.check(skill.id,int(skill.job),maxi(0,int(skill.school)),int(skill.unlock_level)-1).is_empty(),"Level gating "+skill.id)
	print("SKILLS: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
