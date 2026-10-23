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
