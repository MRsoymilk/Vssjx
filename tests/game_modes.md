# 游戏模式、共用地图与聊天隔离

本地和联机入口都使用 `character_selection.tscn`，角色选择和地图 HUD 分别标明“本地模式 / 联机模式”。无角色的首次进入也经过空角色选择页，菜单创建成功后返回角色选择，只有点击“进入”才启动地图。注册后自动登陆同样先到选择页。

`SharedWorldMap` 是两种模式共用的地图构建器。青云山道直接读取同一份 `client/assets/data/qingyun-v1.json`，统一地形、碰撞与树木位置，不再由本地随机生成另一份地图；小地图也读取这些格子。NPC、怪物出生点和属性来自与服务端同源的 `qingyun-population-v1.json`。两份客户端 JSON 必须与 `shared/data/` 中对应文件的原始字节一致，地图哈希和在线协议保持兼容。

地图是目前已有的可玩青云山道重建，并非恢复了原版所有地图。既有古剑遗迹本地剧情仍保留；服务端目前只开放青云山道，此次没有把遗迹接入服务器，也没有更改服务端的任务或刷新规则。

本地控制器只保存本地角色；进入本地模式取消账号请求、停止后台刷新，并阻断后续显式账号 / 世界票据请求。联机仍通过认证世界连接发送移动、任务和战斗操作，由服务端结算和保存，不把客户端计算的伤害、奖励或整个本地存档上传。重新选择联机后恢复网络处理。

本地社交按钮复用地图底部输入框、表情和展开聊天页，消息标为“本地”，仅在当前本地会话内存中回显，最多保留 100 条。打开属性等页面后返回仍保留历史；返回封面或新建角色清空。聊天不写入角色存档，不携带到联机频道。输入时停止自动寻路，WASD / 属性快捷键不作用于地图，点击地图释放输入焦点。

联机消息保持公共频道语义：通过服务器确认后显示，并向同图在线玩家广播；重连、去重、限流及会话隔离沿用现有协议。没有新增私聊、帮会或跨地图全服频道。

## 验证

```powershell
godot --headless --path client res://tests/game_modes_test.tscn
godot --headless --path client res://tests/local_mode_test.tscn
godot --headless --path client res://tests/platform_storage_async_test.tscn
python -m unittest discover -s tests -p test_shared_world_data.py
python tests/run_registration_flow.py
```

实际渲染：

```powershell
godot --path client --rendering-driver opengl3 --position -10000,-10000 res://tests/game_modes_test.tscn -- --capture-modes=F:/project/Vssjx/work/game-modes
```

2026-10-17，Windows / Godot 4.7.1：

- 模式集成 1048 项；逐格比较 1024 个地图格子的地形和碰撞，本地聊天、输入焦点、会话历史、有有效线上身份时阻断本地网络请求，以及线上消息不触碰本地存档。
- 本地入口 30 项、异步持久化 66 项、完整客户端回归 386 项。
- HTTP 协议夹具：注册流程 52 项、线上角色选择 / 创建 69 项、账号界面 19 项；实际 OpenGL 注册选择页截图通过。
- 共用界面 28 项、移动回归 6018 项、脚圈 169 项、离线刷新 87 项、公共聊天协议 48 项、表情 45 项、展开聊天 37 项通过。
- Docker 临时 PostgreSQL + 既有 Rust 服务端真实客户端联调 22 项通过，包含选择角色、地图移动、任务、战斗中聊天和重连。
- 另外在临时数据库运行两个独立的认证 WebSocket 连接，双向发送公共消息和表情，发送方与另一玩家均收到服务器广播。
- Python 数据同源与居民可达性 2 项通过。

截图位于忽略的 `work/game-modes/`。这些结果未冒充本轮 Linux 原生、Web 浏览器、真实手机或公网跨机验收；浏览器脚本已适配首次空角色选择流程，但本轮没有重新导出 Web 并执行该脚本。
