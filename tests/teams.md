# 组队与多怪验证入口

[设计规则](../design/teams.md) · [技能规则](../design/skills.md) · [测试总览](testing.md)

```sh
cargo test --locked --manifest-path server/Cargo.toml --test team_rules
python -X utf8 tests/run_teams.py
python -X utf8 tests/run_team_follow.py
python -X utf8 tests/run_team_participation.py
```

集成脚本使用独立临时数据库，覆盖双方确认、角色／队长权限、准备限制、共享战场、强化怪物、多目标、整轮共用30秒收集并逐人执行、群攻消耗、禁止单人旁路、审计失败回滚、重复胜利回执及重启恢复。

还覆盖活跃战场重启、超时防御审计、提交失败回滚和后续快照解除保守移动锁。设置 `GODOT_BIN` 时由真实客户端与独立网络队友接受邀请、准备、轮流行动及播放胜利返回。

## 整轮30秒与逐人播放（本地源码，未部署）

- `team_rules`：14项规则测试，包含任意队员先选、全员提交前不扣资源、共同截止时间不重置、重复指令锁定、超时全员默认防御、逐只怪物行动、倒下者跳过、目标被击败后重选、队列JSON重读、技能群攻／辅助和独立播放预算。
- `run_teams.py`：真实等待完整30秒，确认期间不提前结算、截止后一次执行全部指令、跨轮旧指令拒绝；另测同快照修订并发提交、已选指令与截止时间随服务重启保留、团灭后各自留坟／出生，以及灵魂队员独立行走。仅本脚本新建数据库的部分后续回合跳过播放预算来缩短验收，不修改生产时钟或数据。
- `res://tests/team_round_test.tscn`：5人5怪同时显示，指令确认不扣血、不播放，依次检查10个原生动作无重叠、血条命中更新、重复事件修订不重播、新轮完整30秒。`SSJX_TEAM_ROUND_FIXTURES` 可输入实际服务端快照 `work/soul-recovery/team-server-fixtures.json`。
- 实际OpenGL ES离屏截图位于忽略目录 `work/soul-recovery/round-*.png`；`SSJX_TEAM_CAPTURE` 指定输出目录。

2026-10-20本轮结果：Rust全量111项通过（其中组队规则14项）；真实服务端／PostgreSQL／WebSocket组队122项通过，包含真实Godot客户端11项；跟随回归35项、参战范围回归48项通过。Xvfb + Mesa实际离屏新回合64项、原组队界面回归81项通过，已人工检查选择窗口、玩家行动和怪物行动截图。新回合64项包含本轮真实服务端快照校验，而非仅手造数据。

```sh
GODOT_BIN=godot python tests/run_teams.py
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb \
SSJX_TEAM_CAPTURE="$PWD/work/soul-recovery" \
SSJX_TEAM_ROUND_FIXTURES="$PWD/work/soul-recovery/team-server-fixtures.json" \
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py --path client \
  --rendering-method gl_compatibility --rendering-driver opengl3_es \
  res://tests/team_round_test.tscn
```

`res://tests/team_test.tscn` 覆盖多角色布局、原版指令／查看面板、选敌、技能、一次施法、重试、墓碑和本地角色隔离；`SSJX_TEAM_CAPTURE` 指定实际渲染截图目录。

同一渲染测试也覆盖队伍头像成员卡、五人滚动且刷新保留位置、固定底部管理按钮、长姓名、暂离／离线、空队伍、解散确认和左侧邀请互不重叠。截图包括 `team`、`team_five`、`team_five_bottom`、`team_confirmation`、`team_empty`、`team_invitation`。`duel_test.tscn` 额外检查邀请正文与确认／拒绝触控区域不重叠，截图保留 `invitation`。队内聊天仍未接通，不在这些测试通过范围内。

跟随验证使用独立临时数据库和真实 WebSocket，覆盖默认跟随、暂离、手动移动拒绝、逐人传送条件、快照保留过图路线、换房、服务重启、队长移交、移出及解散。设置 `GODOT_BIN` 时额外运行 `res://tests/team_follow_live_test.tscn`，由真实客户端无手动输入地跟随并自动过图；`team_test.tscn` 同时验证原包三色旗帜、名字旁定位和暂离按钮。

持久化依赖 `0019_teams.sql` 和 `0022_team_follow.sql`。上述入口不能替代千人组队混合负载验收。

`run_team_participation.py` 使用独立 PostgreSQL 与真实 WebSocket，验证离线成员不阻塞、在线跟随队员仍需准备、三人队籍仅两人参战的强化倍率、缺席者重连不能补入战场、暂离且已准备仍不参战、仅队长时按当前单人规则随机1至3只怪并采用战场冻结的数值版本、胜利重试不重复奖励，以及未参战者资源／药品／任务／冷却不变。`team_rules` 覆盖单人推进回合和胜利；`team_test.tscn` 覆盖单人战场接收与两名战斗实体、查看面板、空参战名单拒绝和未参战提示，截图 `team_solo`。


## 持续准备与实际播放完成确认

战斗结束不再清空队员准备偏好；取消准备和暂离仍有效。服务端通过`playback_ready`数组声明支持动画完成回执，新客户端在完整播放动作、特效、反应和死亡动画后自动发送`playback_done`，所有存活参战者确认即可提前开启下一轮，仍保留完整30秒。旧客户端／断线沿用原播放预算兜底，不会无限等确认。无需新数据库迁移；战场JSON兼容旧记录，确认写入、幂等回执和审计共用事务，不写角色资源或再次结算奖励。

验证结果：Rust全量测试通过，其中组队规则17项；五人五怪回放专项69项（headless和实际OpenGL均通过）、组队客户端69项、单人遭遇55项、状态图标27项通过。真实PostgreSQL／WebSocket组队126项通过，包含真实Godot客户端12项；确认生产客户端实际发出了已接受的动画完成回执。参战范围专项52项通过。

新增覆盖：胜利／撤退后连续开战、取消准备阻止迎战、单人确认不截断其他队友的播放、全部确认提前开放、完整30秒、陈旧回合和无关目标拒绝、重复操作编号不改变窗口、审计失败回滚、确认前后角色资源及修订不变、确认状态JSON重读、倒下者跳过和旧客户端计时兜底。真实客户端首轮使用防御确保至少播放到下一轮。参战范围旧断言更新为现行技能平衡和随机单人多怪契约，随机掉落先明确放弃再验证暂离；没有修改战斗数值或跳过奖励约束。
