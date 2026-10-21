# 六流派与传奇／套装C阶段验收

2026-10-21，源码、自建临时PostgreSQL、实际Rust/Godot规则及OpenGL离屏画面；未打包、部署或推送。

## 结果

- Rust全量152项通过（本阶段新增7项），覆盖两件／四件阈值、传奇独立激活、两者叠穿、非法职业／部位、冻结旧快照、流血时钟、蓄势单次消耗、群攻缓存、毒眠控制保护、夺灵回复与后续持续伤害。
- 60组Rust实际生成的流派／性别／装备组合（无特效、两件、四件、传奇、传奇加四件），逐步输出完整属性、实际技能轮转、伤害、气血灵力和持久化蓄势。Godot实际OpenGL专项642项通过（包含6种真实服务器回包），不是只对照静态目录或截图。
- 真实服务端35项通过：六职业流派的真实属性、单人战斗冻结、成功技能蓄势／流血、没有额外回合、相同请求重放不重复回血或积层、重启后快照／资源／状态一致。装备在独占测试库中植入以隔离C规则；生产掉落尚未在此阶段启用。
- B阶段客户端专项2199项回归通过；共享参数契约6项通过。原有装备仍原数值／原外观，不把固定破天斧或EVA套装自动改成新传奇／绿色套装。

## 边界

三职业各两条流派，传奇对应单个指定部位；绿色按2/4件，不占满原十槽。战斗只消费冻结的`balance.builds`，不是运行中查询角色背包。旧快照的缺字段默认无特效。蓄势按一次动作消费，群攻每个合法目标都收到相同增伤，而回血／回蓝只结算一次。全队回春只让施法者蓄元，不为其他穿同装备的队友蓄元。毒眠附伤只在成功施加睡眠时生效，不跳过控制保护期，不唤醒睡眠，不改变持续时钟。PvP传奇回血按既有60%恢复预算结算，伤害仍35%。零血角色不能靠传奇复活。

暂不包含自然掉落、分解、洗炼或强化，均属D。没有把本阶段规则检查冒充最终数值仿真。完整终局的装备强度、六路线取胜轮数和材料产消仍需随D统一校准。

## 复现

```sh
mkdir -p work/builds-v1
cargo test --offline --manifest-path server/Cargo.toml
cargo build --offline --manifest-path server/Cargo.toml
cargo run --offline --manifest-path server/Cargo.toml --example build_vectors \
  > work/builds-v1/rust-vectors.json
SSJX_BUILD_VECTORS="$PWD/work/builds-v1/rust-vectors.json" python tests/run_builds.py
SSJX_BUILD_VECTORS="$PWD/work/builds-v1/rust-vectors.json" \
SSJX_BUILD_FIXTURES="$PWD/work/builds-v1/server-fixtures.json" \
SSJX_BUILD_CAPTURE="$PWD/work/builds-v1/panel.png" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/builds_test.tscn
```

画面已实际检查：稀有部件列表、传奇名称、已激活阶数、同职业两条路线及滚动说明清晰可读。参数以LF规范化摘要，双端镜像有自动契约检查。独立测试夹具在服务重启时等待真实监听端口，避免日志先打印而首次HTTP请求竞速。
