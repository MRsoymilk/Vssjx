# 联机怪物定时刷新

原先服务端用 `defeated_mask` 禁止再次挑战，客户端也用任务击败名单永久隐藏居民。现在任务历史与怪物冷却分开：三只山狼和山灵胜利后分别等待 **30 秒**，随后在共享地图当前巡逻位置重新出现，可以再次战斗并获取战斗奖励。30 秒与现有本地规则一致，不声称已恢复原服刷新参数。

- 迁移 `0009_monster_respawns.sql` 为人物新增有界刷新时间表；旧人物默认空表，旧版永久消失的怪物立即恢复，原任务进度和奖励保持。每个人物单独计时，其他玩家的怪物不受影响。
- 服务端胜利结算把刷新截止时间、击败历史、人物奖励、背包及幂等回执放在同一事务。冷却内挑战返回 `MONSTER_RESPAWNING`；期限到达可再次开启满血新战斗。失败、逃跑不产生冷却；重复回执不重复给奖励或延后刷新。三只不同山狼仍各计一次任务目标，刷新不重发任务交付奖励。
- 角色私有状态新增数值型 `server_time_ms` 和 `progress.respawns`（怪物 ID → Unix 毫秒截止时间）；历史 `progress.defeated` 保留。最多四项，只能引用有效击败记录。服务端在每次挑战时检查截止时间，客户端不能通过修改本机时间绕过冷却。
- Godot 从服务端时间锚定单调时钟，自动恢复居民及小地图点，不需要点击、换图或轮询请求。菜单打开时也能更新；断线后等权威状态恢复。重连、服务重启及离线期间继续计时。陈旧回执不会回拨表现时钟；同版本的旧协议回执不会擦掉新刷新数据。旧服务端没有刷新字段时仍兼容原行为。
- 运行时最多保留每个怪物一个截止时间。已过期记录保留以便审计，下一次胜利覆盖它，不会随重复战斗无限增长。不修改单机存档。

验证：

```powershell
cargo test --locked --manifest-path server/Cargo.toml --target-dir work/multi-character-target
cargo build --locked --manifest-path server/Cargo.toml --target-dir work/multi-character-target
godot --headless --path client res://tests/online_respawn_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
godot --headless --path client res://tests/population_test.tscn
godot --headless --path client res://tests/game_modes_test.tscn
$env:SSJX_TEST_SERVER_BIN = 'F:/project/Vssjx/work/multi-character-target/debug/vssjx-server.exe'
$env:SSJX_TEST_PVE_RESPAWN = '1'
python -X utf8 tests/run_online_pve.py
$env:SSJX_TEST_PVE_CLIENT_ONLY = '1'
$env:GODOT_BIN = 'E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe'
python -X utf8 tests/run_online_pve.py
```

2026-10-17，Windows / Godot 4.7.1：Rust 52 项、Godot 刷新专项无界面 34 项/渲染 36 项、联机 PvE 65 项、人口 13 项、双模式 1058 项检查通过。隔离 Rust/PostgreSQL/WebSocket 联调实际等待默认 30 秒，验证服务重启、满血再次战斗、奖励重放、不同山狼任务计数、旧人物恢复、逃跑、失败和山灵独立冷却；真实 Godot 联调 30 项通过，包含生产 30 秒后自动出现、小地图恢复及点击开始新战斗。所有真实联调使用临时数据库和测试账号。

`SSJX_RESPAWN_CAPTURE_PATH` 指定现有目录并运行渲染版 `online_respawn_test.tscn` 可保存 `cooldown.png`、`respawned.png`；已目视检查 `work/online-respawn/captures` 中截图。本次客户端未重新打包网页，旧网页包需后续重新导出才能使用自动刷新逻辑。
