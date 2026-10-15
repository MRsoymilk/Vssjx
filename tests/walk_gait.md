# 人物行走步伐修正

本轮对应“像倒着走”的动画反馈。运行时曾按合成帧编号递增播放最后六帧，合成帧的编号却与向前行走的支撑/摆腿顺序相反。例如男力士依次播放腿部素材5、4、3、2、1、0，着地脚向身体前方滑动，产生倒退观感。

现在在导入器中明确向前步伐顺序，同步更新六种角色及其创建预览的`playback.walk`。完整合成帧一起重排，使头部起伏、腿、武器保持原有配合；左右镜像共用同一套步伐。单人和多人均通过`OriginalArt.actor()`使用这套`AnimatedSprite2D`帧资源。原始ANI编排、图集像素、idle与攻击帧保留；资源重新生成会得到相同修正。

## 验证

`test_actor_import.py`校验六种角色的腿部相位（不能把各套素材的子帧编号简单排序），并追踪男力士图集中红色鞋底的像素：跨循环边界的支撑阶段，相对身体的横坐标为-5.889、-1.125、0.889，符合向左行走时支撑脚向右移动的关系。旧顺序无法通过此检查。

```sh
python -m unittest discover -s tests -p 'test_*.py'
godot --headless --path client res://tests/motion_regression.tscn
godot --headless --path client res://tests/movement_control_test.tscn
godot --headless --path client res://tests/idle_regression.tscn
godot --headless --path client res://tests/click_motion_regression.tscn
godot --headless --path client res://tests/test_runner.tscn
```

本次结果：Python 33项通过、1项跳过，含导入器重新生成一致性与图集原样校验；Godot六角色四方向移动6018项、移动控制35项、待机66项、连续点击776项、单人整流程383项、角色资源50项通过。

实际OpenGL录制六种角色各72帧，包含待机、向右、向左和停下，共432帧。使用已有`motion_smoke.tscn`，`SSJX_MOTION_PATH`指定已有输出目录；可设置`SSJX_MOTION_VARIANT=0..5`选择力士男/女、侠客男/女、隐者男/女，默认仍为男侠客。该录制为本地实际引擎画面，多人通过相同资源及移动显示回归验证；本轮不包含真实数据库双客户端联调。
