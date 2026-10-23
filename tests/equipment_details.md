# 背包装备详情、对比与洗练

## 阶段一：原版风格装备详情

- 背包格子及穿戴槽的“查看”进入独立浅黄纸面，蓝色标题、绿色属性、金色边框与翻页。
- 固定商城装备与掉落实例读取各自真实属性；分页显示强化后基础值、全部词条及传奇／套装说明，不添加不存在的绑定、凹槽或词条。
- 查看期间按实例 UUID 保持目标，联机刷新或背包排序不会串到同模板另一件装备；已移除装备显示失效提示。返回保留选中目标，Escape 先关闭详情。
- 葫芦及其他非装备继续使用对应物品说明。

2026-10-23：详情专项 21 项、实例回归 20 项、带真实服务夹具的葫芦回归 395 项通过；Xvfb＋Mesa OpenGL ES 实际渲染 26 项通过，已查看属性、翻页、传奇、固定装备截图。

```sh
godot --headless --path client res://tests/equipment_details_test.tscn
godot --headless --path client res://tests/loot_instances_test.tscn
SSJX_GOURD_FIXTURES="$PWD/work/gourds/server-fixtures.json" \
  godot --headless --path client res://tests/gourds_test.tscn
SSJX_EQUIPMENT_DETAILS_CAPTURE=/tmp/opencode/equipment-details-captures \
  XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
  python3 tests/run_offscreen.py --path client --rendering-driver opengl3_es \
  res://tests/equipment_details_test.tscn
```

日志及截图：`/tmp/opencode/equipment-details-*`。Godot `4.7.2.stable.gentoo.ed1daf0bf`。

## 阶段二：同部位对比与直接洗练

- 详情中的“装备对比”读取当前穿戴的同部位装备；空槽按零值比较。数值为强化后基础值与词条贡献之和，绿升红降、箭头标识方向，百分比差异按百分点说明。传奇／套装效果以完整文字独立展示。
- 对比页可直接装备选中实例；掉落实例使用 UUID，固定商城装备沿用模板 ID 与商城指令。装备后立即更新对比，返回背包定位到该装备的穿戴槽。
- 详情与对比均可“前往洗练”，直接携带 UUID 打开现有养成面板。“返回详情”与 Escape 保留详情页码并刷新洗练结果；固定装备、无词条或达到洗练上限时入口禁用并说明原因。
- 洗练沿用原有二次确认、报价扣费、单词条锁定与持久化；断线、操作待确认、战斗、灵魂等状态限制继续生效。分解后详情显示装备已失效，不改选同模板其他实例。
- 保存失败回滚后刷新详情与背包；保存过程中关闭详情，也按稳定身份恢复真实装备与选中位置。

2026-10-23 最终验证：

| 专项 | 结果 |
| --- | --- |
| 装备对比／直接洗练 | 无界面 49 项、实际 OpenGL ES 渲染 53 项通过 |
| 装备详情 | 无界面 21 项、最终页面实际渲染 26 项通过 |
| 原养成面板布局 | 34 项通过 |
| UI 场景 | 110 项通过 |
| Rust 向量养成回归 | 1,004 项断言通过 |
| 编辑器导入、`git diff --check` | 通过 |

对比专项覆盖触屏入口、同模板不同 UUID、词条新增／丢失、百分点、空槽与特殊效果、确认扣费、失败回滚、保存中关闭详情、洗练返回和失效目标。联机路径使用合法快照与回执，经正式 `OnlinePve.receive/submit` 验证请求字段、权威结果刷新及角色切换；本阶段未运行新的真实服务器联机专项。

养成旧专项退出时偶发报告 4 个对象与 1 个资源仍在使用。`--verbose` 定位为 `background.ogg` 的 OGG 播放资源；在临时项目还原本功能前 `88489fe3` 的背包与养成脚本后复现相同提示，详见 `/tmp/opencode/equipment-baseline-progression-repeat.log`。音频测试已有等待混音线程释放的处理（见 `tests/audio.md`）；新装备专项退出没有该提示。

```sh
godot --headless --path client --editor --import --quit
godot --headless --path client res://tests/equipment_comparison_test.tscn
godot --headless --path client res://tests/crafting_layout_test.tscn
godot --headless --path client res://tests/ui_scenes_test.tscn
SSJX_PROGRESSION_VECTORS=/tmp/opencode/vssjx-progression-repair.json \
  godot --headless --path client res://tests/progression_test.tscn
SSJX_EQUIPMENT_DETAILS_CAPTURE=/tmp/opencode/equipment-details-captures \
  XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
  python3 tests/run_offscreen.py --path client --rendering-driver opengl3_es \
  res://tests/equipment_comparison_test.tscn
```

最终实际截图位于 `/tmp/opencode/equipment-details-captures/`：`01–05` 为含新入口的详情页面，`06-comparison.png`、`07-direct-crafting.png`、`08-white-comparison.png`、`09-special-comparison.png` 为对比与直接洗练页面，均已逐屏核对。第二阶段日志位于 `/tmp/opencode/equipment-comparison-*.log`。
