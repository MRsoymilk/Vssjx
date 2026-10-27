# 气血葫芦与灵力葫芦

规则见[商城设计](../design/shop_catalog.md#可补充储量的气血灵力葫芦)。2026-10-27两种容量均提高至999999，见本文末尾新增验收。以下2026-10-23结果为初次接入的历史记录，使用隔离 PostgreSQL、真实 Rust HTTP／WebSocket 和 Godot 4.7.2 验证。

## 验证结果

| 入口 | 结果 |
| --- | --- |
| Rust `pve::consumable_tests` | 5项通过，含2项葫芦边界及3项原药品／洗点回归 |
| Rust `pve_rules`／`team_rules`／`endless` | 3＋17＋4项通过 |
| `tests/run_gourds.py` | 59项真实服务检查通过 |
| Godot `gourds_test.tscn` | headless与实际OpenGL各395项通过 |
| `tests/run_full_shop.py` | 原208项物品逐项购买／装备或使用／丢弃，983项检查通过 |
| Godot 完整商城／重生丹／单人／无尽／寻尸／异步存档／本地多角色 | 1,641＋181＋55＋52＋461＋67＋27项通过 |
| Python 完整目录／初号机资产 | 5＋8项通过 |

真实联机覆盖：

- 无葫芦不恢复；购买自动开启、仅恢复对应资源；满值不消耗；关闭后重连保留关闭状态；不足时精确耗尽但保留库存。
- 限持一个、数量限制、原葫芦药品仍恢复70点；不能将容器直接使用／装备；丢弃同步删除储量；铜钱不足与满包不扣款、不创建储量。
- 普通与AI地图的有效NPC补充，拒绝怪物、异图NPC、远距离、满储量和灵魂状态；关闭开关时补满不恢复角色，保留开关。
- 相同操作号重放、旧修订拒绝、进程重启与重连；角色HP／MP和储量只在一个事务内提交。实际触发回执写入失败、战后储量写入失败，检查角色、战斗、储量和回执回滚，原请求可重试一次。
- 单人回合与战中重连不消耗；撤退及胜利按最终缺口恢复，保留战斗快照原血蓝；组队成员在回合内不补给，结束后各自恢复；无尽胜利推进层数并补给；失败／灵魂重连不消耗储量。
- 决斗拒绝葫芦操作，决斗伤害及退出均不改持久化资源或储量；操作审计保留可读的储量变化。

客户端覆盖真实服务回包的正式 `OnlinePve` 解码与旧回执防回滚，拒绝伪造容量、开关类型、拥有容器但缺少储量。离线验证真实文件保存／重读、自动补给与NPC补充写入失败回滚、旧式和阵型战斗结算、死亡限制、背包开关，以及主地图NPC按钮经正常交互路径触发持久化补充。

## 实际渲染

Xvfb＋Mesa llvmpipe OpenGL ES渲染通过。已查看商城、背包剩余量、详情及开关、清微道人、扩展地图巡山人、真实地图补充结果和联机背包截图。发现商城长说明与价格行重叠后缩短摘要，将补充地点放入商城提示及背包详情；增加摘要行数、价格间距、背包文字宽度、详情高度断言。

日志：`/tmp/opencode/gourds-*.log`；截图：`/tmp/opencode/gourds-captures/`。真实回包生成在忽略目录 `work/gourds/server-fixtures.json`。测试不访问正式服务、玩家配置或生产数据库。

## 重跑

```sh
cargo build --manifest-path server/Cargo.toml --bin vssjx-server
cargo test --manifest-path server/Cargo.toml --lib pve::consumable_tests
python tests/run_gourds.py
SSJX_GOURD_FIXTURES="$PWD/work/gourds/server-fixtures.json" \
  godot --headless --path client res://tests/gourds_test.tscn
SSJX_GOURD_FIXTURES="$PWD/work/gourds/server-fixtures.json" \
  SSJX_SHOP_CAPTURE=/tmp/opencode/gourds-captures \
  XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es \
  res://tests/gourds_test.tscn
```

商城目录改动会改变 `catalog_sha256`，使用真实快照的旧专项需要重新生成回包后再运行。文档只对本轮改动文件检查链接、锚点和代码围栏；不将全库既有文档失败项计为通过。

## 原包葫芦图标核对（2026-10-23）

- 按用户最后确认的原商城截图，直接复用红色 `ix62.png` 作为气血葫芦、蓝色 `ix63.png` 作为灵力葫芦，不重绘、不重新配色，也不采用最初的外观参考插画。
- 商城和背包共用 `ShopRules.icon_path()` 的客户端显示映射；原包图片、已有物品ID、旧材料记录、容量、开关与补充规则不变。没有改写 `shop-v2.json`，因此不改变服务端目录摘要，不要求为了替换图标升级数据库或重新生成联机快照。
- `godot --headless --path client res://tests/gourd_icons_test.tscn` 与实际OpenGL各13项通过：检查原图像素直接复用、红蓝映射、商城／背包实际纹理路径、购买后储量及目录摘要。
- 完整商城Godot回归1,641项、Python目录回归5项通过。已查看商城和背包截图：`/tmp/opencode/vssjx-gourds-original-captures/`。本轮未重跑依赖隔离PostgreSQL的葫芦服务端专项。
- 仅替换显示，不推送、打包或部署。

## 储量上限调整（2026-10-27）

- 气血葫芦和灵力葫芦的容量均提高至 **999999**；价格仍为200铜钱，每种限持一个、仅战斗外自动补给及NPC免费补充等规则不变。
- 只修改 `tools/build_gourds.py` 的两项容量并重建 `client/assets/data/shop-v2.json`。客户端和Rust共用该目录，购买／NPC补充使用新上限；已有存档／库存保留当前余量和开关，不自动补满。旧10000／5000余量继续有效，无需新增数据库迁移或重写历史迁移。
- 两端继续拒绝负数、1000000及更大的储量；新增999999边界、旧余量保存重读／重连和满储量六位数UI宽度回归。
- 服务端内嵌商城目录，需重新编译并与客户端配套更新；目录摘要已变化，联机夹具必须用新服务端生成，不复用此前快照。

新增检查入口：

```sh
python tests/test_full_shop_catalog.py
cargo build --offline --manifest-path server/Cargo.toml
cargo test --offline --manifest-path server/Cargo.toml --lib gourd
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" python tests/run_gourds.py
SSJX_GOURD_FIXTURES="$PWD/work/gourds/server-fixtures.json" \
  godot --headless --path client res://tests/gourds_test.tscn
SSJX_GOURD_FIXTURES="$PWD/work/gourds/server-fixtures.json" \
SSJX_SHOP_CAPTURE=/tmp/opencode/gourds-capacity-ui \
SSJX_OFFSCREEN_SCREEN=1600x1200x24 LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/gourds_test.tscn
```

本轮只在隔离环境验收，未操作正式数据库，未推送、打包或部署。实际界面使用Xvfb与Mesa；本机另设置 `XVFB_BIN=/tmp/opencode/ui-test-xvfb/usr/bin/Xvfb` 和 `LD_LIBRARY_PATH=/tmp/opencode/ui-test-xvfb/usr/lib/x86_64-linux-gnu`。

本轮结果：

| 检查 | 结果 |
| --- | --- |
| Python全商城目录与两种容量／价格 | 10项通过，确认目录仅两项capacity字段变化 |
| Rust葫芦边界、购买扣量、战斗与NPC限制 | 3项通过，离线构建成功 |
| 隔离PostgreSQL + Rust实际联机／重启／旧余量重连 | 61项通过 |
| Godot本地存档、真实快照解析、容量边界和UI布局 | headless及实际OpenGL ES各402项通过 |
| 红蓝原图复用与购买／背包显示 | headless及实际OpenGL ES各13项通过 |
| 完整商城实际渲染回归 | 1964项通过 |
| 文档链接、索引及当前目录数量 | Python 9项通过 |

已审阅两种满容量背包、商城容量及NPC补充后截图；六位数余量／上限不溢出，容量说明不与价格重叠。日志为 `/tmp/opencode/gourds-capacity-*.log`，界面截图位于 `/tmp/opencode/gourds-capacity-ui/` 和 `/tmp/opencode/gourds-capacity-icons/`；生成的测试快照不入库。
