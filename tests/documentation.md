# 开源文档整理验证

## 范围

2026-10-19：整理项目首页、使用与资源指南、设计索引、贡献和部署说明。仅调整文档及其静态回归，不修改游戏逻辑、配置、素材或历史数据库迁移；不构建、推送或部署产物。

## 检查入口

在仓库根目录执行：

```sh
python -m unittest discover -s tests -p test_documentation.py
python tests/test_project_layout.py ProjectLayoutTests.test_startup_instructions_target_client
git diff --check
```

文档检查离线扫描根 README、贡献指南、服务端 README、`docs/`、`design/`、`deploy/` 及本次整理的测试说明，检查 Markdown 和 HTML 本地链接／图片路径及代码围栏配对。它不请求体验服、不验证外网链接可用性，也不代替 Godot 或浏览器实际渲染。

## 首页与指南阶段

- 首页使用现有 `client/assets/ui/app_icon.png`，未生成新图或更换应用资源。
- 首页、四份专题指南与部署导航共 6 份文档的 73 处本地链接／图片路径初检通过。
- 完整 `test_project_layout.py` 共 6 项中 5 项通过，1 项失败：`test_literal_resource_paths_resolve_with_new_project_root` 将未修改的 `client/scripts/admin/equipment_appearance.gd` 说明字符串中的 `scripts/shop_rules.gd；res://scripts/hero_appearance.gd；` 误认为单条资源路径。本次不扩大范围修改脚本或此旧测试。

文档能力说明依据当前源码、专题契约及已归档发布记录核对，不将既有测试结果表述为本次重新运行的玩法验收。

## 设计文档阶段

- 设计入口覆盖全部 25 份专题，按架构、账号世界、玩法、美术分类。
- 各专题补充返回导航和性质／状态，区分目标契约、当前实现、候选稿与源码接入。
- 核对并修正五角色、NPC 入派、网页发布、线上 PVE、生成世界、组队多目标和聊天管理等过时状态；D03 账号级并发与 D04 统一超时保持为未落实／待核验目标，不更改代码策略。
- 将决斗的既有验收结果迁至 `tests/player_duels.md`，保留原结论；补充社交、队伍测试入口说明，未重跑这些集成用例。
- 文档回归新增设计索引覆盖、专题导航与性质声明检查。
