# 客户端场景资源

固定页面位于 `client/scenes/ui/`：标题、服务器账号、角色选择、创建角色、属性框架与四个分页、背包与物品格、地图/战斗 HUD、聊天、战斗提示、弹窗遮罩与框架。`main.tscn` 保存根 UI 和共享字体主题。节点、位置、图片及固定样式可以在 Godot 编辑器中直接修改。

页面从对应的 `PackedScene` 实例化，脚本通过节点引用连接信号、更新角色数据与显示状态。不要对这些页面脚本直接调用 `.new()`，否则不会得到场景中的子节点。动态弹窗内容使用 `dynamic_*.tscn` 基础组件；按状态变化的文本、颜色和尺寸仍由脚本配置。

标题页公开入口只有“登陆游戏”和“退出游戏”，已移除四行菜单滚动与底部“确定/退出”。登录页由 `server_login.tscn` 和 `login_theme.tres` 保存游戏风格布局：服务地址行带“修改”按钮，用户名与密码左右对齐，登陆/注册纵向排列，返回位于左下方。地址默认只读，“修改”后变为“保存”；登陆与注册分别提交各自请求。联网已登录时按钮显示“选择角色/退出账号”；登陆后先显示`character_selection.tscn`，确认进入后才加入游戏。

角色、怪物与特效使用 `scenes/actors/original_actor.tscn` 中的 `AnimatedSprite2D`。`OriginalArt.actor()` 按角色元数据配置 `SpriteFrames`，保留共享缓存、图集偏移、待机/行走循环和攻击/施法单次播放。地图格子、网络实体和临时特效依旧按实际数据生成。

## 验证入口

在仓库根目录执行，Windows 可将 `godot` 替换为本机 Godot console 可执行文件：

```sh
godot --headless --path client --editor --import
godot --headless --path client res://tests/ui_scenes_test.tscn
godot --headless --path client res://tests/login_ui_test.tscn
godot --headless --path client res://tests/test_runner.tscn
godot --headless --path client res://tests/server_connection_test.tscn
godot --headless --path client res://tests/battle_casting_test.tscn
godot --headless --path client res://tests/battle_transition_test.tscn
godot --headless --path client res://tests/motion_regression.tscn
godot --headless --path client res://tests/actor_catalog_test.tscn
python -m unittest discover -s tests -p 'test_project_layout.py'
```

`ui_scenes_test` 在节点进入场景树、执行 `_ready()` 之前检查静态控件，验证布局确实来自场景文件；另检查角色选择控制节点、位图数字配置、战斗模式和 `AnimatedSprite2D` 类型。既有流程测试覆盖切页、角色选择、背包操作、弹窗及战斗交互。

2026-10-17 清理：删除无运行时入口的旧 `online_characters.tscn`、`online_characters.gd` 及脚本 UID。角色选择检查改为当前 `character_selection.tscn` 的三张预览卡、五个角色标记、联机控制节点及创建/刷新/进入/返回控件。`online_characters_test` 是当前共用选择页的账号多角色集成测试，继续保留。管理页面是可从编辑器独立启动的工具入口，继续保留。

清理后验证：Godot 编辑器导入无错误，项目资源路径 6 项、游戏导出策略 4 项、固定场景 110 项、角色选择 10 项、双模式 1058 项、PvE UI 71 项通过。隔离 PostgreSQL/Rust 联调及真实账号角色界面 98 项通过，覆盖五角色创建/选择、重复请求、断线重试与数据库故障。资源路径检查遇到既有的故意缺图测试夹具，将其改为与其他失败夹具一致的运行时路径构造，保留资源失败测试并恢复静态路径检查。日志位于忽略目录 `work/project-cleanup/`；未部署或重启当前服务。

真实渲染使用既有 `visual_smoke.tscn` 和 `SSJX_CAPTURE_PATH`，生成 37 张截图；`--headless` 不用于替代截图检查。线上账号/共享地图的真实网络联调仍按各自测试文档运行。

标题/登陆布局专项可设置 `SSJX_LOGIN_UI_CAPTURE_PATH`，以真实渲染器运行 `login_ui_test.tscn` 保存两张截图。2026-10-15（Windows，Godot 4.7.1）：布局与动作检查31项通过，实际渲染33项通过，场景资源81项和整流程377项通过；`tests/run_server_connection.py` 的真实Rust发现及Godot界面58项、跨进程地址读写各1项通过。此次未运行需要独立PostgreSQL的完整账号/角色联调；测试入口已改为实际点击独立的登陆/注册按钮。
