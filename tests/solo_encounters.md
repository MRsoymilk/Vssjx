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


## 换装角色头顶血条（2026-10-21）

原问题在新定位专项中可复现：54项中45项失败，攻击帧的姓名、气血和灵力与显示人物分离。修复后54项全部通过，实际OpenGL画面检查正常；覆盖左右朝向、连续动作采样、自然回位、取消、演员层平移／缩放及技能特效等待。现有组队回合54项、单人遭遇55项、精英及复活22项通过，角色数据和战斗规则未修改。

```powershell
godot --path client --rendering-method gl_compatibility res://tests/battle_hud_anchor_test.tscn
```

实际攻击截图与过程日志保存在忽略的 `work/battle-hud-anchor.png`、`work/hud-anchor-*`，未重新导出或部署客户端。


## 原版战斗布局回归（2026-10-21）

`battle_reference_layout_test.tscn` 通过实际本地游戏入口展示森林之王单人战斗，并展示完整五人五怪组队。验证中央菜单默认显示、绿色倒计时、原版手形选中光标、待机／逃跑文字、技能返回、自动模式切换、行动期间隐藏指令、共享回合提交后锁定、紧凑等级血条、完整姓名悬停及大型怪物的头顶空间。单人三怪与现有选目标、技能群攻、伤害／暴击、血条随动作、闪避、死亡／复活继续由原专项验证。

真实OpenGL布局专项36项、组队69项、共享回合54项、单人55项、血条54项、闪避28项、遇敌过渡171项、精英22项，共489项通过。布局变更直接显示六项指令，删除冗余的“战斗指令”按钮，旧布局断言同步更新；战斗事件与数值断言保留。

```powershell
godot --path client --rendering-method gl_compatibility res://tests/battle_reference_layout_test.tscn
```

截图位于 `work/battle-reference-single.png`、`work/battle-reference-party.png`、`work/solo-formation.png`，不提交运行截图或本地测试存档。


## 异常与增益图标回归（2026-10-21）

`battle_status_test.tscn` 使用真实战斗视图验证：原图字节与来源记录一致，人物流血不混入其施加给敌人的中毒，按来源保存的DOT取最长时长，空DOT表清除残留兼容字段，行动队列结束前不展示最终状态，图标跟随人物位移，点击说明和超出三种状态的切换可用，死亡隐藏，旧单怪PVE及切磋按正确归属显示。状态专项27项与相关回归合计385项通过，无需服务端／数据库变更。

```powershell
python tools/build_battle_status_icons.py
godot --path client --rendering-method gl_compatibility res://tests/battle_status_test.tscn
```

原包素材对应表为本次语义适配，未声称恢复原服状态编号。实际截图 `work/battle-status-party.png` 不纳入Git。


## 本地旧服务导致 INVALID_PVE（2026-10-21）

故障复现条件为：客户端已更新地图，8080进程仍使用旧地图目录编译的二进制。HTTP探活和发现均为200，其余商城／技能等主要目录一致，但已运行程序内嵌的 `ai-world-v1.json` 与当前客户端不同，因此 `AIWorld.valid_progress` 拒绝初始PVE快照。修复为使用已提交源码隔离构建、运行真实数据库／WebSocket专项后重新启动本地服务；原数据库完整备份，账号／角色／背包数量与金币／经验汇总核对保留。没有清空账号、迁移本地测试账号到公网或跳过数据校验。

客户端新增明确的 `PVE_CATALOG_MISMATCH` 提示，仅在有效版本声明的地图目录指纹不匹配时使用；损坏任务进度、未就绪世界、其他畸形状态继续按原规则拒绝。`pve_catalog_mismatch_test.tscn` 验证匹配接收、不匹配拒绝且不覆盖已确认数据、后续合法数据清除诊断、其他错误不被误分类，以及实际网络层的可读提示，8项通过。既有联机PVE界面71项、单人遭遇55项及真实服务端／数据库／WebSocket精英专项41项通过。

```powershell
godot --headless --path client res://tests/pve_catalog_mismatch_test.tscn
```

构建、验证日志及数据库备份位于忽略的 `work/local-server-sync-*`；本地8080的健康检查和发现返回200，当前服务程序内嵌地图与编辑器客户端一致。未重新导出网页／Android包或更新公网服务器。

### 商城更新后的同类故障（2026-10-21）

新增神行符后客户端商城为397项，本地8080仍运行此前396项商城的二进制。检查运行文件确认内嵌旧商城原文且不含神行符ID；地图目录已匹配，因此此前仅针对地图的提示没有覆盖本次拒绝。Rust用`include_str!`编译商城，更新JSON或仅重连不能更新已运行的服务，须重新构建并重启；打包客户端也需同步更新。

增加`SHOP_CATALOG_MISMATCH`诊断及明确的商城版本提示，继续拒绝不匹配状态，不覆盖已确认角色数据，不绕过背包校验。匹配后清除诊断，缺少指纹及畸形库存保留普通拒绝。目录专项14项、联机PVE界面71项、隔离数据库神行符服务端25项及真实客户端12项通过。
