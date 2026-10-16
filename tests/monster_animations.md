# 怪物动画全量检查与运行时修正

## 范围

- 全部原包 ANI：117 份、142 份图像成员、3133 个合成帧、969 组序列。
- 校验文件来源、归档完整性、图片引用、变换编号、帧引用、时长、图集尺寸与 PNG 完整性。
- 逐序列记录特效来源、身体标志的覆盖率／方向／横向位移；这些观测不直接指定动作语义。
- 当前 4 组运行时怪物全部验证：固定锚点／方向、循环不播放战斗特效、攻击与受击独立。
- 非山狼的受击采用独立中性姿势配合现有命中特效，明确标注为重建表现。
- 原包图集、原始图层／序列／未知尾部数据不变；其余 113 份的动作语义保持未指定。

## 复现

```text
python tools/audit_monster_animations.py
python -m unittest discover -s tests -p "test_monster*.py"
python -m unittest discover -s tests -p "test_actor*.py"
python -m unittest discover -s tests -p "test_project_layout.py"
godot --headless --path client --editor --import --quit
godot --headless --path client res://tests/monster_attack_test.tscn
godot --headless --path client res://tests/wolf_reaction_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
godot --headless --path client res://tests/data_browser_test.tscn
```

`wolf_reaction_test` 已扩展到全部注册的运行时怪物，保留入口名兼容已有调用。
窗口渲染验证可给该场景增加 `-- --capture=<绝对路径>.png`，生成 4 组怪物双面向的攻击／受击／待机对照。
重新生成报告后，管理页每份原包怪物的「动画检查」显示逐序列观测及接入状态；
原包 `source_N` 保留原始表现，游戏动作从「已接入」条目预览。

## 2026-10-16 验证记录

Windows，Python 3.11，Godot 4.7.1：

- 全量检查结构错误数：0；报告重新生成与发布文件一致。
- Python：怪物检查 9 项、角色回归 15 项、项目布局 6 项，全部通过。
- Godot 怪物动作：153 项；4 组受击／反击时序：38 项；联网战斗界面：28 项；
  数据管理页：9809 项；完整玩法回归：383 项，全部通过。
- 实际 OpenGL 窗口渲染对照：39 项，通过；双面向下攻击、受击、待机独立显示。
- 没有执行 Linux 图形验证；本次不宣称已在 Linux 上运行测试。
