# 存档坐标被障碍覆盖时的地图进入恢复

2026-10-22线上只读核对：日志中有12次 `INVALID_SAVED_POSITION`，
分成连续重试的三组。核对当前367个未删除角色与部署时的地图碰撞数据，
发现1个角色的存档坐标不可行走；没有发现不可行走的尸体坐标。
不提交账号、角色标识或原始生产日志。

旧逻辑先更新角色所有权，再因存档坐标不可行走拒绝进入。
后续重试仍读取同一障碍格，因此无法恢复。

新逻辑在当前地图出生点可达区域中选择距原坐标最近的可行走格，
跳过传送出口；合法存档位置保持不变。
所有权认领、位置修正和 `world.position_recovered` 审计在同一事务提交后，
才发布角色及进入地图的快照。修正失败会回滚所有权、位置和版本。
不回血、不改金钱／背包／分配点，也不删除已有战斗或尸体。

隔离 PostgreSQL／真实服务端专项21项通过，覆盖实际受影响的地图坐标、
附近可达修正、世界与角色私有快照一致、重启保持、只修正一次、
审计失败回滚与重试、灵魂不复活、已有阵列战斗完整保留并可正常逃跑。
修复前同一入口复现 `INVALID_SAVED_POSITION`。
Rust世界单测6项通过；组队真实接口回归121项、角色删除真实接口回归40项通过。

```powershell
$env:SSJX_TEST_SERVER_BIN='F:\project\Vssjx\work\npc-map-cargo\debug\vssjx-server.exe'
python -X utf8 tests/run_saved_position_recovery.py
python -X utf8 tests/run_teams.py
python -X utf8 tests/run_character_deletion.py
```

配合 [PvE审计超限修复](pve_audit_bounds.md)，只需更新服务端，现有客户端兼容。
这里记录源码验证，不代表线上服务已经更新。
