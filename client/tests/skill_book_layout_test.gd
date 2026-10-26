extends Node
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func settle()->void:
	for frame in 3:await get_tree().process_frame
func capture(name_value:String)->void:
	var directory:=OS.get_environment("SSJX_SKILL_BOOK_CAPTURE")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await settle();RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(directory.path_join(name_value+".png"))==OK,"Rendered "+name_value)
func layout(book:SkillBook)->void:
	var paper:Rect2=book.get_node("DetailPaper").get_global_rect()
	var previous_end:=paper.position.y
	for path in ["SkillName","Availability","DescriptionScroll","CombatMeta","Training","TrainingProgress"]:
		var control:Control=book.get_node(path)
		if not control.visible:continue
		check(paper.encloses(control.get_global_rect()),"Detail field fits its paper: "+path)
		check(control.get_global_rect().position.y>=previous_end,"Detail fields do not overlap: "+path)
		previous_end=control.get_global_rect().end.y
	check(book.get_node("Provenance").get_global_rect().end.y<book.get_node("ListPaper").get_global_rect().position.y,"Character unlock summary stays above the list")
	check(previous_end<book.get_node("GrowthHint").get_global_rect().position.y,"Details do not spill into the bottom bar")
	check(book.get_node("GrowthHint").get_global_rect().end.x<=260,"Training hint leaves room for the return button")
	check(not book.get_node("Points").visible and not book.get_node("Upgrade").visible and not book.get_node("NextInfo").visible,"Unused points and manual buttons are hidden")
func _ready()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true)
	Game.new_player("技能界面",0,3);Game.player.level=50;Game.restore()
	var page:OriginalCharacterAttributes=load("res://scenes/ui/character_attributes.tscn").instantiate();add_child(page);page.select_tab(2)
	var book:SkillBook=page.content.get_node("SkillBook")
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return s.id=="legacy_0"));await settle();layout(book)
	check(book.get_node("SkillCatalog").size.y==168 and book.get_node("SkillCatalog").scroll_vertical%28==0,"Programmatic selection keeps whole rows visible without clipped text at the top")
	check(not book.detail.text.contains("兼容") and book.get_node("CombatMeta").text.contains("灵力9点"),"Player-facing description uses a short effect and fixed mana")
	check(book.get_node("Training").text.contains("0/20") and book.get_node("TrainingProgress").value==0,"Fresh skill displays actual training")
	await capture("skill-book-basic")
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_010"));await settle();layout(book)
	check(book.detail.text.contains("35%") and book.get_node("CombatMeta").text.contains("无冷却"),"Long control effect retains its chance and separate cooldown")
	var description_scroll:ScrollContainer=book.get_node("DescriptionScroll")
	if description_scroll.get_v_scroll_bar().visible:
		description_scroll.scroll_vertical=999;await settle()
		check(description_scroll.scroll_vertical>0,"Long effects remain scrollable inside their own clipped area")
	await capture("skill-book-long-effect")
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return int(s.unlock_level)>50));await settle();layout(book)
	check(book.get_node("SkillRank").text=="未解锁" and not book.get_node("TrainingProgress").visible,"Locked skill does not show a usable rank or training bar")
	check(book.rows.get_child(book.selected_index).get_node("Rank").text.contains("级解锁"),"Locked list row explains its required level")
	await capture("skill-book-locked")
	Game.player.level=60;Game.player.skill_proficiency={"sheet_010":280};book.present(Game.player,true)
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_010"));await settle();layout(book)
	check(book.get_node("SkillRank").text=="技能15/15" and book.get_node("Availability").text.contains("3阶段特效"),"Maximum skill rank and resource stage are separate and accurate")
	check(book.get_node("TrainingProgress").value==20 and book.get_node("GrowthHint").text.contains("最高等级"),"Maximum training is full and does not promise another level")
	page.select_tab(3);book=page.content.get_node("SkillBook");await settle();layout(book)
	check(book.get_node("Availability").text.contains("已生效") and not book.get_node("TrainingProgress").visible and book.get_node("CombatMeta").text.contains("不消耗灵力"),"Passive skills have active status without active-skill training")
	await capture("skill-book-passive")
	Game.player.job=1;page.select_tab(3);book=page.content.get_node("SkillBook");await settle()
	check(book.items.is_empty() and book.get_node("Label0").visible and book.detail.text.is_empty(),"Empty passive page has one clear empty state")
	page.queue_free();await settle();Game.player=old
	print("SKILL BOOK LAYOUT: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
