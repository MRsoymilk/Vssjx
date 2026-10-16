# 怪物攻击位移与朝向修复

问题：管理页选择`attack`时，狼向后滑动、转头，再跳回原位；同样的游戏图集用于离线与联机战斗。

原因：`langw.ani`的6～11号组合带有旧客户端的整身水平位移，12号组合则使用水平镜像身体。其他已接入怪物也包含冲刺位移、镜像帧；部分动作以前依赖通用序列下标回退，未显式选取待机/行走/攻击序列。

## 改动范围

- `tools/import_assets.py`只对4种已审核的游戏图集（`langw`、`xt1`、`hs1`、`nt1`）移除整身水平位移。以主身体原始第0帧的中心作为角色锚点，保留垂直起伏与局部肢体动作。
- 对反向组合整体镜像，身体、武器和特效一起调整，使所有游戏帧保持原生朝向。外层角色节点仍负责游戏里的左右朝向和位移。
- 为4种怪物明确选择待机、行走和攻击序列；原有攻击顺序、动作帧与持续时间保留，攻击仍只播放一次，结束回到待机。
- 只重新生成4张游戏PNG及其4份元数据。`analysis/animations`与`client/assets/admin/monsters`原包归档的组合、原始偏移、镜像、序列和图集字节保持原样。管理页“已接入”角色与游戏使用修正版，原包编号序列仍可用于分析。
- 原有v1基准保留；演员目录回归改为允许这4种怪物已审核的尺寸、锚点及动作选择变化，并继续验证其他图集字节不变。新基准只记录本次允许的字段覆盖。

## 验证

```sh
python -m unittest discover -s tests -p 'test_monster_motion.py'
python -m unittest discover -s tests -p 'test_actor*.py'
godot --headless --path client res://tests/actor_catalog_test.tscn
godot --path client res://tests/monster_attack_test.tscn -- --capture=/absolute/path/monster-attacks-fixed.png
godot --headless --path client res://tests/data_browser_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
```

像素检查不只验证序列名：对每个待机、行走、攻击组合，在固定锚点取主身体像素，与未镜像原图直接比对；真实朝向匹配必须显著高于镜像模板，以抓住漂移和转向回归。另检查原包归档不变、生成过程不修改原ANI、运行图集像素和元数据可重建；PNG比较使用RGBA像素，避免不同压缩库把相同图像压成不同文件字节导致误报。

Godot专项覆盖4种怪物、左右两种朝向、攻击Atlas区域和帧数、一次攻击后回到动态待机、节点位置/朝向不变与玩家状态不变。实际渲染截图列出待机、攻击开始、中段、结束，共32种姿态；已目视核对身体位置与朝向。

2026-10-16，Windows / Godot 4.7.1：像素与导出专项3项、演员目录/角色导入15项、工程资源路径6项通过；Godot怪物实际渲染130项、演员缓存50项、联机战斗界面28项、管理页9575项通过。本轮没有修改服务端或战斗规则。

已运行的游戏进程可能仍缓存旧SpriteFrames及元数据，重新运行游戏或管理页后使用新图集。
