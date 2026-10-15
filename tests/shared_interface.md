# 同一游戏界面的单人、多人和公共聊天

`client/scenes/ui/game_world_screen.tscn` 是本地地图和多人地图共用的界面资源，包含原有顶栏、时钟、气血/灵力、地图名称/坐标、小地图、角色标记、底部消息区和七个工具栏入口。在线模式仍使用服务器地图和权威玩家实体，视口统一为320×375，位于320×480游戏画面的 `(0, 28)`。

多人模式将公共聊天固定嵌入原底部消息区，输入和发送在同一画面完成，无需打开独立聊天页面。社交图标和Enter可聚焦输入框；输入WASD不会触发角色移动，其他玩家仍继续插值移动。点击地图或按Escape离开输入焦点，消息区保持可见。确认回执前保留原消息及输入，公共内容按纯文本展示。

小地图显示本人黄点和其他玩家蓝点，人数、位置和玩家离开随权威发布更新。在线菜单只使用线上角色快照；返回登陆会关闭世界连接。线上尚未开放的任务、背包、奖励给出当前状态，不调用本地任务、怪物、战斗或存档结算。在线数据不写入 `Game.player` 或本地存档。

服务地址 `local` 进入单人模式并保存在本地，见[本地入口验证](local_mode.md)。本地模式保留原任务日志、完整离线地图、背包、属性与战斗；进入本地后暂停账号的后台网络刷新，返回线上时恢复。

## 验证

```sh
godot --headless --path client res://tests/shared_interface_test.tscn
godot --headless --path client res://tests/local_mode_test.tscn
godot --headless --path client res://tests/world_delta_test.tscn
godot --headless --path client res://tests/public_chat_test.tscn
godot --headless --path client res://tests/test_runner.tscn
```

`shared_interface_test` 使用验证过摘要和序号的VWD2发布及公共频道协议夹具，覆盖同屏进入/移动/离开、公共消息发送和确认、文本显示、焦点和菜单、本地数据隔离，以及单人与多人实际引用同一PackedScene。它不是数据库或真实双客户端联调的替代品。

真实渲染可设置 `SSJX_INTERFACE_CAPTURE_PATH` 后运行该场景，输出多人聊天和本地地图两张截图。完整网络联调仍使用 `tests/run_shared_world.py --render`（需要Docker PostgreSQL）；既有独立客户端用例已增加共用HUD和内嵌消息区断言。

2026-10-15（Windows，Godot 4.7.1）：界面协议夹具27项、真实OpenGL渲染29项、本地模式26项、独立进程保存/读取7/21项、世界增量50项、公共聊天42项、界面资源86项、整流程377项通过。截图检查确认使用原地图HUD、工具栏、小地图及底部聊天区。本机未安装Docker，未运行数据库驱动的真实双客户端联调；不能将上述夹具检查表述为该联调已通过。
