# 冥林异装：用户参考图直接制作原生装备

2026-10-19。用户要求根据巫师／骸骨／幽绿灵火参考，制作职业武器和多样头部，并直接接入商城、背包及联机规则。延续六职业／性别人物范围，每人物一套十槽装备；当前系列不替换骨甲幽光。

| 人物 | 套装 | 武器 | 头部与配色 |
|---|---|---|---|
| 力士男 | 冥苔断岳 | 战斧 | 苍白尖发、骨枝冠、苔绿黑甲 |
| 力士女 | 腐焰镇魂 | 重锤 | 银发角冠、腐铜黑甲、暗红披布 |
| 侠客男 | 枯藤照夜 | 长剑 | 骨面藤冠、枯绿护甲、翠色剑脊 |
| 侠客女 | 碧毒裂影 | 爪刃 | 浅金短发、紫色头巾、碧毒爪尖 |
| 隐者男 | 葬骨灯冢 | 骨魂法杖 | 骨面兜帽、幽绿眼、暗青残袍 |
| 隐者女 | 烬冠引魂 | 灵火法器 | 金色火焰高发、暗紫面部、碧眼与魂火 |

用户原参考图分别保存为 `necromancer-reference.png`、`hairstyle-reference.png`。它们用于主题、造型和来源追溯；正式游戏仍使用现有人物的像素比例和动作。

`set-definitions.json` 登记职业武器模板、头部编号、命名和提示词主题。每张输入模板按四列八行排布：前五行保留所有原生分层帧及空帧，后三行提供十槽图标。由内置image_gen逐套重绘，完整提示词及默认输出记录保存于 `generation-records.json`。两处身体误绘头部的修正记录另存 `body-correction-records.json`，本目录 `*-parts-painted.png` 为最终采用图。

最终运行时文件为30张原生部件图集及60个32×32图标，位于 `client/assets/generated/equipment/gravebloom/`。`native-frame-templates.json` 与 `runtime-import-report.json` 保留原始帧区域和每张正式资源SHA256。导入采用最近邻采样及透明边缘清理，将部件装回原生有效区域；所有原生坐标、画布、空帧、图层变换和动作配方保留。原输入头部的轮廓允许按参考做骷髅面具、兜帽和夸张发型，仍受当前人物画布约束。

复现（在仓库根目录运行，`godot`为本项目Godot控制台程序）：

```powershell
godot --headless --path client --script ../tools/equipment_asset_pipeline.gd -- build --config res://../analysis/ai-generated/equipment/gravebloom/set-definitions.json
python tools/build_gravebloom_equipment.py
python tools/build_full_shop_catalog.py
godot --headless --path client --editor --import --quit
python tests/test_gravebloom_assets.py
```

重新排出原生输入模板时去掉命令中的 `build`，输出在忽略目录 `work/gravebloom-production/`。重新生成图片应使用保留的原模板与两张用户参考，不将完整人物立绘切成动画。
