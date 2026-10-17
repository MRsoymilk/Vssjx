# 联机装备装卸

2026-10-17：将现有本地“青锋剑”装备、卸下接入联机背包。复用 `inventory.tscn` 的绿色背包、原图标、武器栏和物品菜单；在线模型从服务器读取药品数量、武器归属、装备状态、金币、人物和属性，不安装或保存 `Game.player`。

恢复范围：当前已确认的可玩武器只有青锋剑，沿用既有攻击 +5 规则。`original_items.json` 中 56 个武器图标、81 个装备图标的名称、数值、槽位和角色换装部件映射尚未恢复。其余九个装备栏继续为空；当前角色外观仍使用既有职业组合动画，没有添加未经确认的装备属性或外观替换。

服务端：

- `pve.state` 增加可选 `equipment`：`version=equipment-v1`、`weapon_owned` 和 `weapon`（`sword` 或 null）。旧客户端可以忽略扩展，新客户端连接旧服务时不会显示可用装备。
- `equip` / `unequip` 使用已有角色操作事务与幂等回执，携带 `target=sword` 和预期人物状态版本。服务器检查角色所有权、物品归属、状态版本、站稳及非战斗状态，按明确目标设置装备状态，重复装备不重复增加属性。
- 复用现有 `inventory_items.equipped`，无需新增迁移。库存行、人物状态版本与回执一同提交或回滚；攻击与人物属性由服务器重新计算，后续战斗读取持久化装备。
- 断线后恢复原状态，待确认操作按原 UUID 重试。旧回执不会回退较新状态，同版本的升级前回执也不会抹除新装备字段。

客户端：

- 联机工具栏的“背包”打开原有背包。未装备青锋剑占一个背包格，装备后移入武器栏，点击武器栏可以卸下；服务器回执到达后刷新栏位与属性。
- 等待或断线时禁止重复装备，战斗期间使用原战斗道具流程。物品查看与本地视图整理可用；在线背包没有接入本地购药、丢弃或地图外用药动作，直接调用这些本地方法也不会影响单机数据。
- 背包开启时阻止地图点击与键盘移动，返回/Escape 恢复地图交互，公共任务和战斗模型继续使用原通道。

验证（仅临时 PostgreSQL 与测试账号）：

```powershell
$env:SSJX_TEST_SERVER_BIN='F:/project/Vssjx/work/online-second-map/target/debug/vssjx-server.exe'
$env:GODOT_BIN='E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe'
$env:SSJX_GEAR_RENDER='1'
$env:SSJX_GEAR_CAPTURE='F:/project/Vssjx/work/online-equipment/equipped.png'
python -X utf8 tests/run_online_equipment.py
python -X utf8 tests/run_online_pve.py
```

Windows / Godot 4.7.1：真实 Rust/PostgreSQL/WebSocket 验证物品归属、版本过期、重复请求、回执失败回滚、服务重启、移动与战斗限制、装备攻击伤害和角色隔离通过；真实 OpenGL 背包联调 19 项通过，覆盖装备/卸下、重复点击、非乐观加成、原始栏位、断线恢复、再次打开和单机数据隔离。截图已目视核验。

Rust 53 项与 Clippy 通过；原完整 PvE 联调通过；Godot PvE UI/协议 71 项、场景 105 项、双模式 1058 项回归通过。日志和截图位于忽略目录 `work/online-equipment/`。按用户要求不部署、不重启现有服务、不推送远程。
