# 誓约礼装接入验收

2026-10-23，三职业男女六套：夜玫、白蔷、银蔷、绯绡、星兰、月藤。男士西装、女士婚纱／礼裙，力士大剑、侠客双爪、隐者花环水晶法杖，带花饰与丝绸。制作方式及原生输入摘要见[素材记录](../analysis/ai-generated/equipment/vow/README.md)。

## 接入范围

- 30张部件图集、60张32×32物品图标；注册49份Godot原生资源，覆盖完整原生动作与战斗锚点。
- 商城新增60件，共459件；每套十槽，武器140铜钱／攻击14，其余九件各70铜钱／防御3，整套770铜钱。职业／性别限制、头部／衣服／武器独立换装及跨系列混穿生效。
- 本地购买、穿戴、保存重读，以及服务端权威目录、外观广播、重连接入完成。
- `0038_vow_equipment.sql` 扩展物品白名单和十槽映射，保留旧库存、实例状态、葫芦约束及每槽唯一穿戴索引。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 素材、脸区／下发接缝、衣装关节遮罩、武器握持与目录映射 | Python 6项通过，90张PNG逐字节可重建 |
| 原生资源与全商城目录 | Python 9项、5项通过 |
| 旧系列资源回归 | 31项中28项通过，3项按原规则跳过 |
| Rust权威商城与六套职业／性别／混穿规则 | 8项通过 |
| 临时PostgreSQL + Rust实际购买／穿戴／广播／重连 | 203项通过 |
| 399件旧物品数据库升级、60件新增物品及约束 | 469项通过 |
| Godot实际OpenGL ES界面与真实服务器夹具 | 514项通过 |
| 全原生动作序列、时序、战斗锚点、合成帧 | 1590项通过，导出147张实际合成动作帧 |
| 完整商城实际渲染、原版物品购买／穿戴 | 1701项通过 |

Godot版本为 `4.7.2.stable.gentoo.ed1daf0bf`，界面测试使用独立Xvfb及Mesa软件渲染。已审阅六角色待机、行走、攻击、受击和隐者施法的全部导出动作帧；其他职业不增加原版不存在的施法动作。资源转换前1315份原生资源检查无差异，转换后1364份。

日志、商城／背包／地图／管理页截图、六份动作联系表位于 `/tmp/opencode/vow-equipment/`；真实服务夹具为 `work/vow-production/live-fixtures.json`。

## 复现入口

```sh
python3 -B tools/build_vow_equipment.py --check
python3 -B -m unittest discover -s tests -p test_vow_assets.py
python3 -B -m unittest discover -s tests -p test_native_actor_resources.py
python3 -B -m unittest discover -s tests -p test_full_shop_catalog.py
cargo test --offline --manifest-path server/Cargo.toml --lib shop::tests
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" python3 tests/run_vow_equipment.py
python3 tests/run_vow_migration.py
SSJX_VOW_ACTION_CAPTURE=/tmp/opencode/vow-equipment/actions \
  godot --headless --path client res://tests/vow_animation_test.tscn
SSJX_OFFSCREEN_SCREEN=1600x1000x24 LIBGL_ALWAYS_SOFTWARE=1 \
SSJX_EQUIPMENT_LIVE_FIXTURE="$PWD/work/vow-production/live-fixtures.json" \
SSJX_EQUIPMENT_GAME_CAPTURE=/tmp/opencode/vow-equipment/ui \
  python3 tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/vow_equipment_test.tscn
```

本机便携依赖：`XVFB_BIN=/tmp/opencode/vow-deps/run-xvfb`；数据库设置 `SSJX_TEST_PG_BIN=/tmp/opencode/vow-pg-bin`、`SSJX_TEST_PG_WORK_DIR=/tmp/opencode`，动态库路径为 `/tmp/opencode/vow-deps/usr/lib/x86_64-linux-gnu:/tmp/opencode/vow-deps/lib/x86_64-linux-gnu`。

本轮验收针对源码及隔离运行环境；未执行推送、打包或部署。

[测试导航](testing.md) · [商城验证](shop.md)
