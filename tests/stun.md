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

## 状态图标与实际播放

```sh
godot --headless --path client res://tests/stun_ui_test.tscn
godot --headless --path client res://tests/battle_status_test.tscn
mkdir -p /tmp/opencode/vssjx-stun-captures
SSJX_STUN_CAPTURE_PATH=/tmp/opencode/vssjx-stun-captures \
  LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py \
  --path client --rendering-driver opengl3_es res://tests/stun_ui_test.tscn
```

- 新状态图标逐字节复制原包 `tx41_frame001.png`（`t14` 环状金色星芒），生成器及目录均记录来源和 SHA256。眩晕对应关系为本次语义适配，不冒充已恢复的原版绑定。
- 待消费状态从权威快照恢复；实际跳过行动的 `stun` 事件只显示待机、状态图标和“眩晕 · 无法行动”，不播放攻击、不移动、不产生伤害数字。阵列在该事件播放后按最终状态清除临时图标，取消时立即清理；切磋保留双方事件顺序，按相对施加者解析状态归属，不把受控者画到施加者身上。
- 图标说明使用“剩余1次行动”，不把它误写成回合末自动递减。切磋提示气泡上移，避免遮住眩晕图标。战斗技能选择使用短说明保证可见，完整规则保留在悬浮提示；武功页同时显示35%眩晕、原160%威力／9%最大灵力消耗和3回合冷却。旧在途战斗显示原说明与原冷却，不许诺未启用的眩晕。
- Godot逻辑UI专项28项、Xvfb＋Mesa OpenGL实际渲染32项通过，已检查技能选择、武功页、阵列眩晕和切磋眩晕4张截图。状态条28项、技能战斗120项、技能固定向量408项、单人阵列55项、技能预算3项、本地技能时机26项、队伍70项、切磋46项回归通过。
- Rust全套测试零失败，保留原有数据库审计专项1项忽略。最终数据目录更新后再次运行真实隔离 `run_stun.py` 通过。未声称完成手机或浏览器真机验收。
