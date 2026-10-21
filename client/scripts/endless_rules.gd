class_name EndlessRules
extends RefCounted
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/endless-v1.json"))
static var catalog_hash:String=FileAccess.get_file_as_string("res://assets/data/endless-v1.json").replace("\r\n","\n").sha256_text()
static func empty()->Dictionary:return {"stage":1,"best":0,"level":0,"in_progress":false}
static func progress(player:Dictionary)->Dictionary:return player.get("endless_state",empty())
static func valid(p:Variant)->bool:
	if not p is Dictionary or not ShopRules._integer(p.get("stage"),1,int(rules.max_stage)+1) or not ShopRules._integer(p.get("best"),0,int(rules.max_stage)) or int(p.best)<int(p.stage)-1 or not ShopRules._integer(p.get("level"),0,60) or not p.get("in_progress") is bool:return false
	return (int(p.stage)==1 and not p.in_progress) if int(p.level)==0 else (int(p.stage)>1 or p.in_progress)
static func valid_view(v:Variant)->bool:return v is Dictionary and v.get("version")=="endless-v1" and v.get("catalog_sha256")==catalog_hash and valid(v.get("progress"))
static func monster(run:Dictionary)->Dictionary:
	if not ShopRules._integer(run.get("stage"),1,int(rules.max_stage)) or not ShopRules._integer(run.get("level"),1,60):return {}
	var level:=int(run.level);var stage:=int(run.stage)
	var d:Dictionary={"id":rules.monster_id,"name":"试炼幻影·第%d层"%stage,"kind":"guardian","art":rules.arts[(stage-1)%4],"cell":rules.npc.cell.duplicate(),"level":level,"gold":int(rules.gold_base)+level*int(rules.gold_per_level),"xp":int(rules.xp_base)+level*int(rules.xp_per_level)}
	for key in ["hp","attack","defense"]:
		var value:=(int(rules[key+"_base"])+level*int(rules[key+"_per_level"]))* (10000+(stage-1)*int(rules[key+"_step_bp"]))/10000
		if value>int(rules.max_stat):return {}
		d[key]=value
	return d
static func begin(p:Dictionary,level:int)->Dictionary:
	if not valid(p):return {"error":"INVALID_ENDLESS_STATE"}
	if p.in_progress:return {"error":"BATTLE_ACTIVE"}
	var run:Dictionary={"stage":int(p.stage),"level":level if int(p.level)==0 else int(p.level)};var d:=monster(run)
	if d.is_empty():return {"error":"ENDLESS_LIMIT"}
	p.level=run.level;p.in_progress=true;return {"run":run,"enemy":d}
static func finish(p:Dictionary,run:Dictionary,victory:bool)->bool:
	if not valid(p) or not p.in_progress or p.stage!=run.stage or p.level!=run.level:return false
	if victory:p.best=maxi(int(p.best),int(run.stage));p.stage=int(run.stage)+1;p.in_progress=false
	else:p.stage=1;p.level=0;p.in_progress=false
	return true
static func recover_local(player:Dictionary)->bool:
	var changed:=false
	if player.has("endless_state") and player.endless_state.in_progress:
		player.endless_state.stage=1;player.endless_state.level=0;player.endless_state.in_progress=false;changed=true
	for entry in player.get("local_characters",{}).get("characters",[]):
		if recover_local(entry.data):changed=true
	return changed
