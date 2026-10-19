# 组队与多怪验证入口

[设计规则](../design/teams.md) · [技能规则](../design/skills.md) · [测试总览](testing.md)

```sh
cargo test --locked --manifest-path server/Cargo.toml --test team_rules
python -X utf8 tests/run_teams.py
python -X utf8 tests/run_team_follow.py
```

集成脚本使用独立临时数据库，覆盖双方确认、角色／队长权限、准备限制、共享战场、强化怪物、多目标、逐人回合、群攻消耗、禁止单人旁路、审计失败回滚、重复胜利回执及重启恢复。

还覆盖活跃战场重启、超时防御审计、提交失败回滚和后续快照解除保守移动锁。设置 `GODOT_BIN` 时由真实客户端与独立网络队友接受邀请、准备、轮流行动及播放胜利返回。

`res://tests/team_test.tscn` 覆盖多角色布局、原版指令／查看面板、选敌、技能、一次施法、重试、墓碑和本地角色隔离；`SSJX_TEAM_CAPTURE` 指定实际渲染截图目录。

跟随验证使用独立临时数据库和真实 WebSocket，覆盖默认跟随、暂离、手动移动拒绝、逐人传送条件、快照保留过图路线、换房、服务重启、队长移交、移出及解散。设置 `GODOT_BIN` 时额外运行 `res://tests/team_follow_live_test.tscn`，由真实客户端无手动输入地跟随并自动过图；`team_test.tscn` 同时验证原包三色旗帜、名字旁定位和暂离按钮。

持久化依赖 `0019_teams.sql` 和 `0022_team_follow.sql`。上述入口不能替代千人组队混合负载验收。
