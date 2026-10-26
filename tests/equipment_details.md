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

## 装备评分（2026-10-27）

- 详情沿用原版蓝标题、浅黄纸面、绿色属性与金边，窗口加高；属性页每页7行，评分以红色常驻显示，旁边提示相对当前同部位装备的增减。基础属性、追加词条、真实绑定状态分开显示。装备失效后清空评分，不跳到同模板其他实例。
- 同部位对比首行增加装备评分，装备、强化、洗练后随真实数据更新；实例列表提示与养成属性说明也显示同一评分。固定商城装备与迁移后的固定实例数值一致。
- 采用当前游戏的属性评分公式，并非从截图推断原版算法：强化后基础值及所有词条分别乘 `equipment-score-v1.json` 的整数权重，相加后除100并四舍五入一次；有正属性至少1分，空槽0分。主攻/双防/暴击/命中/闪避每点权重50；气血/灵力10；气血百分比5、暴伤2、穿透5、增伤3、持续伤害2、额外减伤10（百分比词条原始单位为万分点）。不额外按物品等级或品质重复加分。
- 传奇及套装特效继续独立展示，不折算为固定分数。评分用于同部位属性总量比较，不代表实际战斗伤害。当前没有镶嵌、凹槽或装备出售机制，因此未照抄截图中的宝石与售价；已有属性石仍是材料。
- 服务端与客户端共用评分配置；本地和联机界面使用同一函数，联机读取服务端快照。评分为派生显示值，不写入存档、数据库或客户端操作请求，不改变角色战斗属性、掉落、经济或旧协议兼容性。

验证：Rust评分、装备、强化、流派专项共22项通过，生成2160组涵盖3职业、2性别、10部位、1/30/60级、3品质、2随机种子、0/6强化的真实服务端向量；Godot实际OpenGL渲染详情4356项检查通过（含4320项跨语言数值与背包入口检查），详情及对比截图已核对。装备对比57项、装备实例20项、配置镜像9项通过；对比专项含真实本地装备/洗练保存及联机权威回执刷新。

扩展回归的两个既有问题已通过临时恢复HEAD的4个生产脚本对照复现：`crafting_layout_test.gd:51` 仍断言已取消的定向掉落 `focus` 字段；`equipment_slot_filter_test.gd` 的4处固定数量断言未跟随现有装备目录扩容。修改前后错误完全一致；基线日志为 `work/equipment-score-baseline-*.log`，本次未修改这两项旧测试。新页面截图为 `work/equipment-score-captures/01-details.png`、`06-comparison.png`；未打包、推送或部署。
