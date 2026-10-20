# 决斗／组队卡顿排查与回归

2026-10-20。只读排查线上日志与审计，在自建 PostgreSQL、测试账号和独立存档验证源码修复。**未部署、未打包**；不把本地修复通过等同于当前线上／已有 APK 已修复。

## 线上证据与边界

- 游戏容器运行正常；当次资源采样约 11% CPU、66 MiB 内存，不支持“服务已崩溃”的判断。
- 已读取的 66,406 行日志覆盖 01:31～08:19 UTC，包含 2,338 条 `RATE_LIMITED`；另读取近期 6,000 行，包含 371 条 `RATE_LIMITED`。均为有限样本，不是完整全天统计。样本未发现 panic、ERROR 或数据库死锁。
- 前一日志样本的 44,582 条组队 HTTP 回执：服务端耗时中位约 8.9ms、P95 约 23.3ms、最大约 166.5ms。这不是设备端／公网端到端耗时，也不能排除个别时间段的慢请求。
- 最近 24 小时审计中，决斗接受、技能及组队技能均持续有成功记录；同时存在决策过期、已进入结算、未准备、未集合等业务拒绝。不能把等待他人提交／共享30秒窗口统称为卡死。
- 线上迁移表最新为 0022，本地数值、灵魂和共享回合等源码更新尚未部署。没有修改线上数据库、进程、配置或玩家资源。
- 旧日志的“send failed or timed out”同时表示普通写失败与超时，**不能将其全部当作真实网络超时**。本修复增加独立 `WORLD_SEND_TIMEOUT`／`WORLD_SEND_FAILED` 日志字段。

原始远端日志仅保存在忽略的本地证据目录，不提交昵称、连接标识、访问令牌或生产配置。

## 源码修复

1. **组队只读刷新阻塞操作**：旧逻辑在自动快照请求进行时禁用按钮并直接拒绝 `submit`。现在可排队一条玩家写操作，快照仍按原请求关联验证，随后优先发送原 UUID。重复点击被锁定；读取失败不能误清写操作；未知写入结果仍以同 UUID 重试；授权撤销则清除队列。队伍面板与战斗按钮都使用同一提交能力判断。
2. **弱网移动突发**：保留服务端 80ms 间隔、协议速率与权威移动速度限制。客户端最多一条移动请求待确认，只保留最新未发目标；收到本角色 `last_input_seq` 后才继续发送。`RATE_LIMITED` 后单调时钟退避250ms；战斗围栏错误清除移动残留；单人PVE／未确认PVE也不能漏发旧移动。
3. **播放队列防御**：缺失／空／零速动画不再产生永久活动令牌；在没有动画时仍只释放一次命中与完成事件。原生命中步截取到合法帧数，微小终点误差归零。有效资源仍按原帧／原命中时间播放，不改在线伤害。桌面常规帧率测试没有复现所有用户卡顿，本项是已覆盖异常输入的兜底，不宣称它是线上唯一根因。
4. **决斗协议恢复和诊断**：不合法数据仍拒绝，不启用客户端算伤；失败后走有次数上限的重连，而不是停在不可恢复的战斗画面。决斗审计附带处理耗时、回合／已结算回合、版本与阶段，后续可区分“等待指令、播放、断线”。
5. **日志降噪**：重复移动拒绝保留全部响应、指标及10秒聚合审计，但同一聚合窗口只在首个／错误码变化时输出 WARN，避免反复输入掩盖其他错误。没有删除限流或安全审计。

## 验证入口

本次结果：Rust全量123项通过；真实组队联调118项、Godot组队客户端11项通过；真实决斗联调24项、Godot决斗双方各14项通过；增加审计字段断言后的独立决斗协议回归21项通过。新增专项实际离屏323项、组队完整回合离屏58项通过；原有决斗38项、组队68项、真实回环移动38项、目标标记27项、原生动作276项回归通过。两种战斗截图已人工检查。上述测试在隔离工作树执行，不包含未完成的装备实例草稿。

```sh
cargo test --offline --manifest-path server/Cargo.toml
cargo build --offline --manifest-path server/Cargo.toml
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" GODOT_BIN=godot python tests/run_teams.py
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" GODOT_BIN=godot python tests/run_duels.py
godot --headless --path client res://tests/movement_control_test.tscn
godot --headless --path client res://tests/duel_test.tscn
godot --headless --path client res://tests/team_test.tscn
godot --headless --path client res://tests/team_round_test.tscn
SSJX_DUEL_CAPTURE=/tmp/opencode/stall-captures \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/combat_stall_test.tscn
```

`combat_stall_test` 使用真实 SpriteFrames、三职业全部主动技能和正式决斗／组队视图，检查两次施法按序结束后恢复按钮；此外验证异常动画、后台快照与写队列的确认／失败／重绑。`movement_control_test` 用真实回环 WebSocket 验证一条待确认、连续目标合并、停止、限流退避和断线清理。

组队联调保留真实共享30秒等待、并发指令、事务失败回滚、重启恢复、死亡寻尸和真实 Godot 客户端。原有旧数值断言改为根据冻结版本验证怪物参数，未放宽业务成功／失败要求。决斗联调的两个专用8级UI角色合法分配40点，以适配新版虚拟气血及减伤后的原65秒UI测试预算；不改玩家数据或PvP规则。

后续线上验收仍需要在用户设备、实际延迟／丢包条件下复测；本次不操作部署，不能据此保证现有安装包即时消除卡顿。

## local 技能特效与怪物反击时序（2026-10-20）

复现角色出招已结束、原生技能特效仍在播放时，怪物提前反击的问题。local 技能现在在原生命中点触发特效和音效，等待角色动作及本次技能全部特效层结束后进入反击；不增加固定延时，不等待音频尾音。退出战斗取消等待，避免旧回合继续执行。未改变技能费用、伤害、冷却、回合末结算或联机规则。

新增 `local_skill_timing_test.tscn`，使用实际主场景和原生动画，覆盖雷霆一击、星火燎原、天罡战甲、狂风骤电，检查命中前无特效、多层最后一层仍阻止反击、播完立即反击及退出清理。修复前26项中6项失败；修复后真实 OpenGL 运行26项全部通过。技能战斗回归120项、音效回归22项通过，编辑器导入及 `git diff --check` 通过。技能说明断言同时按既有数值版本验证百分比消耗／冷却或旧固定消耗。

```sh
godot --path client --rendering-method gl_compatibility res://tests/local_skill_timing_test.tscn
godot --headless --path client res://tests/skill_battle_test.tscn
godot --headless --path client res://tests/skill_audio_test.tscn
```

本阶段仅修复本地源码并提交，未重新打包、推送或部署。
