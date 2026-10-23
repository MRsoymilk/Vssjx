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

## 2026-10-23 分配界面卡住修复

复查线上审计可见大量`TEAM_LOOT_PENDING`拒绝，但只读检查时没有未结算公共池。客户端可复现的原因是：ROLL面板作为战斗页的子节点，胜利提示1.6秒自动返回时，面板一起隐藏，服务器却仍等成员选择。

现在战斗页、队伍页均在共同父级打开同一独立弹层，父页面隐藏不影响ROLL；页面销毁时清理弹层，不留遮挡物。超时后显示“正在确认分配”，最终归属仍来自服务器。已明确返回的`LOOT_STORAGE_FULL`清除未提交的待确认指令，提示整理库存，不再无限重试；网络未知结果仍保留原操作编号。

新增实际胜利自动返回后面板仍可见、按钮仍提交原物品选择、关闭队伍页不藏面板、入口不重复创建弹层以及确定拒绝不锁死发件箱的回归。真实服务器18项、Godot逻辑63项通过，实际OpenGL另覆盖完整分配截图。未手动发奖、清空分配记录、修改线上角色或缩短60秒规则。

## 2026-10-23 跨战斗弹层残留修复

使用临时 PostgreSQL、真实三人HTTP／WebSocket流程取得连续战斗回包，再经正式 Godot 校验器和 `OnlineWorldView` 重放。修改前生命周期专项51项中12项失败，实际复现：上一场分配完成后弹层没有关闭，下一场开始仍遮挡；跳过中间战斗快照时，同一旧面板直接切换成新一场装备，旧按钮回调可以提交新池选择；超时禁用的按钮会被 `refresh()` 重新启用。基线日志保留在 `/tmp/opencode/vssjx-loot-lifecycle/baseline.log`。

修复将弹层绑定角色／队伍／战斗ID，失效时同帧隐藏、禁用按钮、清理输入拦截并释放。新战斗没有分配入口，后续池创建新面板；只有同一战斗的窗口可复用。等待中的池收到全部发放确认后展示结果3秒再关闭；重复轮询不重置计时，已完成结果仍可手动打开阅读。超时仍等待服务器确认，刷新和按钮回调都检查截止时间。源码未调整服务端分配算法。

本轮验证（Linux、Godot `4.7.2.stable.gentoo.ed1daf0bf`）：

| 入口 | 结果 |
| --- | --- |
| Rust `team_loot` | 4项通过 |
| `run_team_loot.py` 临时数据库与真实三人请求 | 22项通过 |
| Godot `team_loot_lifecycle_test` | 54项通过 |
| Godot 原有分配／队伍／共享回合回归 | 65＋70＋69项通过 |
| Xvfb＋Mesa llvmpipe 实际OpenGL渲染 | 生命周期56项、原有分配69项通过 |

新增覆盖正常胜利返回、全员完成后自动关闭、手动重看、重复快照、队友立即开战、真实异步资源准备、漏过中间战斗的恢复、超时确认、重连、显式关闭、队伍消失和空池。服务端实际验证待分配时挑战被拒绝，分配完成／超时后可以开新战斗，新战斗不含旧池，旧分配请求不能重复发奖。

已查看 `lifecycle-distributed.png`、`lifecycle-next-battle.png` 与原分配截图：下一场战斗菜单可正常选择，无旧弹层遮挡。截图与运行日志位于 `/tmp/opencode/vssjx-loot-lifecycle/`；本轮真实回包为忽略目录 `work/team-loot/server-fixtures.json`、`lifecycle-fixtures.json`。

```sh
# 先运行上面的 run_team_loot.py；它现在同时输出 lifecycle-fixtures.json。
SSJX_TEAM_LOOT_LIFECYCLE_FIXTURES="$PWD/work/team-loot/lifecycle-fixtures.json" \
  godot --headless --path client res://tests/team_loot_lifecycle_test.tscn
SSJX_TEAM_LOOT_LIFECYCLE_FIXTURES="$PWD/work/team-loot/lifecycle-fixtures.json" \
  SSJX_TEAM_LOOT_CAPTURE=/tmp/opencode/vssjx-loot-lifecycle/captures \
  LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py --path client \
  --rendering-driver opengl3_es res://tests/team_loot_lifecycle_test.tscn
```
