# 未命中闪避反馈回归

2026-10-21。Godot与Rust源码验证，未部署、打包或推送。真实联调使用自动创建并销毁的隔离PostgreSQL容器和服务进程，没有操作现有数据库或正在运行的服务。

- Rust全量原回归通过，新增 `dodge_feedback` 4项通过：普攻与技能逐目标未命中、怪物未命中无伤害／反伤／流血、旧状态兼容与重置、切磋事件与防御零伤害区分。
- `dodge_rules_test.tscn` 11项通过，验证混合命中／闪避群攻、逐目标标记隔离、未命中清理前一目标暴击、旧快照兼容，以及错误布尔类型／有伤害却标记闪避的回包拒绝。
- 实际OpenGL `dodge_presentation_test.tscn` 28项通过：双方向外短退、完整回位、取消恢复、主题文字、无零伤害／暴击闪、命中前不提前闪避、反击等待和血条跟随、群攻混合结果、旧单人PVE与切磋双方复用、相同修订不重复播放。
- 真实HTTP／WebSocket／数据库精英遭遇回归41项通过，回包经过Godot新校验器；包括事件持久化与恢复、回执重放、有限复活、组队触发和事务失败回滚。
- 组队回合54项、切磋客户端38项、本地技能时序26项、伤害数字23项、单人遭遇55项、精英22项、血条定位54项、技能音效22项、旧联机界面71项、原生战斗流程100项通过。技能时序测试主动关闭应用时钟，补充手动推进新增闪避时钟，保留技能全部特效结束前不得反击的断言。原生受击回归固定一个合法命中种子并使用实际换装元数据，继续严格检查hurt／原生回弹；未命中另由专用闪避测试覆盖。

```powershell
cargo test --offline --manifest-path server/Cargo.toml --target-dir work/monster-combat-target --test dodge_feedback
godot --headless --path client res://tests/dodge_rules_test.tscn
godot --path client --rendering-method gl_compatibility res://tests/dodge_presentation_test.tscn
```

画面与日志位于忽略的 `work/battle-dodge.png`、`work/dodge-*`；没有提交测试账号、角色存档和运行回包。浏览器／Android发布包尚未导出，本轮不代表公网客户端已经更新。
