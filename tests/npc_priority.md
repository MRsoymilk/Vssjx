# NPC 显示与点击优先级

## 行为

- 本地及联机地图的 NPC 显示在玩家及玩家队伍旗标上方；高分辨率 NPC 名字在玩家名字上方，仍受地图裁剪及 HUD 遮挡。
- 联机点击同时命中玩家与 NPC 身体时优先选择 NPC，继续走原接近／对话流程。
- 复用原身体像素命中区域；玩家独立区域选择、怪物、空地、传送点、弹窗及组队跟随限制沿用原逻辑。

## 2026-10-23 验证

在 NPC 出现后加入 12 名围观玩家，使玩家身体覆盖 NPC。修复前鼠标、触屏两项复现失败；修复后通过。

| 专项 | 检查结果 |
| --- | --- |
| 地面点击、拥挤 NPC、鼠标／触屏、玩家选择及跟随限制 | 24 项通过 |
| 玩家目标及社交操作回归 | 28 项通过 |
| 联机人口、名字跟随及清理回归 | 27 项通过 |
| 修复 NPC 外观、协议及本地地图回归 | 454 项通过 |
| Xvfb＋Mesa OpenGL ES 实际渲染 | 29 项通过 |

已查看本地主角与 NPC 重叠、联机 12 人围住 NPC 的截图。日志为 `/tmp/opencode/npc-priority-*.log`，截图位于 `/tmp/opencode/npc-priority-captures/`。

## 重跑

```sh
godot --headless --path client res://tests/ground_click_test.tscn
godot --headless --path client res://tests/player_target_test.tscn
godot --headless --path client res://tests/population_test.tscn
godot --headless --path client res://tests/recovered_npc_map_test.tscn

SSJX_GROUND_CLICK_CAPTURE=/tmp/opencode/npc-priority-captures \
  XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
  python3 tests/run_offscreen.py --path client --rendering-driver opengl3_es \
  res://tests/ground_click_test.tscn
```

渲染前需创建截图目录；Godot 版本为 `4.7.2.stable.gentoo.ed1daf0bf`。
