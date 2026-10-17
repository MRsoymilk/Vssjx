# 怪物独立巡逻

2026-10-17：原巡逻逻辑让三只山狼共用六个固定相对路点，完成一段后统一停顿 0.6 秒，只有初始时刻略微错开，容易呈现同步走动。

本地与联机均改为每只山狼独立的随机流、初始等待、目标顺序与停顿计时。每次休息结束后，在出生点两格范围内随机排列候选格，只采用可达且整条路线都留在活动区内的路径；初始等待 0.2～2.5 秒，后续停顿 0.5～2 秒。移动速度仍为每秒 28 像素。NPC、山灵与遗迹怪物保持原来的待机设定。

联机巡逻仍由服务器推进，同一只怪物在不同玩家眼中保持一致。随机状态不发送给客户端，各连接继续复用同一份权威居民快照，没有给每名玩家生成不同的怪物位置。本地巡逻在世界暂停、玩家交互及靠近玩家时保留原暂停规则。

追近山狼时额外保留一格交互距离余量，避免发出挑战到服务器处理期间，怪物走动一格就超过允许范围。试炼联调相应改为读取当前怪物位置并重新走近，不再假设战斗结束、重连后怪物仍停在原来附近。

验证：

```powershell
cargo test --locked --manifest-path server/Cargo.toml --target-dir work/online-second-map/target
cargo clippy --locked --manifest-path server/Cargo.toml --target-dir work/online-second-map/target --all-targets -- -D warnings
godot --headless --path client res://tests/patrol_test.tscn
godot --headless --path client res://tests/population_test.tscn
godot --headless --path client res://tests/game_modes_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
$env:SSJX_TEST_SERVER_BIN='F:/project/Vssjx/work/online-second-map/target/debug/vssjx-server.exe'
$env:GODOT_BIN='E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe'
$env:SSJX_TEST_PVE_GODOT='1'
python -X utf8 tests/run_online_pve.py
```

Rust 55 项与 Clippy 通过；固定种子的两分钟模拟验证相对轨迹不同、同时存在移动与休息，以及改变一只狼的随机流不会影响其他狼。原巡逻通行、邻接、范围、NPC 不移动及共享快照检查通过。本地巡逻专项 8 项、联机居民 13 项、双模式 1058 项、PvE UI/协议 71 项通过。日志位于忽略目录 `work/independent-patrols/`。

隔离 PostgreSQL/Rust/WebSocket 完整试炼联调通过；真实 Godot 联调 25 项通过，覆盖追近独立巡逻山狼、接任务、战斗、聊天和断线回执恢复。仅使用临时数据库及测试账号。

按用户既有要求不部署、不重启当前游戏服务、不推送远程。
