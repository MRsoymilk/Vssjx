# 固定灵力消耗与固若金汤

2026-10-26：按用户确认，仅修改技能灵力消耗和固若金汤，其余技能伤害、回血、反伤、触发概率与恢复灵力规则保留。

所有主动技能按技能表 `mp_cost` 固定扣除 9～24 点灵力，不再按最大灵力的比例扣除。被动技能仍为 0。技能选择器、技能书、本地遭遇战、联机单人、组队和决斗共用此规则；增加最大灵力不会提高单次技能消耗。

固若金汤消耗 15 点灵力，施放当回合及下一回合生效。每次物理或法术直接攻击在已有防御和防御行动结算后再固定抵挡 25 点伤害，最低降至 0。该效果不增加攻击方伤害，不改变角色基础属性，不削减流血等持续伤害。多怪、多段攻击分别抵挡；同类护体替换而不叠加。天罡战甲保留既有百分比护体规则。

新增可选状态字段 `defense_flat`，缺省为 0，旧存档无需迁移。施放新的固若金汤清除原百分比护体值；施放其他护体清除固定抵挡值。在途旧护体状态按原值继续至失效。技能目录及平衡规则哈希更新，客户端和服务端须一起更新；代码提交不会自动更新线上服务或安装包。

回归覆盖：全部技能在不同最大灵力下的固定消耗；低于/恰好等于消耗时的菜单行为；物理、法术、零伤害、完全抵挡、极大伤害及两回合失效；其他技能规则不变；单人、多怪、决斗实际结算；真实临时 PostgreSQL 中的扣费、回执重试、重连和进程重启；服务端快照通过客户端解码。

运行专项：

```text
cargo test --offline --manifest-path server/Cargo.toml
python tests/test_skill_catalog.py
python tests/test_balance_contract.py
python tests/run_skill_balance.py
python tests/run_fixed_skill_costs.py
godot --headless --path client res://tests/fixed_skill_cost_test.tscn
godot --headless --path client res://tests/skill_rules_test.tscn
godot --headless --path client res://tests/skill_battle_test.tscn
godot --headless --path client res://tests/stun_ui_test.tscn
```

联机测试仅启动独立临时数据库和测试服务。没有访问玩家数据库，没有打包、推送或部署。

本次验证结果：Rust 全量 213 项通过、1 项既有临时数据库审计检查按原标记跳过；客户端专项与回归 1,035 项通过（含 72 组 Rust/Godot 技能结果和状态对照）；真实数据库联机检查 24 项通过；Python 目录与镜像契约 14 项通过。36 组基础技能向量中，仅固若金汤状态发生预期变化，其余 35 组保持一致。
