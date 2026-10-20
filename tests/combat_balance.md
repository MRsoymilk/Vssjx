# 候选数值内核验证

[设计与阶段边界](../design/combat-balance.md) · [测试索引](testing.md)

A1验证可复现的新数值内核；A2已接入新建战斗并迁移角色，旧在途战斗保留旧规则。尚未启动新掉落与装备养成。仅在自建临时数据库/存档验证，不连接生产服务。

## 覆盖

- Python检查共用参数及固定样例的客户端镜像逐字节相同、基础字段与比例边界有效。
- Rust检查人工固定样例、非法输入、整数上界、1～60级属性预算、防御/暴击曲线单调及上限、群攻和Boss人数预算。
- Godot读取同一人工样例；另载入Rust实际生成的1280组伤害结果，逐项核对等级、极大/极小攻击、防御、暴击、防御指令、穿透、辅助技能零伤害、叠加倍率及取整。
- 实际Xvfb/Mesa OpenGL ES绘制候选数值面板并保存截图；本地内存角色保持不变，不上传或导入联机角色。

## 命令

2026-10-20 A1验收：Python契约检查3项通过；Rust全量115项通过（含候选内核4项专项及大量曲线循环断言）；Godot实际离屏7559项检查通过，其中1280组为真实Rust输出比对。截图 `work/combat-balance-v1/preview.png` 已人工检查，中文、公式示例与“尚未切换”状态正常显示；导入及离屏日志无脚本错误。截图中的检查数在截图保存及最终状态保护检查之前统计，因此面板显示7557、最终日志为7559。

```sh
python tools/sync_balance_data.py
python -m unittest discover -s tests -p test_balance_contract.py
cargo test --offline --manifest-path server/Cargo.toml
cargo run --offline --manifest-path server/Cargo.toml --example balance_vectors \
  > work/combat-balance-v1/rust-vectors.json
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb \
SSJX_BALANCE_RUST_VECTORS="$PWD/work/combat-balance-v1/rust-vectors.json" \
SSJX_BALANCE_CAPTURE="$PWD/work/combat-balance-v1/preview.png" \
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py --path client \
  --rendering-method gl_compatibility --rendering-driver opengl3_es \
  res://tests/combat_balance_test.tscn
```

`work/combat-balance-v1/` 为忽略目录；先创建该目录。Xvfb路径为本机已有便携依赖，不要求其他开发机使用相同路径。也可通过已有的 `XVFB_BIN` 指定本机Xvfb。

A1当时未执行新战斗协议的联机验收；后续A2记录见下。六流派胜率、掉落经济与终局装备强度仿真仍依赖后续接线。未打包、部署或推送。

## A2 实战接线与迁移

2026-10-20：Rust全量118项通过；`run_balance_activation.py` 的真实PostgreSQL/Rust/WebSocket验证13项通过；正式属性页实际离屏12项通过（含服务端实际快照验证）。技能旧向量回归376项、本地控制59项、寻尸456项通过。截图 `work/combat-balance-v1/activation.png` 已人工检查免费重置按钮及物/法属性。

覆盖：旧资源比例迁移、不重复迁移/回满、一次免费重置及审计/存储失败回滚、原UUID重放、不重复消费、单人完整数值冻结与重启恢复、无冻结字段的旧在途战斗继续旧公式、结束后迁移。本地入口同样落盘/重读验证；三职业、60级裸身/固定装备聚合、物理/法术通道和防御评级均有专项规则检查。

```sh
cargo build --offline --manifest-path server/Cargo.toml
python tests/run_balance_activation.py
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb \
SSJX_BALANCE_ACTIVATION_FIXTURES="$PWD/work/combat-balance-v1/activation-fixtures.json" \
SSJX_BALANCE_CAPTURE="$PWD/work/combat-balance-v1/activation.png" \
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py --path client \
  --rendering-method gl_compatibility --rendering-driver opengl3_es \
  res://tests/balance_activation_test.tscn
```

A2尚不宣称完成A3的技能冷却/预算、法术怪AI、六流派胜率或装备经济。旧PVE回执仍按原有版本读取，不改写已提交回执；`attributes-v1` 通过 `formula_revision=3` 表示新版，战斗快照携带可选 `balance` 对象；新客户端同时支持旧快照。源码更新不代表线上或已有APK已更新。

## A3 技能预算、完整回合与怪物

2026-10-20：Rust全量123项通过；Python镜像契约4项通过；真实Rust/PostgreSQL/WebSocket技能联调10项通过；实际离屏205项通过，包含33技能×两个目标规模共66组完整Rust/Godot结果及状态一致性、真实服务端快照和正式技能选择器的费用/冷却拒绝。旧技能向量回归376项通过。截图 `work/combat-balance-v1/skills.png` 已人工检查。

专项覆盖：冷却随战斗持久化、进程重启、拒绝不扣费/不推进、回执重放、冷却结束可再次施放、术法怪确实在第3轮施法、封印抑制、多人DOT来源不覆盖、首领整场预算和PvP虚拟气血不影响世界属性。

`balance_sweep` 使用固定种子执行30,000场同级基准战斗，验证生存与回合数范围。仅代表固定装备、推荐加点与单体基准策略，不是最终流派或掉落经济验收。报告在 `work/combat-balance-v1/sweep.json`。

```sh
python tools/sync_balance_data.py
cargo build --offline --manifest-path server/Cargo.toml
python tests/run_skill_balance.py
cargo run --offline --manifest-path server/Cargo.toml --example balance_skill_vectors \
  > work/combat-balance-v1/skill-vectors.json
cargo run --offline --manifest-path server/Cargo.toml --example balance_sweep \
  > work/combat-balance-v1/sweep.json
SSJX_BALANCE_SKILL_VECTORS="$PWD/work/combat-balance-v1/skill-vectors.json" \
SSJX_BALANCE_SKILL_FIXTURES="$PWD/work/combat-balance-v1/skill-server-fixtures.json" \
SSJX_BALANCE_CAPTURE="$PWD/work/combat-balance-v1/skills.png" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/skill_balance_test.tscn
```
