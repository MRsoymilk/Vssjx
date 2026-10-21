class_name TeamLootRules
extends RefCounted
## Read-only validation and presentation; never rolls a die on the client.
static func pending(pool:Dictionary)->bool:return pool.get("drops",[]).any(func(d:Dictionary)->bool:return not d.delivered)
static func valid(pool:Variant,fighters:Array)->bool:
	if not pool is Dictionary or not OnlinePve.integer(pool.get("deadline_ms"),1,253402300799999) or not OnlinePve.integer(pool.get("revision"),0,1000) or not pool.get("members") is Array or not pool.get("drops") is Array or pool.drops.size()>2 or pool.members.size()!=fighters.size():return false
	var members:={};var ids:={}
	for f in fighters:members[f.id]=f
	var seen:={}
	for id in pool.members:
		if not id is String or not members.has(id) or seen.has(id):return false
		seen[id]=true
	for d in pool.drops:
		if not d is Dictionary or not d.has("winner") or not d.get("item") is Dictionary or not d.get("eligible") is Array or not d.get("choices") is Dictionary or not d.get("tie_scores") is Dictionary or not d.get("resolved") is bool or not d.get("delivered") is bool:return false
		var valid_for_any:=false;var eligible:={}
		for f in fighters:
			if LootRules.valid_item(d.item,int(f.job),int(f.gender)):
				valid_for_any=true
				if int(d.item.level)<=int(f.level):eligible[f.id]=true
		if not valid_for_any or d.item.legacy or d.item.equipped or ids.has(d.item.id):return false
		ids[d.item.id]=true
		if d.eligible.size()!=eligible.size():return false
		var eligible_seen:={}
		for id in d.eligible:
			if not id is String or not eligible.has(id) or eligible_seen.has(id):return false
			eligible_seen[id]=true
		var high:=0;var scores:={}
		for id in d.choices:
			if not members.has(id):return false
			var score:Variant=d.choices[id]
			if score!=null:
				if not eligible.has(id) or not OnlinePve.integer(score,1,100):return false
				high=maxi(high,int(score))
		for id in members:
			if not eligible.has(id) and (not d.choices.has(id) or d.choices[id]!=null):return false
		for id in d.tie_scores:
			var score:Variant=d.tie_scores[id]
			if not d.choices.has(id) or d.choices[id]==null or int(d.choices[id])!=high or not OnlinePve.integer(score,1,100) or scores.has(int(score)):return false
			scores[int(score)]=true
		if not d.resolved:
			if d.delivered or d.get("winner")!=null or not d.tie_scores.is_empty() or d.choices.size()>=members.size():return false
		else:
			if d.choices.size()!=members.size() or not d.delivered:return false
			var winner:Variant=d.get("winner")
			if high==0:
				if winner!=null or not d.tie_scores.is_empty():return false
			else:
				if not winner is String or not eligible.has(winner) or not d.choices.has(winner) or d.choices[winner]==null or int(d.choices[winner])!=high:return false
				var tied:Array=d.choices.keys().filter(func(id:String)->bool:return d.choices[id]!=null and int(d.choices[id])==high)
				if tied.size()>1:
					if d.tie_scores.size()!=tied.size() or not d.tie_scores.has(winner):return false
					for score in d.tie_scores.values():
						if int(score)>int(d.tie_scores[winner]):return false
				elif not d.tie_scores.is_empty():return false
	return true
