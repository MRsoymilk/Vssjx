# 单人随机多怪与怪物能力回归

2026-10-20。本地源码验证，未推送、打包或部署；没有操作用户的数据库、账号或正在运行的本地服务。Rust 使用独立 `work/monster-combat-target`；真实联调创建并销毁自己的 PostgreSQL 容器与游戏进程。

## 验证范围

- 1／2／3只抽取边界、同地图候选、同种普通怪独立增援与禁止复制首领；每只怪有独立槽位、血条及目标选择。
- 三只普通怪依次反击；强力怪两次独立攻击、横扫存活队员、撕裂流血、怪物暴击元数据及屏闪；睡眠、封印、防御、反伤继续生效。
- 流血按完整回合扣血三次，状态序列化后不重抽；重复命中刷新而非无限叠加。死亡后不继续连击、不自动复活。
- 单体只命中所选槽位，群攻对全部存活敌人结算，消耗一次灵力；冷却、失效目标及旧修订拒绝不会推进回合或扣资源。
- 本地／联机沿用原像素资源与六指令；技能全层特效播完才进入下一行动，群攻音效只播放一次；死亡动画结束后显示结果。顶部本地气血跟随命中展示。
- “战斗指令”和“自动战斗”各72×22逻辑像素，同一行居中；自动开启后显示“手动战斗”，无快捷键前缀；本地自动仍会低血量用药、选择可用技能。
- 新客户端以 `encounter_version=1` 请求新单人阵列；旧客户端／旧在途JSON保留旧入口。`enemy_slot` 与技能 `target` 分开，不能注入客户端伤害或奖励。
- 独立数据库联调验证挑战重放不重抽、选敌、旧修订拒绝、进程重启精确恢复、整场胜利、奖励只发一次、全部居民任务／刷新进度落库。扩展地图首领有增援时，整场总血量预算与主怪兼容字段均通过真实客户端验证。
- 同种增援逐只发放铜钱和修为，居民任务和刷新状态按ID去重。本地失败进入既有灵魂／坟堆恢复规则，不发放部分奖励。

## 结果

Rust全量129项通过；新增怪物专项5项（含单人阵列、序列化及首领预算），原组队14项、伤害反馈4项通过。真实 PostgreSQL／WebSocket 专项21项通过，真实服务端的普通怪／扩展地图首领回包均由 Godot 校验。

Godot真实 OpenGL单人专项55项、遇敌准备151项通过；联机PVE界面71项、组队客户端69项、组队完整回合54项、技能战斗120项、音效22项、本地特效时序26项、怪物参数107项、卡顿专项322项通过。编辑器导入与 `git diff --check` 通过。旧“怪物不暴击”和“死亡动画开始即显示胜利”断言已更新为本次明确要求与展示顺序，并保留独立元数据／死亡等待断言。

## 命令

```powershell
cargo test --offline --manifest-path server/Cargo.toml --target-dir work/monster-combat-target
cargo build --offline --manifest-path server/Cargo.toml --target-dir work/monster-combat-target
$env:SSJX_TEST_SERVER_BIN="$PWD/work/monster-combat-target/debug/vssjx-server.exe"
$env:GODOT_BIN="$PWD/work/web-toolchain/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
python tests/run_solo_encounters.py
& $env:GODOT_BIN --path client --rendering-method gl_compatibility res://tests/solo_encounter_test.tscn
& $env:GODOT_BIN --path client --rendering-method gl_compatibility res://tests/battle_transition_test.tscn
```

本地渲染截图位于忽略的 `work/solo-formation.png`，不提交测试账号数据、临时存档或运行日志。此记录不代表已有网页／APK已经更新，也不宣称所有等级／装备的胜率均已完成平衡仿真。
