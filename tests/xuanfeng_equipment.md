# 玄锋行装接入验收

[测试导航](testing.md) · [成品设计与规则](../design/xuanfeng-equipment.md) · [商城规则](../design/shop_catalog.md) · [生产记录](../analysis/ai-generated/equipment/xuanfeng/README.md)

2026-10-27，验收三职业男女六套：破阵、斩月、逐影、流萤、观星、照夜。采用正常人形比例、开面／半覆面硬盔、黑银衣装及暗红饰边，不以单张待机图代替动作图集。

## 接入范围

- 30张原生部件图集、60张32×32独立图标，六张最终80×80母版及可重建的输入／产物摘要；49份新增Godot原生资源，总资源与场景数由1490增至1539。
- 商城新增60件，共519件；每套十槽，武器140铜钱／攻击14，其余九件各70铜钱／防御3，全套770铜钱，无额外套装技能。
- 职业／性别限制、头部／衣服／武器独立换装、跨系列混穿、本地购买／穿戴／保存重读及联机权威目录／广播／重连。
- `0044_xuanfeng_equipment.sql`前向迁移保留旧库存、UUID、数量、穿戴、实例／绑定和葫芦状态，并继续约束装备单件、十槽映射及每槽唯一穿戴。未修改历史迁移。

## 实际结果

| 检查 | 结果 |
|---|---|
| 六角色素材、脸区／下发接缝、原生关节遮罩、武器握持、目录和迁移一致性 | Python 8项通过，90张PNG逐字节可重建 |
| 全素材回归（含玄锋） | 39项中36项通过、3项按原规则跳过 |
| Godot原生资源与全商城目录 | Python各9项通过，1539份资源／场景检查无差异 |
| Rust权威商城、职业／性别与跨系列混穿 | 9项通过，离线构建成功 |
| 临时PostgreSQL + Rust实际购买／穿戴／广播／重连 | 203项通过 |
| 459件旧库存升级、60件新增物品与约束 | 529项通过 |
| Godot实际界面与真实服务器夹具解析 | 520项通过 |
| 全原生动作、时序、战斗锚点与实际合成帧 | 1590项通过，导出147张动作帧 |
| 全商城实际渲染、原版购买／穿戴与图标回归 | 1964项通过 |
| 六个原生人物全部帧像素一致性、原有换装攻击及锚点 | 525项通过 |
| 文档本地链接、设计索引、性质声明与目录数量 | Python 9项通过 |

Godot版本：`4.7.2.stable.gentoo.ed1daf0bf`。实际界面使用独立Xvfb、Mesa llvmpipe和OpenGL ES 3.2，虚拟屏幕1600×1200；不使用纯headless结果代替渲染验收。已读图审阅六角色全部动作联系表、六套商城商品、地图、背包和管理页截图。头盔随原生头部动作，衣装和武器沿用原生层级与握持；其他职业不增加原生没有的施法动作。

首轮全商城检查有2项失败：帽子分类测试仍写33件，新增六顶后应为39件。仅修正对应数量和说明，完整重跑1964项通过，未放宽分类或物品检查。

## 复现

在仓库根目录执行，数据库集成使用脚本自建并销毁的PostgreSQL，不连接正式库：

```sh
python tools/build_xuanfeng_equipment.py --check
python tests/test_xuanfeng_assets.py
python -m unittest discover -s tests -p 'test_*assets.py'
python tools/build_godot_actors.py --check
python tests/test_native_actor_resources.py
python tests/test_full_shop_catalog.py
python -m unittest discover -s tests -p test_documentation.py
python tools/build_xuanfeng_migration.py --check
cargo build --offline --manifest-path server/Cargo.toml
cargo test --offline --manifest-path server/Cargo.toml --lib shop::tests
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" python tests/run_xuanfeng_equipment.py
python tests/run_xuanfeng_migration.py
godot --headless --path client res://tests/hero_appearance_test.tscn
```

数据库环境使用本地已有的 `postgres:17-bookworm` Docker镜像。服务端测试生成隔离夹具 `work/xuanfeng-production/live-fixtures.json`，仅供测试，不含真实玩家数据。

真实界面复现需要Xvfb、Godot及Mesa，先创建截图目录：

```sh
mkdir -p /tmp/opencode/xuanfeng-ui
SSJX_OFFSCREEN_SCREEN=1600x1200x24 LIBGL_ALWAYS_SOFTWARE=1 \
SSJX_EQUIPMENT_LIVE_FIXTURE="$PWD/work/xuanfeng-production/live-fixtures.json" \
SSJX_EQUIPMENT_GAME_CAPTURE=/tmp/opencode/xuanfeng-ui \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/xuanfeng_equipment_test.tscn
SSJX_OFFSCREEN_SCREEN=1600x1200x24 LIBGL_ALWAYS_SOFTWARE=1 \
SSJX_XUANFENG_ACTION_CAPTURE=/tmp/opencode/xuanfeng-actions \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/xuanfeng_animation_test.tscn
SSJX_OFFSCREEN_SCREEN=1600x1200x24 LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/full_shop_test.tscn
```

本机另设置 `XVFB_BIN=/tmp/opencode/ui-test-xvfb/usr/bin/Xvfb`、`LD_LIBRARY_PATH=/tmp/opencode/ui-test-xvfb/usr/lib/x86_64-linux-gnu`。本轮日志为 `/tmp/opencode/xuanfeng-{server,migration,animation,ui,full-shop}.log`；动作图及六份联系表位于 `/tmp/opencode/xuanfeng-actions/`，界面截图位于 `/tmp/opencode/xuanfeng-ui/`。这些临时验收产物不入库。

人工动作复核入口：`godot --path client res://tests/xuanfeng_review.tscn`，六角色并排对照原人物和整套穿戴，可切换动作；本轮已实际渲染并审阅该场景。

## 边界

本轮针对源码及隔离Linux运行环境，未重新验收Web、Android或手机真机，未操作正式数据库、推送、打包或部署。不将本次素材或集成专项结果当作全工程、全部平台或线上版本的验收结论。
