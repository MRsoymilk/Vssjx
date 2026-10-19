# 骨甲幽光装备验证

## 2026-10-20 赤翎破军脸部修正

用户指出女力士头部脸型、眼睛变形后，以内置 image_gen 编辑原生产稿的第 0 格，并参考原包 `wzst2` 头部；保留棕红长发、金色饰物和装备风格。新稿、修复前图集、生成记录与可复现配置保存在 `analysis/ai-generated/equipment/boneglow/face-correction-*` 及 `02_female_lishi-face-corrected.png`、`02_female_lishi-head-before.png`。

原导入器按包围框独立拉伸宽高，本次增加 `--patch-only` 模式，只替换配置明确列出的部件格。`preserve_aspect` 使用等比采样、水平居中与底部颈部锚点对齐，避免把眼睛和下颌再次纵向拉长。后脑帧、其余部件和图标均保留原像素，更新导入清单中的目标 SHA256。

```sh
godot --headless --path client --script ../tools/equipment_asset_pipeline.gd -- build --patch-only --config res://../analysis/ai-generated/equipment/boneglow/face-correction-config.json
python tests/test_boneglow_assets.py
```

运行图集只变更 `client/assets/generated/equipment/boneglow/wzs/parts/wzst2.png`，90 张资源中其他 89 张 SHA256 不变。实际 OpenGL 装备场景 490 项通过；另以实际人物合成器对照修复前后并检查待机、行走、攻击及受击。开发截图在忽略目录 `work/face-game-captures/`。本轮未打包、推送或部署，已发布客户端需要后续重新导出才能获得此图集。

2026-10-19，使用项目Godot 4.7.2、本机OpenGL兼容渲染，以及Rust服务端和专用临时PostgreSQL数据库验证。未操作玩家实际存档和生产数据库，未部署公网。

## 命令

在仓库根目录运行，`godot`指本项目Godot控制台可执行程序：

```powershell
python tests/test_boneglow_assets.py
python tests/test_full_shop_catalog.py
cargo test --manifest-path server/Cargo.toml --lib shop::tests
cargo build --manifest-path server/Cargo.toml
$env:SSJX_TEST_SERVER_BIN = (Resolve-Path server/target/debug/vssjx-server.exe).Path
python tests/run_boneglow_equipment.py
$env:SSJX_BONEGLOW_LIVE_FIXTURE = (Resolve-Path work/boneglow-production/live-fixtures.json).Path
godot --headless --path client res://tests/boneglow_equipment_test.tscn
```

服务端验证使用 `tests/pg_fixture.py` 创建并清理独占临时PostgreSQL；默认使用已安装Docker本地 `postgres:17-bookworm` 镜像，也支持测试专用便携PostgreSQL参数。监听随机回环端口，不接入现有服务。非Windows环境请设置实际服务端可执行文件路径。

## 本次结果

- 生产纹理：2组验证通过，覆盖30张部件、60个图标、原生画布与帧区域、空帧保留、透明边缘和全部90个资源SHA256。
- 原商城与原图集：4组Python验证通过，保留208个原包物品图标及原始部件像素。
- Rust商城：2个单元测试通过，覆盖六套十槽定义、权威属性、职业／性别限制和旧版协议响应。
- 真实服务端：197项通过，覆盖六角色60件购买／装备、扣费、十槽数据库约束、目录摘要、错误职业／性别拒绝、其他客户端接收外观、重连和角色列表恢复。
- Godot专用场景：带真实服务端输出和实际OpenGL截图489项通过；覆盖本地购买与落盘恢复、伪造性别存档拒绝、五类可用原生动作与组合帧、单件混穿、同屏外观接收、实际游戏地图、商城入口和背包图标／人物预览、整套管理预览及桌面布局。
- 原生人物组合525项、装备映射4726项、完整商城1516项、装备筛选264项、外观面板78项、管理布局311项通过。
- 社交客户端36项、切磋客户端25项、队伍客户端37项通过。
- 原商城真实服务端回归983项通过：全部208件原包物品仍可购买、穿戴或使用、移除，涵盖十槽、背包容量、数量、幂等与旧物品外观。

实际渲染文件保留于忽略目录 `work/boneglow-production/`：`native-runtime-review.png`、`world.png`、`shop.png`、`inventory.png`。独立六角色动作核对场景为 `res://tests/boneglow_review.tscn`，可切换动作；非隐者无原生施法动作时保留当前可用动作。

导出配置检查：正式资源位于游戏资产目录，使用 `all_resources` 导出，未被管理工具／测试目录的排除规则覆盖。本次未执行游戏打包或公网部署，未将其记为已验证结果。

## 2026-10-19 商城图标边界残片修正

霜骨流萤审阅图第一行人物脚部越过网格边界，导致下一行武器、头冠、衣甲、护腕切片夹带残片。导入器现在先清除接触边界且面积不足主区域十分之一的八方向连通小块，再计算包围框和缩放；报告分别记录407、421、761、211个原始切片像素的清理。保留内部细节、成对部件和主要轮廓。

- `godot --headless --path client --script res://tests/equipment_icon_cleanup_test.gd`：边界残片、成对部件、内部细节、对角连接和重复清理验证通过。
- 两个装备系列重新导入，共120个图标、60张部件；Git差异仅四个目标图标，其他资源一致。`python tests/test_boneglow_assets.py`、`python tests/test_gravebloom_assets.py`、`python tests/test_full_shop_catalog.py`全部适用检查通过。
- 实际OpenGL运行 `res://tests/boneglow_equipment_test.tscn`，设置 `SSJX_EQUIPMENT_GAME_CAPTURE=work/shop-icon-cleanup` 的绝对路径：490项检查、0失败，存档恢复检查通过。六角色商城及地图、背包、管理预览截图保存在该忽略目录，重点核对 `shop-wck.png` 的四个目标图标无上方杂点。
