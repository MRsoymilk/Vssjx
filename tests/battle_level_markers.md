# 联机战斗等级标记跟随

等级原先固定在 HUD 的站位坐标，原版 ANI 攻击位移只移动演员，导致怪物突进时等级留在左侧。

`OnlineBattleView.refresh()` 现在将演员相对站位的实际位移转换到等级标记父节点的坐标空间，再加上场景原有标记位置。双方等级随攻击出击、命中与回位同步；文字保持正向，不继承怪物的镜像或精灵缩放。受击帧自身的贴图偏移不会带动等级抖动。原来的气血条、脚下环隐藏时机及死亡时等级隐藏规则保留。

验证命令：

```sh
godot --headless --path client res://tests/wolf_reaction_test.tscn
godot --path client --rendering-driver opengl3 res://tests/wolf_reaction_test.tscn -- --capture-battle-layers=/absolute/path/follow
godot --headless --path client res://tests/player_ring_test.tscn
godot --headless --path client res://tests/battle_death_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
```

2026-10-17，Windows / Godot 4.7.1：怪物回合测试无界面 765 项、实际渲染 767 项通过；脚下环 279 项、死亡动画 23 项、联机战斗界面 59 项通过。新增断言在修复前复现 201 项失败；覆盖全部四种运行怪物、双方攻击位移、非等比视图缩放与平移、回位、断线取消和新战斗重置。实际截图确认狼反击时等级已移动到狼的上方，不再遗留在左侧站位。

本次未导出或部署 Web 包。
