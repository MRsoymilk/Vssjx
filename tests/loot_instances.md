# 装备实例B阶段验收

2026-10-21。只在源码及自建测试数据库／独立存档验证；未打包、部署或推送，不操作玩家数据库。

## 范围

- `loot-v1` 独立UUID、物等、白／蓝／黄品质、部位词缀与双端属性聚合。
- 固定装备镜像迁移、同底材多件、共享背包容量、领取暂存、装备／卸下、所有权及修订验证。
- 实际背包“菜单 → 装备实例”入口；背包图标、物等、人物预览、选角、世界与战斗使用同一实例外观。
- 一次确认保存后编号／词缀不变；持久化失败回滚；换装不回血，寻尸流程不受影响。
- 穿透、增伤、持续增伤、评级、暴伤和额外减伤实际进入计算；技能与PvP继续使用各自既有规则。
- 旧商城和原有装备图像不改，固定装备不重抽、双计或自动变为传奇。随机奖励、流派套装及打造仍待C/D。

## 证据

本轮结果：Rust全量145项、真实服务20项、实际OpenGL专项2200项、参数镜像契约5项均通过。相关客户端回归：异步持久化67项、本地角色27项、控制指令59项、寻尸461项、商城1638项、属性80项、战斗防卡322项、单人阵列55项、闪避呈现28项通过；先前“零失败”但含脚本错误的异步测试已修正并重跑，不计作通过证据。

`server/examples/loot_vectors.rs` 直接输出实际Rust结果：三职业×两性别×十部位×三个物等×三品质，共540组；Godot逐组检查抽取结果、完整属性、属性面板、伤害、持续伤害、暴伤、命中与承伤。此处的同种子是可复现开发验收，不是联机客户端能提交的抽取参数。

`tests/run_loot_instances.py` 使用独占临时PostgreSQL、真实Rust服务与WebSocket验证20项：旧库存一次迁移、同底材独立副本、只穿一件、角色修订过期拒绝、UUID跨角色拒绝、原UUID重放与变更请求冲突、事务失败回滚及重试、进程重启、选角／社交属性外观一致、真实单人阵列冻结数值、战斗中拒绝换装、共享满包及领取原暂存实例。真实回包交给Godot正式校验器与背包界面，界面仅提交UUID和修订。

新增专项还覆盖：本地真实文件重读、迁移写失败前不发布新编号、保存失败整笔回滚、魂态拒绝、满包拒绝、非法词缀／重复UUID拒绝、控制指令降级后存档仍可读取、有界大库存封包和正常原生背包入口。实际OpenGL画面已检查，截图位于忽略的 `work/loot-instances/panel.png`。

原有属性／异步存储测试中，旧推荐加点和旧NPC按钮／传送等待已落后于现有源码；本轮按实际版本更新固定断言与真实入口，不放宽失败回滚要求。闪避专项改用现有角色映射，而不是不存在的`_w1_c0`资源别名。独立命中测试仍覆盖闪避；持久化测试使用合法固定命中种子避免随机击空跳过结算。

## 复现

```sh
mkdir -p work/loot-instances
cargo test --offline --manifest-path server/Cargo.toml
cargo build --offline --manifest-path server/Cargo.toml
cargo run --offline --manifest-path server/Cargo.toml --example loot_vectors \
  > work/loot-instances/rust-vectors.json
SSJX_LOOT_VECTORS="$PWD/work/loot-instances/rust-vectors.json" \
python tests/run_loot_instances.py
SSJX_LOOT_VECTORS="$PWD/work/loot-instances/rust-vectors.json" \
SSJX_LOOT_FIXTURES="$PWD/work/loot-instances/server-fixtures.json" \
SSJX_LOOT_CAPTURE="$PWD/work/loot-instances/panel.png" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/loot_instances_test.tscn
```

截图和向量验证不证明终局平衡，也不等于六流派胜率或刷装经济已验收。迁移0026已在前阶段提交，本轮不改写历史迁移、不向线上运行库执行迁移。
