# 候选数值内核验证

[设计与阶段边界](../design/combat-balance.md) · [测试索引](testing.md)

本轮是A1：验证可复现的新数值内核，不启动新掉落、不修改玩家资产，不表示正式战斗已切换。旧规则仍负责当前游戏。

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

未打包、部署或推送；尚未执行新战斗协议的联机验收，也未完成六流派胜率、掉落经济与终局装备强度的仿真，这些依赖后续接线。
