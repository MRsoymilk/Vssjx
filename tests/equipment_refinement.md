# 新增套装像素精修

## 第一阶段：赤翎破军

2026-10-23，按原版像素精修方向整理骨甲、暗甲与赤红饰件的明暗关系，处理上缘细高光，统一五张原生部件与十个物品图标。实际启用的自定义头部也独立精修，并保留编辑器保存的两个 `[0,2]` 偏移。

`tools/refine_equipment_pixels.py` 从 `analysis/ai-generated/equipment/pixel-refinement/inputs/` 的不可变原始像素重建。头部脸区、裸露肤色、下发／颈部附件保持原像素；部件不缩放、不改透明轮廓。自定义头部以内容寻址生成新图片，原编辑图片保留。输入／输出摘要及适用套装分别记录在 `baseline.json`、`refinement.json`，源导入报告同步正式纹理摘要。

- 资源回归：骨甲幽光5项通过。
- 真实人物合成器前后比对：14项通过，验证所有姿势的完整透明遮罩、帧区域、时序与战斗锚点一致；覆盖实际编辑器头部。
- 原装备专项：Xvfb＋Mesa OpenGL ES实际渲染496项通过，含商城、地图、背包、管理试穿、混搭与保存恢复。
- 16张纹理可从输入逐字节复现，编辑器导入及 `git diff --check` 通过。
- 已查看四种动作合成对照及实际商城截图。对照：`/tmp/opencode/equipment-refinement/scarlet-before-after.png`；游戏截图：同目录 `sample-ui/`。

```sh
python3 -B tools/refine_equipment_pixels.py --sets boneglow/wzs --check
python3 -B -m unittest discover -s tests -p test_boneglow_assets.py -v
godot --headless --path client res://tests/equipment_refinement_test.tscn
SSJX_EQUIPMENT_GAME_CAPTURE=/tmp/opencode/equipment-refinement/sample-ui \
  SSJX_OFFSCREEN_SCREEN=1600x1000x24 \
  XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
  python3 tests/run_offscreen.py --path client --rendering-driver opengl3_es \
  res://tests/boneglow_equipment_test.tscn
```

重建时省略 `--check`。`--snapshot` 仅用于首次登记尚未精修套装的输入，已有输入不覆盖；每次重建先核对当前正式纹理及编辑器覆盖，避免覆盖额外修改。原导入器仍负责原生产稿的拆分，精修由本工具作为后处理执行。

## 第二阶段：推广到三个系列18套

2026-10-23，完成骨甲幽光、冥林异装、初号机各六角色，共90张原生部件、180个图标及1张正在使用的编辑器头部覆盖。

- 骨甲幽光：按六套主题整理骨白、暗甲、红／紫／冰青／玉色饰件，提亮上缘材质细节。
- 冥林异装：统一暗铁、旧金与骨质明暗，收敛绿色高亮，保留骨面、兜帽和火焰发冠各自的轮廓与主题。
- 初号机：加深紫甲阴影并区分力士、侠客、隐者的玉绿／银绿／浅玉点缀；在32×32像素格上重绘54个非武器图标。衣甲为重甲、轻衣、法袍三种结构，冠饰采用不同玉饰造型，戒指、项链、腰佩各自可辨。
- 原生图层遮罩、帧布局、时序、握持与战斗锚点保持一致；道具目录、物品ID、价格、玩法属性和外观编码没有变动。

### 最终验证

| 检查 | 结果 |
| --- | --- |
| 全系列原生合成前后比对 | 397项通过，包含156次动作对照PNG写入；覆盖实际生效的自定义头部 |
| 骨甲幽光实际OpenGL ES装备专项 | 496项通过 |
| 冥林异装实际OpenGL ES装备专项 | 496项通过 |
| 初号机实际OpenGL ES装备专项 | 496项通过 |
| 初号机原版人体／接缝回归 | 62项通过 |
| 三系列资源与原破天斧资源 | 20项适用检查通过；3项仅针对骨甲幽光的继承测试在冥林系列按原规则跳过 |
| 原商城目录及原包像素 | 5项通过 |
| 可复现性 | 271张正式纹理从不可变输入重建后逐字节一致 |
| 编辑器导入、`git diff --check` | 通过 |

完整帧透明遮罩与元数据由专项逐项检查。人工查看三个系列18个角色的待机前后对照、各原生动作首步、实际商城及背包；非隐者没有原生施法动作，审阅图明确标注。联机外观编码走原测试中的消息接收分支，本轮没有新跑真实服务端专项。

```sh
python3 -B tools/refine_equipment_pixels.py --check
python3 -B -m unittest discover -s tests -p test_boneglow_assets.py -v
python3 -B -m unittest discover -s tests -p test_gravebloom_assets.py -v
python3 -B -m unittest discover -s tests -p test_eva01_assets.py -v
python3 -B -m unittest discover -s tests -p test_potian_assets.py -v
python3 -B -m unittest discover -s tests -p test_full_shop_catalog.py -v
SSJX_REFINEMENT_CAPTURE=/tmp/opencode/equipment-refinement/all-compositor \
  godot --headless --path client res://tests/equipment_refinement_test.tscn
godot --headless --path client res://tests/eva01_anatomy_test.tscn
```

三个系列的实际渲染复用第一阶段命令，将输出目录分别设为 `boneglow-ui`、`gravebloom-ui`、`eva01-ui`，场景分别为对应的 `*_equipment_test.tscn`。输出目录需预先创建。

最终对照与日志在 `/tmp/opencode/equipment-refinement/`：

- `boneglow-before-after.png`、`gravebloom-before-after.png`、`eva01-before-after.png`：实际人物合成器前后对照，最近邻放大。
- `boneglow-actions.png`、`gravebloom-actions.png`、`eva01-actions.png`：18个角色原生动作首步整理。
- `after/*-idle.png`：Godot实际渲染的六角色穿戴页；`*-ui/`：真实商城、背包、地图及管理试穿截图。
- `eva01-icons.png`：最终初号机六角色十槽图标；`*-ui.log`、`all-geometry.log`、`eva01-anatomy.log` 为验证日志。
