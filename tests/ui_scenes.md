# 客户端场景资源

固定页面位于 `client/scenes/ui/`：标题、服务器账号、线上角色、创建角色、属性框架与四个分页、背包与物品格、地图/战斗 HUD、聊天、战斗提示、弹窗遮罩与框架。`main.tscn` 保存根 UI 和共享字体主题。节点、位置、图片及固定样式可以在 Godot 编辑器中直接修改。

页面从对应的 `PackedScene` 实例化，脚本通过节点引用连接信号、更新角色数据与显示状态。不要对这些页面脚本直接调用 `.new()`，否则不会得到场景中的子节点。动态弹窗内容使用 `dynamic_*.tscn` 基础组件；按状态变化的文本、颜色和尺寸仍由脚本配置。

角色、怪物与特效使用 `scenes/actors/original_actor.tscn` 中的 `AnimatedSprite2D`。`OriginalArt.actor()` 按角色元数据配置 `SpriteFrames`，保留共享缓存、图集偏移、待机/行走循环和攻击/施法单次播放。地图格子、网络实体和临时特效依旧按实际数据生成。

## 验证入口

在仓库根目录执行，Windows 可将 `godot` 替换为本机 Godot console 可执行文件：

```sh
godot --headless --path client --editor --import
godot --headless --path client res://tests/ui_scenes_test.tscn
godot --headless --path client res://tests/test_runner.tscn
godot --headless --path client res://tests/server_connection_test.tscn
godot --headless --path client res://tests/battle_casting_test.tscn
godot --headless --path client res://tests/battle_transition_test.tscn
godot --headless --path client res://tests/motion_regression.tscn
godot --headless --path client res://tests/actor_catalog_test.tscn
python -m unittest discover -s tests -p 'test_project_layout.py'
```

`ui_scenes_test` 在节点进入场景树、执行 `_ready()` 之前检查静态控件，验证布局确实来自场景文件；另检查选项列表、位图数字配置、战斗模式和 `AnimatedSprite2D` 类型。既有流程测试覆盖切页、角色选择、背包操作、弹窗及战斗交互。

真实渲染使用既有 `visual_smoke.tscn` 和 `SSJX_CAPTURE_PATH`，生成 37 张截图；`--headless` 不用于替代截图检查。线上账号/共享地图的真实网络联调仍按各自测试文档运行。
