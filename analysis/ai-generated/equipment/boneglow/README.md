# 骨甲幽光：设计稿到原生动画部件

2026-10-19，按用户“之前的骨甲幽光套装设计资源接入正式游戏”确认接入六套设计。

本目录保存六张原设计、六张从原人物部件直接排出的模板、六张由内置 `image_gen` 重绘的生产部件图、完整提示词、逐帧坐标和运行时资源校验和。两套男性躯干经过额外遮盖修正，最终选用的图已替换本目录 `*-parts-painted.png`；工具默认输出另存于本机，修正提示词另有登记。

运行时资源位于 `client/assets/generated/equipment/boneglow/`：30 张部件图集、60 个 32×32 图标。图标来自已确认设计稿的十个对应区域；部件沿用现有人物头部、身体及前后层、武器的帧区域和 ANI 配方，未覆盖原包图片。部件图中的空帧仍为空帧；有效区域按原生大小作最近邻采样后装回原坐标，清除半透明外缘。整套设计在原生像素尺寸下有所简化，不能将审阅图的六个姿势当作动画帧直接循环。

重新制作资源（在仓库根目录执行，`godot` 指本项目 Godot 4.7）：

```powershell
# 已保存生产图，可直接重复导入；不用再次生成图片。
godot --headless --path client --script ../tools/equipment_asset_pipeline.gd -- build
python tools/build_boneglow_equipment.py
python tools/build_full_shop_catalog.py
godot --headless --path client --editor --import --quit
python tests/test_boneglow_assets.py
```

如需重新生成原生输入模板，去掉脚本末尾的 `-- build`；它会输出到被忽略的 `work/boneglow-production/`，不会覆盖本目录已保存的生产图。执行生产图重绘需使用记录的提示词、对应原生模板和已确认设计稿。

运行时映射见 `client/assets/data/boneglow-equipment.json`；接入约定、编码和入口见 `design/boneglow-equipment.md`。
