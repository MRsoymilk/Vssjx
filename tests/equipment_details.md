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
