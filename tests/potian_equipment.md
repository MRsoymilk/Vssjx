# 破天斧接入验证

用户于2026-10-20确认的斧头图片作为唯一生产源，保存在 `analysis/ai-generated/equipment/legendary/potian-approved.png`，SHA256为 `3ccb7861833d950ed46a2db25c13da1eea5f3c0b07b8952f1088c73f202dc610`。本次未重新生成武器设计。

入口为商城“武器”或“传世兵器 · 本角色”。物品ID为 `ai/legendary/potian_axe`，男女力士共用，售价250铜钱、攻击+20。截图及玩家表的“51级”保存在参考字段，当前仍沿用重建商城不设等级门槛的规则；数值并非原服务器物品表恢复。

独立武器使用外观编码46，与套装注册表分离，不生成虚构衣服或头饰。商城、背包、管理试穿、人物选择、世界及战斗均使用相同映射。换装时可保留原版及三套新增装备的衣服和头饰；服务端继续校验职业、所有权、购买扣费及单槽唯一性。

生产导入通过 `tools/build_potian_assets.gd`：对用户抠图的半透明边缘设透明阈值，然后按原版力士武器两帧的握持点、朝向等比最近邻采样，输出148×47原生图集与32×32图标。未改原包纹理、帧矩形或动画配方。输入、握持参数及输出摘要记录在 `potian-import.json`。

新增 `0027_potian_equipment.sql` 迁移把物品加入数据库白名单和武器槽，保留旧物品、数量约束及单槽唯一索引。没有修改历史迁移，也没有对正在运行的服务执行迁移。

复现命令：

```powershell
python tools/build_legendary_equipment.py
python tools/build_full_shop_catalog.py
godot --headless --path client --script ../tools/build_potian_assets.gd
godot --headless --editor --path client --import --quit
python tests/test_potian_assets.py
python tests/test_full_shop_catalog.py
cargo test --manifest-path server/Cargo.toml --lib shop::tests
```

新迁移已作为固定SQL提交；无需日常重新生成。要在另一个独立测试数据库验证联网行为，先编译专用测试服务，并设置：

```powershell
$env:SSJX_TEST_SERVER_BIN = '测试服务exe的绝对路径'
python tests/run_potian_equipment.py
$env:SSJX_POTIAN_FIXTURE = (Resolve-Path work/potian-review/live-fixtures.json).Path
$env:SSJX_POTIAN_CAPTURE = Join-Path (Get-Location) 'work/potian-review'
godot --path client res://tests/potian_equipment_test.tscn
godot --headless --path client res://tests/full_shop_test.tscn
```

本次结果：3项资产检查、5项完整商城Python检查、5项Rust商城单元测试通过；独占临时PostgreSQL与真实WebSocket服务38项检查通过，覆盖男女力士购买、数据库落盘、装备属性、职业拒绝、重复购买拒绝、其他客户端外观广播、混穿及重连恢复。Godot接收真实服务端状态并渲染103项检查通过；原商城1637项检查通过。实际截图位于忽略目录 `work/potian-review/`，包括商城、男女背包以及四种动作对照。

本次仅本地接入和测试，未打包、推送、重启现有服务或部署。联网运行环境需在后续部署时同时更新客户端、服务端和数据库迁移。
