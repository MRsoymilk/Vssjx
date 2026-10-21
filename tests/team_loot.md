# 组队公共战利品：ROLL／放弃

2026-10-21，按用户要求取代最初的组队个人独立装备掉落。只更新源码；未打包、部署。

## 玩家规则

- 胜利后生成一份全队公共装备池：普通概率一件，首领／精英两件，每件分别选择。
- 「ROLL点」由服务端生成1～100点；「放弃」不参与竞争。最高点获得。最高分相同者自动加骰，公平决定归属，加骰结果也保留显示。
- 只有实际参战且职业、性别、等级适用者可ROLL。未参战的暂离／离线成员不能分装；已经参战、之后离线的成员保留已提交的点数及获奖资格。倒下化魂也不剥夺参战资格。
- 独立60秒；未选者超时自动放弃，所有人放弃则无人获得。它不是战斗的30秒指令窗口，不改变整轮收集命令的机制。
- 满包进暂存；同一UUID只发一次，重复点击／HTTP重试／服务器重启不重新抽装备或点数。最后选择、归属、发奖和回执在同一事务，失败可按原操作编号重试。
- 分配未完成前不能换队、踢人、解散或发起新战斗，冻结获奖资格并保留空间。队长不能指定赢家。队长的定向部位决定公共池偏向，不改变骰子。
- 战斗结果后自动弹出，回到地图后仍可从「队伍 → 战利品」打开。展示每个人的等待／ROLL／放弃、点数、同点加骰及最终获得者。

铜钱、修为保持原规则；炼材和首领精华按实际参战者各发一次。仅装备采用公共ROLL，不再向每名成员复制同一场的装备份额。普通遭遇和首领保底按参战者进度合并到公共池，不为队伍外成员增加进度。

## 验证

- Rust4项专项：最高点／放弃、不可改选、非参战者／职业等级限制、超时、全员放弃、独立多件、同点自动加骰、持久化。并纳入161项Rust全量回归。
- 自建临时PostgreSQL、真实三名客户端和正式HTTP服务18项：真实胜利公共池、服务端点数、重复点击拒绝、发奖前不能解散、重启保持点数／期限、同UUID重放、离线赢家、满包暂存、事务故障整笔回滚、首领两件独立选择、两人同修订并发ROLL、真正最高点获得、另一件全员放弃、超时自动放弃与唯一发奖、客户端注入分数被拒绝。
- 正式Godot校验器读取真实回包，实际点击ROLL按钮只提交物品UUID／战斗ID／修订，不提交点数。非法点数／期限拒绝，已选／已分配禁用按钮，队伍原生入口可重开，实际OpenGL专项56项通过。离屏检查等待、已ROLL、已分配以及五人长名字布局；五人样例是基于真回包扩展的呈现夹具，不冒充额外的五人真实服务器测试。
- 另跑原组队回归125项，保留真实30秒全员指令窗口、断线恢复、寻尸及退队行为。已经寻尸的人不会因旧战场仍保留零血快照而在后续ROLL刷新时再次变魂。

源码：`server/src/team_loot.rs` 为纯分配状态机；`teams.rs` 为身份、事务与回执；`pve.rs` 只将原实例写入赢家库存，不恢复资源；`team_loot_rules.gd` 为客户端只读验证，`team_loot_panel.gd` 为正式界面。没有客户端抽点、队长分配、额外行动或生产数据库操作。

```sh
cargo build --offline --manifest-path server/Cargo.toml
SSJX_PROGRESSION_VECTORS="$PWD/work/progression-v1/rust-vectors.json" \
python tests/run_team_loot.py
SSJX_TEAM_LOOT_FIXTURES="$PWD/work/team-loot/server-fixtures.json" \
SSJX_TEAM_LOOT_CAPTURE="$PWD/work/team-loot/screenshots" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/team_loot_test.tscn
```

临时库和账户全部属于测试夹具；生成的回包及截图置于忽略的`work/`目录。不修改或清除线上战利品。
