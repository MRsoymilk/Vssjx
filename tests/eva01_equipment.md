# 初号机套装离屏与规则验证

## 2026-10-21 原版衣装美化

新版采用原版七阶三层衣装、原生脸型与发型，替换封闭机甲头盔为小型碧玉冠饰。配色为紫甲、玉绿镶边、浅紫高光和少量金色扣饰。30张部件及60个图标已接入正式运行时目录；原物品ID和数值保持。

- `python tests/test_eva01_assets.py`：8项通过，检查90张资源、原包输入哈希、人体轮廓、肤色和下发段、完整图标及六套映射；历史迁移仅核对其当时的394项，不把新增物品反写旧迁移。
- Godot `res://tests/eva01_anatomy_test.tscn`：62项通过。与原版同武器、七阶衣装及同发型的合成图集比较，所有姿势的alpha、裁切位置、动作序列和战斗锚点一致，证明新绘制没有改变头发、衣领、手部及武器连接的轮廓。
- Godot `res://tests/eva01_equipment_test.tscn`：496项通过，覆盖实际购买、十槽穿戴、持久化、混搭、地图、背包和管理界面。使用临时本地存档，不改用户存档或待发联机指令。
- `python tests/test_full_shop_catalog.py`：5项通过；重生再造丹2项回归通过。

使用 `F:/project/Vssjx/work/web-toolchain/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe`。设置 `SSJX_EQUIPMENT_GAME_CAPTURE=F:/project/Vssjx/work/eva01-refinement` 可重建实际界面截图。动作审阅仍用 `eva01_review.tscn`，`SSJX_EQUIPMENT_REVIEW_ACTION` 依次为idle/walk/attack/cast/hurt，并设置 `SSJX_EQUIPMENT_REVIEW_CAPTURE` 指向目标PNG。施法动作仅隐者原本具备，其他职业展示待机回退，不称为新增施法动画。

本轮截图：`work/eva01-refinement/after-idle.png`、`after-walk.png`、`after-attack.png`、`after-cast.png`、`after-hurt.png`、`shop.png`、`inventory.png`、`world.png`、`admin.png`。使用Windows OpenGL实际渲染。未打包、部署、推送，也未操作正式数据库或服务器。

以下为之前版本的历史记录，其中“独角全覆面盔”与86张图片不变等结论只适用于当时的斧头单项改动，不代表此次美化后的资源。

[套装设计](../design/eva01-equipment.md) · [装备规范](../design/ai-equipment-style-spec.md) · [测试导航](testing.md)

2026-10-20，Godot 4.7.2、独立 Xvfb 虚拟显示、Mesa 26.2.4 llvmpipe OpenGL ES 3.2。截图是真实游戏渲染，不以 `--headless` 的无图形逻辑测试冒充离屏截图。没有使用桌面 `:0`、生产账号、正式数据库或真实玩家存档；未打包、推送或部署。

## 初版已通过结果

以下为初版完整资源／隔离联机验证；后续仅力士武器改斧头的最新范围和离屏结果见文末，未将初版联机结果冒充新一轮完整联机测试。

| 检查 | 结果 |
|---|---|
| 新资源、原生帧、握持 alpha、下发接缝、十槽、目录／迁移与哈希 | Python 6 项 |
| 全物品、原包像素与图标来源 | Python 5 项 |
| 旧系列资源 | 骨甲幽光 5 项、冥林异装 4 项，另有 3 项仅适用骨甲幽光的测试按原规则跳过 |
| Rust 权威目录与职业／性别／跨系列混穿／旧协议 | 4 项 |
| 真实临时 PostgreSQL + Rust 服务 | 203 项，六角色购买、穿戴、十槽约束、权威价格／属性、目录摘要、非法 ID／职业／性别拒绝、跨系列混穿、外观广播及重连 |
| Godot 新系列离屏 + 临时服务数据 | **508 项，0 失败**，含本地持久化、全动作帧、地图、商城分类、背包、管理整套对照、外观消息及真实服务器状态解析 |
| 无图形逻辑回归 | 新系列及旧两系列各 486 项 |
| 完整商城 | 1636 项 |
| 原生人物合成与原 ANI 逐帧像素 | 525 项 |
| 资源复现 | 93 个产物／记录重建后逐字节一致 |

文档链接、图片路径、片段和围栏等 4 项局部回归通过；新专题已登记设计索引并注明源码／未部署状态。既有音频、命中反馈专题的全量索引缺口不属于本次装备工作，不通过修改无关文档或放宽检查掩盖。

已查看 `idle-runtime.png`、`walk-runtime.png`、`attack-runtime.png`、`cast-runtime.png`、`hurt-runtime.png`、商城与背包截图。所有职业／性别保持原生像素比例；施法序列只用于原生支持的角色，不为其他职业凭空新增动作。头部、身体、武器可以单独或与旧系列混穿。

## 命令

```sh
python -m unittest discover -s tests -p test_eva01_assets.py
python -m unittest discover -s tests -p test_full_shop_catalog.py
cargo test --offline --manifest-path server/Cargo.toml --lib shop::tests
cargo build --offline --manifest-path server/Cargo.toml
SSJX_TEST_SERVER_BIN="$PWD/server/target/debug/vssjx-server" TMPDIR=/tmp/opencode python tests/run_eva01_equipment.py
godot --headless --path client res://tests/eva01_equipment_test.tscn
```

实际离屏测试需要 Xvfb；可通过 `XVFB_BIN` 指定便携安装，不需要更改宿主系统包。`SSJX_OFFSCREEN_SCREEN` 可设置屏幕尺寸，默认保持旧测试的 `640x960x24`：

```sh
SSJX_OFFSCREEN_SCREEN=1600x1000x24 LIBGL_ALWAYS_SOFTWARE=1 \
SSJX_EQUIPMENT_LIVE_FIXTURE="$PWD/work/eva01-production/live-fixtures.json" \
SSJX_EQUIPMENT_GAME_CAPTURE="$PWD/work/eva01-production" \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility --rendering-driver opengl3_es res://tests/eva01_equipment_test.tscn
```

动作对照场景为 `res://tests/eva01_review.tscn`，沿用 `SSJX_EQUIPMENT_REVIEW_CAPTURE`、`SSJX_EQUIPMENT_REVIEW_ACTION` 和 `SSJX_EQUIPMENT_REVIEW_FRAME`。动作选项 `idle`、`walk`、`attack`、`cast`、`hurt`；已各截取一个固定帧，不将五张截图描述为逐像素人工审阅了所有动作帧。

本机使用 `/tmp/opencode/vssjx-eva01-xvfb/run-xvfb` 及便携依赖；每次测试创建独立显示并在结束时关闭，不触碰用户桌面。输入法／XKB 有非致命提示，Godot 脚本没有错误。

## 修正与限制

首次资源测试发现头盔绘制细节扩宽了下发接缝，已改为最后重新覆盖原始底部接缝并验证完整 alpha。商城首轮回归因旧断言仍只计两系列头饰而失败，已同步为 9 个原包 + 18 个新增头饰并重跑通过；未减少断言或更改原物品。

截图、日志及临时联机夹具在 Git 忽略目录 `work/eva01-production/`。只在临时数据库执行新增迁移，测试结束清理自建容器。没有手机真机、正式导出包、生产多人或性能长稳验收；当前公网客户端不会因源码新增资源而自动更新。

## 力士武器改为斧头（2026-10-20）

按“力士的武器换成斧头，其他不变，离屏测试”，仅将男女力士的武器由 `ezs14` 锤模板改为 `ezs9` 双刃斧模板，保持初号机配色、原生两帧、握持、动作及锚点。图标同步改为斧头，名称改为“高振动破障斧”“高振动镇岳斧”。旧的两张无引用锤图集已移除。

相对于 `86b98cf`：另外 **86 张 PNG 逐字节不变**；完整商城除两个武器名称外完全相同，包括 392 条其他物品记录与两个武器的全部玩法字段；外观清单除这两项武器的部件／名称映射外也完全相同。`axe-change-record.json` 保存上述归一化摘要，新增回归会拒绝范围外改变。物品 ID、价格、属性、职业／性别限制及编码均不变，不新增／改写迁移。

- 资源与范围保持测试 **7 项通过**，完整物品目录 Python 5 项通过，Rust 商城 4 项通过。
- Godot 4.7.2 + 独立 Xvfb + llvmpipe 实际离屏 **496 项通过，0 失败**，含六角色、本地持久化、地图／背包／商城／管理预览。此次不使用旧目录摘要的联机夹具，不将初版的 508 项直接算作新一轮结果。
- 已人工查看男女力士待机、攻击及对应商城图标；另保存行走、受击和攻击指定帧截图，头部／身体和其他四角色保持原样。
- 新截图和日志：`work/eva01-axe-production/idle-0.png`、`attack-0.png`、`attack-3.png`、`walk-2.png`、`hurt-0.png`、`shop-mzs.png`、`shop-wzs.png`、`rendered-equipment.log`。

离屏命令仍沿用上文，但将 `SSJX_EQUIPMENT_GAME_CAPTURE` 指向新的 `work/eva01-axe-production/`，**不设置**旧的 `SSJX_EQUIPMENT_LIVE_FIXTURE`。本轮未连接远端、未打包、未部署、未推送，也未重新执行真实联机测试。
