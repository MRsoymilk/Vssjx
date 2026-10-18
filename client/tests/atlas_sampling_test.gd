extends Node
## Compare actual game atlas frames against independently isolated source pixels.
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
    checks+=1
    if not ok:failures+=1;push_error("ATLAS SAMPLING: "+message)
func _ready()->void:call_deferred("_run")
func _run()->void:
    check(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel"),"Root battle and preview rendering snaps sprite transforms")
    check(get_viewport().snap_2d_transforms_to_pixel,"Root viewport actually applies the project pixel alignment setting")
    var local:SubViewport=load("res://scenes/ui/world_viewport.tscn").instantiate()
    var page:Control=load("res://scenes/ui/online_world_view.tscn").instantiate()
    var online:SubViewport=page.get_node("Viewport");page.remove_child(online);page.free()
    for child in online.get_children():child.free()
    var reference_view:SubViewport=local.duplicate()
    add_child(reference_view);reference_view.size=Vector2i(256,256);reference_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    var reference:=Sprite2D.new();reference.centered=false;reference.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;reference_view.add_child(reference)
    var rendered:=0
    for view in [local,online]:
        check(view.snap_2d_transforms_to_pixel,"Authored local/online world viewport enables pixel alignment")
        add_child(view);view.size=Vector2i(256,256);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
        for key in ["monster/langw","hero/mzs","hero/mzs_w2_c3_h9","hero/wzs_w0_c0_h0"]:
            var actor:=OriginalArt.actor(key);actor.pause();view.add_child(actor)
            var info:=OriginalArt.actor_info(key)
            var visited:={}
            for animation in ["idle","walk","attack","hurt"]:
                if not actor.sprite_frames.has_animation(animation):continue
                actor.animation=animation
                for index in actor.sprite_frames.get_frame_count(animation):
                    actor.frame=index
                    var region:AtlasTexture=actor.sprite_frames.get_frame_texture(animation,index)
                    if visited.has(region.get_instance_id()):continue
                    visited[region.get_instance_id()]=true
                    check(region.filter_clip,"Frames clip to their atlas region: "+key)
                    if DisplayServer.get_name()=="headless":continue
                    var source:=region.atlas.get_image()
                    if source.is_compressed():source.decompress()
                    var isolated:=Image.create(int(info.width),int(info.height),false,Image.FORMAT_RGBA8)
                    isolated.blit_rect(source,Rect2i(region.region),Vector2i(region.margin.position))
                    reference.texture=ImageTexture.create_from_image(isolated);reference.offset=actor.offset
                    for fraction in [0.0,0.25,0.5,0.75]:
                        for facing in [1.0,-1.0]:
                            actor.position=Vector2(128+fraction,210-fraction);reference.position=actor.position;actor.scale.x=facing;reference.scale.x=facing
                            await get_tree().process_frame
                            await RenderingServer.frame_post_draw
                            var actual:Image=view.get_texture().get_image();var expected:Image=reference_view.get_texture().get_image()
                            check(actual.get_data()==expected.get_data(),"Rendered frame matches isolated source: %s %s/%d x=%s facing=%s"%[key,animation,index,str(fraction),str(facing)])
                            rendered+=1
            actor.free()
        view.free()
    reference_view.free()
    print("ATLAS SAMPLING: %d checks, %d failures, %d rendered comparisons"%[checks,failures,rendered])
    get_tree().quit(1 if failures else 0)
