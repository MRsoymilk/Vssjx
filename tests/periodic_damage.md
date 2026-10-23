# 回合末持续伤害同步验证

2026-10-23，Linux、Godot `4.7.2.stable.gentoo.ed1daf0bf`。规则与事件契约见[组队与多怪战斗](../design/teams.md)。

## 覆盖范围

- Rust 权威规则：五人五怪混合流血、中毒与未来状态键；各来源独立递减、按目标合计；所有恢复事件之后连续输出周期伤害；整批后处理死亡、有限复活与全灭判负。
- Godot 共用阵列：十目标同帧扣血／飘字／重启受伤动作，单目标多状态只显示一个总伤害，人数不增加0.8秒公共窗口；重复快照不重复扣血，过期状态清理，取消播放清理，旧回执兼容。
- 时序边界：连续批次不能跨回合合并；即使下一轮回执提前到达，也等待整批原生死亡结束。复活、胜利提示、指令提交和播放完成回执均遵守等待顺序，新死亡动画不消耗上一批次的时间增量。
- 本地流血／中毒生成与持续时间；真实 Rust before/after 快照经 Godot 生产校验器和表现层验证，各目标最终气血一致；反伤保持原攻击之后的独立事件。

## 结果

| 检查 | 结果 |
| --- | --- |
| Rust `periodic_damage` | 3项通过 |
| Rust `skill_balance`、`elite_hunt`、`team_rules` | 5＋7＋17项通过 |
| Godot `periodic_damage_test`，含 Rust 快照 | 69项通过 |
| Godot 组队回合／状态／精英／防卡死／本地多怪／组队界面 | 69＋28＋22＋322＋55＋70项通过 |
| 临时 PostgreSQL、HTTP／WebSocket `run_elite_hunt.py` | 41项通过，含真实服务回包的 Godot 校验 |
| Xvfb＋Mesa llvmpipe 实际 OpenGL 渲染 | 71项通过，已审阅十目标飘字和同时死亡两张截图 |
| 本阶段文档链接、锚点与代码围栏 | 3项通过 |

截图位于 `/tmp/opencode/vssjx-periodic-captures/periodic-full-formation.png` 与 `periodic-simultaneous-deaths.png`。跨端快照在 `/tmp/opencode/vssjx-periodic-fixture.json`，相邻客户端回归日志在 `/tmp/opencode/vssjx-periodic-results/`。

全库文档检查另有7个既有失败子项：`audio.md`、`battle-hit-feedback.md`、`soul-recovery.md` 缺少设计索引入口，上述三份及 `monster-combat.md` 缺少统一导航声明。已从本阶段修改前的 Git HEAD 提取设计文件独立复现相同7项；基线日志为上述日志目录的 `documentation-baseline.log`。

## 复现

在仓库根目录执行：

```sh
SSJX_PERIODIC_FIXTURE=/tmp/opencode/vssjx-periodic-fixture.json \
  cargo test --manifest-path server/Cargo.toml --test periodic_damage
SSJX_PERIODIC_FIXTURE=/tmp/opencode/vssjx-periodic-fixture.json \
  godot --headless --path client res://tests/periodic_damage_test.tscn
cargo test --manifest-path server/Cargo.toml --test skill_balance --test elite_hunt --test team_rules
cargo build --manifest-path server/Cargo.toml --bin vssjx-server
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" GODOT_BIN=godot \
  python tests/run_elite_hunt.py
SSJX_PERIODIC_FIXTURE=/tmp/opencode/vssjx-periodic-fixture.json \
  SSJX_TEAM_CAPTURE=/tmp/opencode/vssjx-periodic-captures LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/periodic_damage_test.tscn
```

真实联调由 `PostgresFixture` 创建并清理临时数据库；离屏运行需要 Xvfb，可用 `XVFB_BIN` 指定。Godot 专项使用独立测试存档路径。
