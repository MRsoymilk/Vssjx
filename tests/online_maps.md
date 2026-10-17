# 联机第二张地图

2026-10-17：接入既有本地剧情地图“古剑遗迹”，不是恢复了新的原包地图布局。地形由接入前本地 `_ruins_data()` 用 Godot 导出，之后本地、联机客户端和服务器读取同一份 JSON；青云山道原始字节和原有地图摘要保持不变。

- 山道东侧 `[28,16]` 灵门：完成三狼试炼并向道人领取奖励（任务阶段至少 3）后开放，抵达遗迹 `[5,16]`。遗迹 `[3,16]` 返回山道 `[10,16]`。
- 传送复用持久化 PvE 操作 UUID、事务与回执。服务器校验当前地图、站立、距离、任务和战斗状态；地图、坐标、位置版本、状态版本和回执一起提交。旧连接在转移后失效；迟到的位置保存由地图、所有权与位置版本三重条件隔离。
- 每张地图独立发布玩家增量、基线和居民。全服共用账号所有权、准入限制与公共聊天；地图间互不显示玩家或怪物。重连重新校验地图字节摘要，重建地形、装饰、灵门、小地图与角色。
- 遗迹守卫和赤焰妖王沿用本地怪物数值及原包美术。战斗、奖励、逃跑和个人 30 秒刷新冷却由服务器处理；击败妖王将任务阶段从 3 推进至 4，返回道人仍可恢复元气。
- 迁移 `0010_online_ruins.sql` 扩大击败位图至六只怪物，保留旧位及冷却。握手协商 `maps_version:1`；旧客户端仍可玩第一张地图，拒绝进入未支持地图，需要更新客户端才能切图。
- 切图回执丢失时保留账号内存中的原操作，重连读取权威所在地图并重放原 UUID；旧回执只确认操作，不能回退当前地图。测试须等待待确认操作清空后再发起下一次交互。

验证命令（专用临时数据库，不使用或修改用户账号）：

```powershell
cargo test --locked --manifest-path server/Cargo.toml --target-dir work/online-second-map/target
cargo clippy --locked --manifest-path server/Cargo.toml --target-dir work/online-second-map/target --all-targets -- -D warnings
$env:SSJX_TEST_SERVER_BIN='F:/project/Vssjx/work/online-second-map/target/debug/vssjx-server.exe'
python -X utf8 tests/run_online_maps.py
python -X utf8 tests/run_online_pve.py
$env:GODOT_BIN='E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe'
$env:SSJX_MAP_UI_ONLY='1'
$env:SSJX_MAP_RENDER='1'
$env:SSJX_MAP_CAPTURE='F:/project/Vssjx/work/online-second-map/ruins-online.png'
python -X utf8 tests/run_online_maps.py
```

Windows / Godot 4.7.1：Rust 53 项、Clippy、共享数据 2 项、导出策略 4 项通过；隔离联调覆盖传送距离、锁定入口、错误入口、回执失败回滚、跨图不可见、同图互见、异图 NPC 拒绝、战斗禁止传送、两只遗迹怪物胜利及冷却、完成妖王剧情、返回、旧回执不回退、旧客户端隔离与服务重启恢复。原山道完整 PvE 联调通过。

真实 Godot/OpenGL 联调 19 项通过，覆盖地图点击走近、自动转移及待确认回执恢复、原样地形、地图名、小地图、返回灵门、遗迹原动画战斗、逃跑和双向返回，单机存档保持不变。截图已目视核验，产物位于忽略目录 `work/online-second-map/`。原 PvE UI 65、居民 13、世界增量 50、移动控制 35、双模式 1058、角色选择 10、世界地图 33 项回归通过。
