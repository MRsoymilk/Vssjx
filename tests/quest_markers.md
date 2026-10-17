# 地图任务标识

原包依据：`analysis/catalogs/online_world.json` 中 `teach1` 文案明确写明“角色头顶的黄色感叹号，代表有任务需要你来接受”。本次以这个语义替换本地 NPC 姓名后固定追加的“ · 任务”；联机姓名也只保留“清微道人”。

两种模式使用同一个 `npc_quest_marker.tscn` 和 `NpcQuestMarker`，图标是深色描边、黄色填充的像素感叹号，放在姓名上方，不依赖字体中感叹号的笔画宽度。SVG 是按上述形状复现的代码资源，并非声称已提取原版任务图标。未确认原版交付图标及颜色，因此可交付时复用黄色感叹号，不自行新增蓝/灰问号或其他状态图案。

| 任务状态 | NPC 标识 |
| --- | --- |
| 0：可接受 | 黄色感叹号 |
| 1：进行中、目标未完成 | 隐藏，进度仍在任务页面/对话中 |
| 2：目标完成、可交付 | 黄色感叹号重新显示 |
| 3 及以后：已交付 | 隐藏 |
| 联机尚未同步或断线 | 隐藏，等权威状态恢复 |

本地从 `Game.player.quest` 更新，返回地图时立即刷新；联机仅使用当前人物的权威 `quest_stage`，接受及领取成功回执更新标识。怪物不显示任务标识。没有修改任务规则、奖励、存档结构或后端。

验证命令：

```sh
godot --headless --path client res://tests/game_modes_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
godot --headless --path client res://tests/population_test.tscn
godot --headless --path client res://tests/test_runner.tscn
```

2026-10-17，Windows / Godot 4.7.1：双模式无界面 1058 项、实际渲染 1063 项通过；联机 PvE 无界面 65 项、实际渲染 73 项通过；人口 13 项、离线玩法 386 项回归通过。新增覆盖初次可接、接受后隐藏、可交付恢复、奖励回执后隐藏、无权威状态、断线及怪物排除，并检查标识不覆盖姓名。实际截图在 `work/quest-markers/local` 和 `work/quest-markers/online`，已目视检查。

本次未重新打包或部署网页。
