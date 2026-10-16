# 单机怪物定时刷新

单机怪物此前直接通过 `player.defeated` 永久排除，完成试炼后地图会逐渐清空。现在击败记录仅保留为任务历史，当前是否存活由独立的 `enemy_respawns` 截止时间决定。

- 当前两张单机地图的六个出生点，包括山灵、守卫和妖王，胜利结算后分别等待 **30 秒**刷新。这是本地规则配置 `Game.ENEMY_RESPAWN_SECONDS`，并非已经恢复的原服刷新参数。
- 原出生点重新生成完整怪物；山狼重新开始巡逻，可以再次选中、战斗和获取奖励。刷新不会清空已完成任务或重发任务交付奖励。
- 期限使用 Unix 时间随角色存档保存，换地图、读档不会重新开始倒计时，退出游戏期间也计算时间。期限到达后，当前地图自动补回；暂停战斗或菜单时保留场景，返回地图立即补齐到期怪物。
- 旧版存档没有该字段时补为空字典，原来永久消失的怪物立即恢复，保留角色、任务和击败历史。损坏的刷新字段拒绝加载，保留当前角色和原文件。
- 逃跑、失败不触发刷新计时；战斗重复结算不重复发奖励或延长计时。联网模式仍使用服务端数据。

验证命令（Godot 4.7.1，仓库根目录）：

```powershell
godot --headless --path client --editor --import --quit
godot --headless --path client res://tests/offline_respawn_test.tscn -- --realtime
godot --headless --path client res://tests/test_runner.tscn
godot --headless --path client res://tests/platform_storage_async_test.tscn
godot --headless --path client res://tests/local_mode_test.tscn
godot --headless --path client res://tests/move_target_test.tscn
godot --headless --path client res://tests/click_motion_regression.tscn
python -m unittest discover -s tests -p test_platform_interface.py
```

刷新专项覆盖：旧存档恢复两张地图；全部六个出生点消失与重生；截止时间边界；避免重复节点；可交互、满血再次战斗；巡逻重新初始化；挂机自动刷新；菜单/战斗暂停后补齐；独立计时、换图和读档；完成任务不倒退；真实战斗胜利、失败、逃跑及重复结算；无效存档字段。`--realtime` 额外实际等待默认的 30 秒期限，不改短刷新配置。

2026-10-16 Windows / Godot 4.7.1 验证结果：刷新专项（含真实 30 秒等待）91 项、完整游戏流程 385 项、异步存档 64 项、单机入口 27 项、移动落点 27 项、连续点击移动 776 项，全部 0 失败；平台边界 Python 检查 14 项通过。旧移动用例改用明确的刷新期限来隔离怪物，避免继续依赖“击败即永久消失”。
