# 雷霆一击眩晕验证

## 规则与隔离

`sheet_010` 保留5级解锁、单体伤害和原灵力预算；现代新战斗命中后35%概率令目标跳过下一次行动，受击不解除，技能冷却3回合。与睡眠／封印共用控制保护。眩晕是一次行动令牌，不在回合末直接递减；目标已行动时留到下一轮。技能表生成器明确标注为新增玩法，非原版恢复。

新建本地、联机阵列（单人／组队）和切磋战斗时，在技能状态的 `balance.stun_revision=1` 冻结规则；既有存档缺字段视为0，继续原雷霆一击和原冷却，不在加载或重连时自动升级。目标状态可选 `enemy_stun` 仅允许0／1，缺省0。伤害不清除它，目标消费一次后清空；阵列中的状态归属目标，切磋沿用施加者保存 `enemy_*` 的既有约定。死亡／精英复活清理该状态。

当前旧 `solo-v1` 服务入口不声明现代阵列能力，保留原行为；正常客户端使用的 `encounter_version=2` 单人阵列已接入。联机需要同步更新服务端和客户端，技能目录摘要变化不允许旧客户端误读新状态。无数据库结构迁移，不改操作编号、回执和奖励规则。

## 规则测试

```sh
python -m unittest discover -s tests -p 'test_skill_catalog.py'
godot --headless --path client res://tests/stun_rules_test.tscn
godot --headless --path client res://tests/skill_rules_test.tscn
cargo test --locked --manifest-path server/Cargo.toml \
  --test stun --test skills --test skill_balance --test team_rules --test duel
cargo build --locked --manifest-path server/Cargo.toml
python tests/run_stun.py
```

2026-10-23：

- 生成目录6项通过，明确检查仅雷霆一击新增眩晕、保留原伤害／消耗及重建来源声明。
- Godot 4.7.2 眩晕专项322项、原技能固定向量408项、队伍客户端70项、切磋客户端46项通过。
- Rust眩晕5项、原技能9项、技能预算5项、队伍17项、切磋16项通过。覆盖100个概率边界、冷却、免控共享、受击不解除、未命中、旧状态序列化、后手眩晕保留至下一轮、被眩晕者不消耗已选技能的灵力／冷却。
- `run_stun.py` 在自行创建的临时 PostgreSQL、Rust 服务和真实 WebSocket 下通过：实际概率触发、整次怪物行动跳过、冷却拒绝、原编号回放、断连／进程重启保持结果、回执写入故障整笔回滚、原编号重试及旧版本存档不升级。仅在临时数据库将测试目标气血加大以避免提前击杀，不修改生产地图定义。

本轮未打包、部署或推送，不访问生产数据库或玩家存档。
