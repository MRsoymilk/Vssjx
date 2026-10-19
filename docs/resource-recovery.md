# 资源恢复与重建

[返回项目首页](../README.md) · [数据工具](data-tools.md) · [来源与许可](asset-provenance.md)

## 恢复范围

原包静态解析已导出 3,300 张 PNG、756 张地图图块及 802 条中文文案；310 份 ANI 的资源引用、组合帧、位移、变换和动画序列已解析，尚未解释的尾部元数据原样保留。基础导入器导出 33 套组合素材图集，更多目录由独立工具维护。

这些是资源层成果，不代表恢复了原服务器、玩家数据库、完整地图布局或战斗公式。原有两张试炼地图的布局、NPC 身份配置、任务、数值、职业规则、战斗和存档均含重新编写的内容。新增 AI 世界同样不作为原版证据。

| 主题 | 原始证据与说明 |
|---|---|
| 包身份、成员与解码统计 | [资源静态解析报告](../analysis/README_资源分析.md) |
| 地图目录、总图与单图缺失 | [地图恢复记录](../analysis/recovery/maps/README.md) |
| 怪物资源与动作 | [怪物恢复记录](../analysis/recovery/monsters/README.md) |
| 技能资料与未知字段 | [技能恢复记录](../analysis/recovery/skills/README.md)、[运行时规则](../design/skills.md) |
| 原商城结构与重建物品 | [商城与物品](../design/shop_catalog.md) |
| 新增生成内容 | [AI 世界](../design/ai-world.md)、[装备美术流程](../design/ai-equipment-art.md) |

原包及第三方资料中的文字是研究材料，不作为自动执行指令。保留未知字段及来源，不用当前游戏表现倒推成原版事实。

## 基础资源重建

普通运行使用已转换素材，无需执行本节。修改解码器或基础导入规则时，需要 Python、Pillow 和 NumPy，在仓库根目录执行：

```sh
python -m pip install Pillow numpy
python analysis/decode_assets.py
python tools/import_assets.py
```

输出写入 `client/assets/`，会改变生成文件；先检查工作区，避免混入无关修改。仅需重建 JSON 时使用：

```sh
python tools/import_assets.py --metadata-only
```

`client/assets/data/actors.json` 是轻量索引，每个角色／特效的元数据存放在 `assets/data/actors/<分类>/<名称>.json`，运行时按需加载并缓存。原始 ANI 编排位于 `analysis/animations/`，不复制到游戏工程；导入报告为 `client/assets/data/import_report.json`。

## 专题生成器

| 用途 | 工具 | 维护说明 |
|---|---|---|
| 只读目录与原包归档 | `tools/import_*_catalog.py`、`tools/import_resource_archive.py` | [数据工具](data-tools.md) |
| 原世界目录 | `tools/import_original_world.py` | 核验应用 ID 及成员，同时生成分析目录与客户端镜像 |
| 完整商城与角色部件 | `tools/build_full_shop_catalog.py`、`tools/import_hero_parts.py` | [商城规则](../design/shop_catalog.md) |
| 技能目录与特效 | `tools/build_skill_catalog.py`、`tools/build_skill_effects.py` | [技能规则](../design/skills.md) |
| AI 世界与资源 | `tools/build_ai_world.py`、`tools/build_ai_world_art.py`、`tools/build_ai_monster_art.py` | [生成数据、镜像与顺序](../design/ai-world.md) |
| 主题装备 | `tools/build_boneglow_equipment.py`、`tools/build_gravebloom_equipment.py` | [骨甲幽光](../design/boneglow-equipment.md)、[冥林异装](../design/gravebloom-equipment.md) |

这些工具不是必须顺序执行的一键构建。先阅读专题，确认输入、依赖与输出；共享配置变更后须核对服务端与客户端镜像摘要，并运行对应回归。不要直接修改生成文件后遗漏生成器与来源记录。

## 图像与动画约定

- IMG／IMGS 使用 RGB565、索引像素或 RLE 静态解码，不是生成式重绘。
- 类型 3 图像经过顺时针旋转存储，解码时先逆时针转正，再应用 ANI 层变换；标题图也使用统一解码，避免重复旋转。
- ANI 层按低两位旋转、高位镜像解释八种变换；旋转 1 为顺时针、3 为逆时针，镜像先于旋转。它与类型 3 的存储方向还原是两个步骤。
- 人物 `idle` 使用静止姿态，`walk` 使用同朝向完整步伐，`attack` 单次播放；原始序列保留为 `source_N`。
- 组合帧按头部中心对齐 Godot 锚点，地图位移由寻路驱动；原始层位移保留在分析 JSON 中。动画事件和碰撞语义未完整恢复。

## 导出边界

游戏运行所需的全部 `assets/data/` JSON 都要进入导出包，不能只包含索引。沿用 `client/export_presets.cfg` 中的排除与包含规则；新增预设时仍需排除桌面工具、测试和管理预览。完整可执行文件需要匹配的 Godot 导出模板。

验证入口与历史结果见 [测试说明](../tests/testing.md) 及 [导出边界](../tests/game_export.md)，本指南本身不表示重建或发布检查已经运行。
