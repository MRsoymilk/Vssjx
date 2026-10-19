# 项目数据工具

[返回项目首页](../README.md) · [资源恢复与重建](resource-recovery.md)

数据浏览器与世界总图是**独立桌面开发工具**，只读浏览项目定义和原包资料，不连接玩家数据库、不读取玩家存档，不属于游戏内页面，也不随游戏导出。

## 启动

Godot 4.7 打开对应场景后按 **F6**，或在仓库根目录运行：

```sh
godot --path client res://scenes/admin/data_browser.tscn
godot --path client res://scenes/admin/world_overview.tscn
```

这两条命令是不同工具的启动入口，按需单独运行。Windows 还可使用：

```powershell
./tools/open-data-browser.ps1 -GodotBin "你的Godot可执行文件路径"
```

脚本也支持 `GODOT_BIN` 环境变量及 PATH 中的 `godot`／`godot4`。

数据浏览器使用 960×640 桌面画布，世界总图及弹窗使用 960×540，可放大窗口；不改变游戏的 320×480 视口。按 F6 时工具使用独立窗口，避免嵌入编辑器手机比例宿主。数据页按 F5 刷新 JSON 和列表，修改脚本常量后需重新运行。

## 可以查看什么

目录覆盖武器、装备、物品、人物、任务、地图、怪物、特效、素材／动画和原包归档。支持搜索名称、ID 与属性，按来源状态筛选，查看 JSON 字段和定义来源；部分目录提供缩略图、动画、地形与阻挡预览。

| 目录 | 已归档范围与解释 |
|---|---|
| 物品 | `item.mrp` 的 208 张图标：56 武器、81 装备、71 其他；同一资源可出现在多个分类，不代表多份物品定义 |
| 怪物 | `monster.mrp` 的 117 份原始动画，覆盖 142 份图片成员；资源条目不等于已恢复的完整怪物定义 |
| 特效 | `effect.mrp` 的 159 份原始动画，覆盖 75 份图片成员；原名及技能对应关系未完整恢复 |
| 原包归档 | 6 个 MRP 的 1,916 条成员记录及 1 份版本文件，共 1,917 条；保留部分解析、未解析和失败条目 |
| 原地图目录 | 214 条记录、157 个不同名称；已恢复世界总图 79 个位置、78 条连线，不等于单张场景布局 |
| 任务／线索 | 区分重建任务链、原包文字线索与 AI 任务，文案和引导资料不计作完整原版任务 |

原包资源可核对成员路径、帧号、尺寸与校验值。未恢复的原版名称、ID、等级和数值保持未知，不以当前商城名称、AI 配置或临时匹配填充原始证据。

世界总图采用地图与说明左右布局，支持查看地点名称、等级和连线。单图布局的恢复边界见 [地图恢复记录](../analysis/recovery/maps/README.md)，AI 地形则见 [世界扩展](../design/ai-world.md)。

## 更新索引

在修改源分析或转换规则后，按需执行对应导入器；普通浏览不必重建：

```sh
python tools/import_item_catalog.py
python tools/import_monster_catalog.py
python tools/import_effect_catalog.py
python tools/import_resource_archive.py
python tools/import_original_world.py
```

命令会更新对应索引或预览资源，运行前检查工作区并阅读 [资源重建指南](resource-recovery.md)。原始二进制保留在 `analysis/`，管理专用资源位于 `client/assets/admin/`。

游戏导出预设应继续排除 `scenes/admin/`、`scripts/admin/`、管理专用素材与测试，保留游戏运行需要的 JSON；不要把整个项目目录当作网页静态根目录。导出边界的检查入口见 [游戏导出测试](../tests/game_export.md)。
