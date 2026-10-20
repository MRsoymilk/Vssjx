# 同地图连续挑战精英回归

2026-10-21。本次仅修改与验证源码；真实联调使用自行创建并销毁的 PostgreSQL 容器和服务进程，没有迁移测试数据到现有数据库或操作运行中的服务。

- Rust `elite_hunt` 验证地图／种类计数、序列化、保持触发状态、单人／组队强化、逐击暴击、封印／睡眠、直接击杀与持续伤害后的有限复活，以及全灭判负。
- Godot `elite_hunt_test` 验证走动不重置、真实存储重载、保存失败回滚、第五场实际游戏入口、击败后清零、精英标签和死亡动画完成后复活。
- `run_elite_hunt.py` 使用真实HTTP与WebSocket验证不同位置同种居民计数、操作重放、服务重启、旧能力拒绝、撤退保留、精英复活与最终一次奖励、实际切图数据库触发器、队员达到阈值触发组队精英、提交失败整笔回滚。真实服务回包经Godot校验器验证。
- 原有普通怪物、单人多怪、组队、玩家技能和音效回归继续运行，确保新增玩法没有改变普通战斗规则。

```powershell
cargo test --offline --manifest-path server/Cargo.toml --target-dir work/monster-combat-target
cargo build --offline --manifest-path server/Cargo.toml --target-dir work/monster-combat-target
$env:SSJX_TEST_SERVER_BIN="$PWD/work/monster-combat-target/debug/vssjx-server.exe"
$env:GODOT_BIN="$PWD/work/web-toolchain/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
python tests/run_elite_hunt.py
& $env:GODOT_BIN --path client --rendering-method gl_compatibility res://tests/elite_hunt_test.tscn
& $env:GODOT_BIN --path client --rendering-method gl_compatibility res://tests/solo_encounter_test.tscn
```

过程日志、回包和截图仅保留在忽略的 `work/hunt-*`、`work/elite-*`，不提交测试账号／角色存档。未执行发布打包或部署；后续服务更新需运行0028迁移并同时更新客户端。


## 本轮结果

Rust全量通过（当前工作目录137项，含精英专项7项）；真实 PostgreSQL／HTTP／WebSocket精英专项41项通过；Godot精英专项22项、本地多怪55项、组队客户端69项、组队回合54项、联机PVE界面71项、遇敌准备165项、技能战斗120项、技能音效22项、技能特效时序26项通过。编辑器导入正常，精英界面使用实际OpenGL渲染检查，复活事件同时验证有无技能特效尾段的死亡等待顺序。
