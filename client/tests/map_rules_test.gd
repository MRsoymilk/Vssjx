extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("MAP RULES: "+text)
func _ready()->void:
	var model:=OnlineMapRules.new();var map:=SharedWorldMap.load_data();var people:Array=[]
	for p in SharedWorldMap.population("qingyun_trail"):people.append({"id":p.id,"cell":p.cell,"enabled":true,"respawn_seconds":30})
	var portals:Array=[]
	for p in SharedWorldMap.exits("qingyun_trail"):
		var v:Dictionary=p.duplicate(true);v.id="ruins_gate" if v.get("legacy",false) else "ai_waystone";v.enabled=true;v.legacy=v.get("legacy",false);v.cells=[v.cell];v.arrival=null;portals.append(v)
	var nodes:=GatheringRules.nodes_for("qingyun_trail")
	for n in nodes:n.enabled=true
	var packet:={"version":1,"map_id":"qingyun_trail","revision":"1","rules":{"entry_enabled":true,"spawn":map.spawn,"station":[3,16],"station_enabled":true,"residents":people,"portals":portals,"gathering":nodes}}
	check(model.receive(packet,"qingyun_trail"),"Typed operational configuration accepts bundled identities")
	check(model.receive(packet,"qingyun_trail"),"Identical revision is idempotent")
	var bad:Dictionary=packet.duplicate(true);bad.rules.spawn=[-1,0]
	check(not model.receive(bad,"qingyun_trail"),"Out-of-range cells rejected")
	bad=packet.duplicate(true);bad.rules.residents[0].id="forged"
	check(not model.receive(bad,"qingyun_trail"),"Unknown asset identities rejected")
	bad=packet.duplicate(true);bad.rules.residents[1].id=bad.rules.residents[0].id
	check(not model.receive(bad,"qingyun_trail"),"Duplicate identities rejected")
	bad=packet.duplicate(true);bad.rules.portals[0].target_map="missing"
	check(not model.receive(bad,"qingyun_trail"),"Unknown destinations rejected")
	bad=packet.duplicate(true);bad.rules.residents[0].respawn_seconds=86401
	check(not model.receive(bad,"qingyun_trail"),"Respawn deadline remains bounded")
	bad=packet.duplicate(true);bad.rules.gathering[0].max_quantity=999
	check(not model.receive(bad,"qingyun_trail"),"Gathering yield bounds retained")
	bad=packet.duplicate(true);bad.rules.portals[0].enabled=false
	check(not model.receive(bad,"qingyun_trail"),"Same revision cannot silently replace different content")
	bad.revision="2";check(model.receive(bad,"qingyun_trail") and model.portal("qingyun_trail").is_empty(),"New revision can disable portal without fallback to static gate")
	check(model.receive(packet,"qingyun_trail") and model.revision==2 and model.portal("qingyun_trail").is_empty(),"Stale operational snapshot cannot roll back active revision")
	check(model.exit_at("qingyun_trail",Vector2i(28,16)).is_empty(),"Disabled gate is not an automatic transfer trigger")
	check(SharedWorldMap.exit_at("qingyun_trail",Vector2i(28,16)).target_map=="ancient_ruins","Offline portal behavior remains unchanged")
	model.clear();check(model.portal("qingyun_trail").id=="ruins_gate","Older server can use packaged portal helpers")
	print("MAP RULES CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
