# 主城无尽试炼

2026-10-21。主城「灵空台」新增「守境人／无尽试炼」，位于 `[12,15]`，复用现有角色素材；本地、联机均可从原生NPC对白进入。

## 玩法

- 单人逐层挑战一名试炼幻影；胜利后再次与守境人交谈进入下一层。组队时须先退队，不改变普通组队战斗及公共ROLL分装。
- 本轮第一次进入时冻结人物等级 `L`。首层原始属性为：气血 `45+20L`、攻击 `8+3L`、防御 `1+L`；第 `N` 层分别乘 `1+20%(N-1)`、`1+10%(N-1)`、`1+8%(N-1)`，整数向下取整。防御另沿用现有战斗换算一次，不附加首领／精英倍率。
- 战败、撤退或超回合结束本轮，下次从第一层开始；个人最高已通过层数保留。战败沿用当前地图灵魂／坟堆寻尸规则。
- 进入下一层不自动补满血蓝；胜利沿用正常铜钱、修为和普通装备／炼材掉落。奖励按本轮入场等级计算，不随层数倍增；原有升级恢复规则不变。
- 记录按角色独立保存。联机中断或重启可续同一场战斗；本地中断战斗在重读存档时结束本轮，保留最高纪录，不补发未结算奖励。
- 无尽幻影不推进世界任务击杀、居民刷新或精英连战计数。超出当前安全数值范围时明确拒绝进入，不溢出、不偷偷降低敌人属性；并非声称可无限容纳数值。

参数位于镜像 `shared/data/endless-v1.json`／`client/assets/data/endless-v1.json`；原AI地图文件及其哈希保持不变，通过独立参数注入NPC。联机记录迁移为 `server/migrations/0030_endless_trials.sql`。

## 验证

- Rust全量 **165项**通过，含4项无尽专项：各等级连续增长、阶段／纪录状态机、冻结等级、异常记录、NPC注入、数值上限。
- 临时PostgreSQL、正式服务及真实WebSocket **25项**通过：NPC及距离／身份／旧修订限制、首层与第二层实际战斗、入场／胜利事务故障回滚、原操作重试、防重复领奖、重启精确续战、失败寻尸、单人限制、角色隔离。
- Godot实际OpenGL ES离屏 **78项**通过：真实Rust规则向量、本地NPC按钮和战斗／结算、对白换行及敌人名牌、存储失败回滚、中断恢复、退出保存失败仍可继续结算、真实服务回包校验、在线按钮提交及伪造属性／残缺阵列拒绝。人工检查主城、对白、首层截图。
- 相关回归：地图契约23项、参数镜像8项；实服原任务链、普通单人27项、装备20项、寻尸18项、组队ROLL18项通过；实际离屏AI地图2075项、单人55项、本地多角色27项、异步存储67项、寻尸467项、ROLL52项通过。异步存储原测试退出时仍报告一项资源未释放，断言无失败；未将其计为无尽运行错误。
- 原单人实服测试已改用当前遭遇协议和共享首领预算，避免旧版协议在精英阈值处报错；地图实服测试等待新刷新居民位置，并在首领前走正常恢复服务。不修改生产战斗规则以迎合旧断言。

```sh
cargo test --offline --manifest-path server/Cargo.toml
cargo build --offline --manifest-path server/Cargo.toml
cargo run --offline --manifest-path server/Cargo.toml --example endless_vectors > /tmp/opencode/endless-vectors.json
python tests/run_endless.py
SSJX_ENDLESS_VECTORS=/tmp/opencode/endless-vectors.json \
SSJX_ENDLESS_FIXTURES="$PWD/work/endless/server-fixtures.json" \
SSJX_ENDLESS_CAPTURE="$PWD/work/endless/captures" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/endless_test.tscn
```

实服测试仅创建、销毁自己的临时库、账号和服务；截图／回包保存在忽略的 `work/endless/`。此次未推送、打包或部署，现有安装包／线上服务不会因此自动更新。
