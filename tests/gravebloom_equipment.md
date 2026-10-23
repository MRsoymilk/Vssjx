# 冥林异装与对称战斧验证

## 2026-10-23 全系列像素精修

六套正式部件与图标已精修；实际渲染496项通过。最新材质调整、全动作几何比对及复现命令见[套装精修](equipment_refinement.md)。

## 初次接入验证

2026-10-19。使用Godot 4.7.2、实际OpenGL兼容渲染及本机独占临时PostgreSQL/Rust服务端完成验证，不访问生产数据库，不操作玩家真实存档。

## 命令

```powershell
python tests/test_gravebloom_assets.py
python tests/test_boneglow_assets.py
python tests/test_full_shop_catalog.py
cargo test --manifest-path server/Cargo.toml --lib shop::tests
cargo build --manifest-path server/Cargo.toml
$env:SSJX_TEST_SERVER_BIN = (Resolve-Path server/target/debug/vssjx-server.exe).Path
python tests/run_gravebloom_equipment.py
$env:SSJX_EQUIPMENT_LIVE_FIXTURE = (Resolve-Path work/gravebloom-production/live-fixtures.json).Path
godot --headless --path client res://tests/gravebloom_equipment_test.tscn
```

`godot`指项目控制台程序。服务端集成测试复用专属临时数据库工具，默认启动本地Docker PostgreSQL镜像并监听随机回环端口，结束后只清理自建测试容器；不连接现有账号库。

## 结果

- 新资源4组Python检查通过：30张原生部件、60个图标、不同职业武器模板、两种隐者头部、全部源帧尺寸、有效区域／空帧及90个资源SHA256。
- 双刃斧单独验证第一横向姿势中斧刃轮廓的轴对称重叠率高于90%，实际为94.2%，原不对称版本为73.1%。图标轴对称轮廓为95.9%。只有两个正式PNG改变：包含两帧的 `mzs/parts/ezs11.png` 与 `mzs/icons/weapon.png`。
- 旧骨甲幽光2组资源检查通过，原部件及图标没有改变；原商城5组检查通过，包含原208件图标／部件像素与两系列120件AI物品共存。
- Rust商城3个单元测试通过，覆盖两系列十槽、属性、职业／性别限制、旧版响应和跨系列头部混穿。
- 真实服务端203项通过：六角色60件购买／装备、权威价格及属性、数据库十槽约束、目录摘要、非法职业／性别拒绝、旧系列物品混穿、其他客户端收到外观、重连及角色列表恢复。
- Godot新系列场景：带真实服务器数据及实际OpenGL截图496项通过；覆盖本地存档、伪造性别拒绝、完整原生动画、默认与旧系列混穿、同屏编码、实际地图、商城分类、十槽背包及整套管理预览。旧骨甲幽光在新目录下480项回归通过。
- 原生人物组合525项、装备映射5434项、完整商城1576项、外观面板78项、管理布局311项、部位筛选318项通过。
- 社交客户端36项、切磋客户端25项、队伍客户端37项通过。

最终待机、行走、攻击截图分别为 `work/gravebloom-production/native-runtime-review.png`、`walk-runtime-review.png`、`attack-runtime-review.png`；实际游戏截图为同目录 `world.png`、`shop.png`、`inventory.png`、`admin.png`。这些截图和临时服务端数据置于忽略目录，不充当正式资源源文件。

独立动作场景为 `res://tests/gravebloom_review.tscn`；`SSJX_EQUIPMENT_REVIEW_CAPTURE` 指定截图路径，`SSJX_EQUIPMENT_REVIEW_ACTION` 选择动作，`SSJX_EQUIPMENT_REVIEW_FRAME` 可定位具体帧以便检查两个斧头姿势。

导出配置使用 `all_resources`，正式资源与JSON均在游戏目录中，未被管理工具／测试目录排除规则覆盖；本次未打包或部署，未把这些列为已完成验证。
