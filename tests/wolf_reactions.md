# 山狼攻击与受击效果分离

用户反馈：单独预览山狼`attack`时，嘴部出现星形受击效果。上一轮修正了整身位移和镜像，但保留了原组合中的`tx38`星形层，所以攻击仍像同时受击。

## 修改

- 保留原18个运行组合及其`source_N`序列，新增18～20号派生组合：复制原6～8号动作姿态，只移除`tx38`效果层。`attack`用这些无星形效果的派生组合替换对应帧，其他攻击姿态、顺序、持续时间、锚点与朝向保持。
- `hurt`独立使用原6～8号有星形效果的组合，是一次性受击动画，结束回到`idle`。元数据`derived_frames`记录每个新增组合的来源及移除层；原始ANI和管理页原包归档未修改。本次动作命名属于重建版表现规则，不声称恢复了原服全部状态语义。
- 离线战斗在玩家造成伤害时播放山狼`hurt`，随后沿原有回合流程播放反击。
- 联机战斗比较前后权威血量，实际掉血才播放`hurt`；反击延后至玩家动作及受击完成。被击败不反击；断线取消排队反击；新战斗清理旧计时。结果与伤害仍来自服务端，本轮只调整表现时序。
- 其他怪物的攻击特效不作统一删除，以免误去掉其自身施法效果。

## 验证

```sh
python -m unittest discover -s tests -p 'test_monster_motion.py'
python -m unittest discover -s tests -p 'test_actor*.py'
godot --headless --path client res://tests/monster_attack_test.tscn
godot --path client res://tests/wolf_reaction_test.tscn -- --capture=/absolute/path/wolf-attack-hurt-separated.png
godot --headless --path client res://tests/online_pve_test.tscn
godot --headless --path client res://tests/test_runner.tscn
godot --headless --path client res://tests/data_browser_test.tscn
```

像素回归直接检查运行图集：所有攻击帧没有金黄色星形像素，3个受击帧保留星形像素；攻击/受击使用不同组合。派生帧按`source_frame`追溯，在固定锚点匹配主身体原图，保留上一轮对漂移和翻向的检查。原归档哈希与原序列保持一致，重新导出的RGBA像素与元数据一致。

2026-10-16，Windows / Godot 4.7.1：Python怪物专项4项、演员/导入15项、资源路径6项通过；Godot怪物动作135项、受击/反击时序实际渲染11项、联机战斗28项、离线主流程383项、管理页9575项通过。截图已目视确认左右两种朝向下`attack`无星形、`hurt`有星形。新增测试直接覆盖断线、新战斗、无伤害和击败后的排队行为。

已有进程可能缓存旧元数据与SpriteFrames，需要重新运行游戏或管理页。
