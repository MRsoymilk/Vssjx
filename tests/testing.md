# 开发测试入口与历史记录

本文记录已有测试入口、运行方式与隔离要求。下文带日期和阶段的结果是历史事实，不保证当前源码、发布包或全部设备都已通过。联机业务已有实现，完整混合负载目标继续见 [online_test_plan.md](online_test_plan.md)；测试说明和结果统一放在 `tests/`，不写入项目或设计 README。

## 按变更选择入口

| 范围 | 说明 |
|---|---|
| 开源文档与链接 | [文档检查](documentation.md) |
| 导航与游戏子路径 | [页面、浏览器与隔离 Nginx 验证](portal_navigation.md) |
| 私有统计后台与 APK 管理 | [采集、文件管理、HTTP 安全与浏览器验证](portal_stats.md) |
| 独立 Flarum 论坛 | [2026-10-20 安装、隔离、资源与公网浏览器验证](flarum_release_20261020.md) |
| 论坛 SMTP 与注册 | [QQ 测试邮件确认、注册开放与敏感配置检查](flarum_registration_20261020.md) |
| EVA 初号机主题装备 | [六角色、60 件装备、实际离屏渲染及隔离联机验证](eva01_equipment.md) |
| 任务、战斗与地图 | [线上 PVE](online_pve.md)、[第二张地图](online_maps.md)、[技能](../design/skills.md#验证) |
| 新数值候选内核 | [共享参数、Rust/Godot一致性与实际离屏预览](combat_balance.md) |
| 社交与多人战斗 | [社交](social.md)、[组队](teams.md)、[决斗](player_duels.md) |
| 平台与网页 | [平台基础](platform_interface.md)、[主游戏 Web](web_game.md)、[浏览器存储](web_storage.md) |
| 素材与桌面工具 | [数据浏览](data_browser.md)、[游戏导出边界](game_export.md) |
| 公网历史发布 | [发布基线](release_20261018.md)、[后续聊天管理](chat_moderation.md)、[仅门户发布](portal_release_20261019.md) |

文档变更可只运行相关静态检查，不要求启动数据库、导出产物或部署服务。以下保留各阶段的具体入口，选择与修改范围对应的回归。

Rust基础服务、登录服务器地址、重启保存与真实网络联调见[server_connection.md](server_connection.md)。

PostgreSQL账号、密码、会话、注销与账号界面验证见[account_auth.md](account_auth.md)。

`.env`读取、参数边界、环境优先级与Git忽略验证见[env_config.md](env_config.md)。

线上角色、昵称唯一性、账号创建回执与事务故障验证见[characters.md](characters.md)。注册进入原角色创建场景、后续登陆复用该账号角色的验证见[registration_flow.md](registration_flow.md)。

角色元数据分片、按需加载、无损重建与读取微基准见[actor_catalog.md](actor_catalog.md)。

结构化日志与监控早期验证见 [observability.md](observability.md)；当前本机写入管理与审计另见 [security_admin.md](security_admin.md) 和 [chat_moderation.md](chat_moderation.md)，不再将整个管理页面称为只读。

项目数据管理与世界总图独立桌面窗口、小窗口布局验证见[data_browser.md](data_browser.md#独立桌面工具布局)；开发工具不进入游戏包的真实导出检查见[game_export.md](game_export.md)。

多平台接口P1的原生入口、配置/存储兼容、显示/生命周期及失败路径验证见[platform_interface.md](platform_interface.md)，不等于Web或手机兼容验收。

P1b资源准备接口、并发取消、超时、遇敌接入及真实PCK异步读取见[platform_resources.md](platform_resources.md)。

P1c文本焦点、组合状态提交防护和原生退出/窗口关闭保存验证见[platform_input_actions.md](platform_input_actions.md)。

P2c-1可等待存档契约、全部游戏调用方迁移、延迟完成/失败与退出等待验证见[storage_async.md](storage_async.md)；不等于实现或验收浏览器持久化。

P2c-2 的存储夹具、IndexedDB 事务确认、重开恢复及失败／超时验证见 [web_storage.md](web_storage.md)。该早期阶段不代表主游戏验收；后续已接入 Web 工厂与网页发布，分别见 [web_game.md](web_game.md) 和 [release_20261018.md](release_20261018.md)。

同一游戏界面的多人角色、内嵌聊天与本地入口验证见[shared_interface.md](shared_interface.md)及[local_mode.md](local_mode.md)。

底部内置表情面板、标记传输与双方贴图显示验证见[chat_emotes.md](chat_emotes.md)。

游戏竖排菜单、充值及编号移除、功能跳转和系统存档入口验证见[game_menu.md](game_menu.md)。

除非特别说明，命令均在`Vssjx/`仓库根目录执行，Godot工程路径为`client/`。

- `tests/`：Python回归、离屏辅助脚本、测试说明和容量验收方案。
- `client/tests/`：Godot测试场景、GDScript与UID，场景内仍使用`res://tests/`路径。

## 环境与隔离

- Godot 4.7系列；原工程记录的验证引擎为`4.7.1.stable.official.a13da4feb`，本轮Linux行走验证使用`4.7.2.stable.gentoo.ed1daf0bf`。
- Python素材测试需要Pillow，资源重建另外需要NumPy。
- 普通`--headless`只检查逻辑，不能代替真实渲染截图。
- Linux真实渲染离屏运行需要Xvfb与OpenGL驱动，可使用Mesa软件渲染，不向桌面弹窗。
- 场景使用各自的独立测试存档；不能把测试配置指向玩家的`user://shushan_save.json`。
- 普通启动的隔离存档可用`SSJX_SAVE_PATH`指定；下列测试场景会自行设置独立存档路径。
- 截图输出目录必须先创建。测试产物不混入`assets/`或玩家数据。

## 1. 素材与动画导入回归

```sh
python -m unittest discover -s tests -p 'test_*.py'
```

`test_asset_decoder.py`检查静态资源解码；`test_actor_import.py`检查六个角色的完整步伐朝向，以及侠客待机和六帧行走中双刀与身体的像素连接，防止较大的武器孤立像素部件。`test_project_layout.py`检查目录边界、Godot资源引用、素材工具输出位置和启动脚本路径。

## 2. 游戏逻辑与完整流程

```sh
godot --headless --path client res://tests/test_runner.tscn
```

覆盖战斗、存档、寻路、背包、界面操作与完整任务流程，使用独立的`test_save.json`。

Windows PowerShell示例：

```powershell
& 'E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --headless --path client res://tests/test_runner.tscn
```

## 3. 行走专项逻辑回归

路线频繁转向、键盘接管、暂停回拉、多人拐点/停走抖动和移动限频丢指令的后续修正见[movement_control.md](movement_control.md)。

```sh
godot --headless --path client res://tests/motion_regression.tscn
```

覆盖六角色、WASD四向、跨格、转向、暂停、松键、阻挡、点击寻路与15/30/60/120 FPS速度和步伐一致性。不读写玩家存档。

连续点击同一屏幕位置的寻路回归：

```sh
godot --headless --path client res://tests/click_motion_regression.tscn
```

覆盖四个斜向、四种点击距离、15/30/60/120 FPS与每1/2/4/8帧点击一次，检查无反向移动、跨格或瞬移；另检查中途换目标、点击当前步落点、不可达目标、障碍绕行和重复目标交互。行走途中重规划以当前一步的落点为起点，避免从旧格子重新接路。

2026-10-15（Godot 4.7.1，Windows）：旧实现的初始32项复现用例有4项失败，出现反向移动及非相邻格衔接；修复后扩展的776项连续点击检查全部通过，原有6018项行走、379项整流程、129项遭遇过渡和6项目录检查也全部通过。

角色待机动画回归：

```sh
godot --headless --path client res://tests/idle_regression.tscn
```

覆盖六角色与六种创建页预览：使用真实 `AnimatedSprite2D` 时钟确认待机确实切换两张原生站姿，而非仅检查动画名；验证循环播放、重复更新不重置帧、暂停后恢复，以及走完后原地待机。待机每帧持续约2/3秒，整轮约4/3秒；不使用攻击帧、移动帧或脚本位移模拟呼吸。

2026-10-15（Godot 4.7.1，Windows）：待机逻辑66项、实际OpenGL渲染68项检查全部通过，并逐张检查六角色的两张待机姿态截图。设置 `SSJX_IDLE_CAPTURE_PATH` 为已存在目录、以真实渲染器运行，可保存这两张对比图。

## 4. Linux真实渲染离屏

```sh
mkdir -p /tmp/opencode/vssjx-motion
SSJX_MOTION_PATH=/tmp/opencode/vssjx-motion LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/motion_regression.tscn
```

输出204张截图和`motion_trace.json`逐帧位置、朝向、动画与步伐记录。`GODOT_BIN`、`XVFB_BIN`可指定引擎与虚拟显示器路径；辅助脚本位于`tests/run_offscreen.py`。

连续行走录制：

```sh
mkdir -p /tmp/opencode/vssjx-motion-smoke
SSJX_MOTION_PATH=/tmp/opencode/vssjx-motion-smoke LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/motion_smoke.tscn
```

记录72帧待机、右行、左行、停下过程，使用独立测试存档。

## 5. 战斗回合渲染

```sh
mkdir -p /tmp/opencode/vssjx-turn
SSJX_TURN_PATH=/tmp/opencode/vssjx-turn LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/turn_smoke.tscn
```

记录105帧指令选择、我方行动、敌方行动、回合结算和下一次选择，并输出阶段截图，使用独立测试存档。

## 6. 页面与场景截图

```sh
mkdir -p /tmp/opencode/vssjx-visual
SSJX_CAPTURE_PATH=/tmp/opencode/vssjx-visual LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/visual_smoke.tscn
```

Windows直接运行会短暂打开窗口：

```powershell
$env:SSJX_CAPTURE_PATH = '指定一个已存在的绝对目录'
& 'E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --path client res://tests/visual_smoke.tscn
```

## 行走修正验证记录

本轮行走修正曾在Linux Godot 4.7.2下运行：素材单元测试6项通过，游戏逻辑回归379项零失败，行走无渲染回归6018项零失败，真实渲染离屏回归6426项零失败，并录制72帧连续行走。

这些是对应行走修正的验证记录，不表示未实施的联网功能或1000人容量已通过验收。后续修改需要重新运行相应入口。

## 启动器兼容检查

```sh
XDG_DATA_HOME="$(mktemp -d /tmp/opencode/vmanage-layout.XXXXXX)" \
  godot --headless --path ../../vmanage --script res://tests/smoke.gd
```

使用隔离数据目录，不改动个人收藏和游玩时间。检查Vssjx新入口、旧式根目录工程、`client/`工程、双入口优先级、服务端目录排除、游戏ID及统计关联，并实际启动一个临时`client/`工程验证进程和计时。此脚本还会检查现有游戏库与界面，依赖工作区中其他游戏项目。
