# 内置聊天表情

底部消息区的“表情”按钮打开 `client/scenes/ui/chat_emote_picker.tscn`。选择面板、关闭按钮、八个表情按钮、贴图引用均由场景资源定义。面板在消息区上方展开，保留地图、底部聊天与原工具栏；本地单人模式仍显示原任务日志。

`client/scenes/ui/chat_emotes.tres` 维护客户端标记白名单与本地贴图映射：`[微笑]`、`[大笑]`、`[爱心]`、`[流泪]`、`[生气]`、`[惊讶]`、`[害羞]`、`[加油]`。贴图为本项目内置的16×16像素风SVG，随Godot资源导入打包；无外部素材或运行时图片下载。

选择表情会在当前光标处插入完整标记，有选区时仅替换选区。插入前检查120字/480字节限制，超长时保留原稿并提示。等待服务器确认期间文本和表情均锁定，确认后清空；断线时关闭并禁用表情面板。关闭按钮、Escape、点击地图或游戏菜单可以收起面板，人物不会因选择表情而接收移动输入，远端角色继续更新。

网络继续发送原公共聊天协议的普通 `text` 字段；重试ID、限流、历史窗口和消息顺序协议不变。接收端只将白名单标记转为 `RichTextLabel.add_image`，昵称和其他内容使用 `add_text`；BBCode保持关闭，未知标记、`[b]`、`[img]`及路径均按原文显示。旧客户端收到标记时仍可作为文字阅读。地图状态更新不会重复重建相同聊天内容。

## 验证

```sh
godot --headless --path client res://tests/chat_emotes_test.tscn
godot --headless --path client res://tests/public_chat_test.tscn
godot --headless --path client res://tests/shared_interface_test.tscn
godot --headless --path client res://tests/ui_scenes_test.tscn
```

`chat_emotes_test` 创建两个实际多人界面实例，使用经过公共频道验证的消息夹具，检查发送内容仍是标记、双方生成原生图片项、所有表情资源一致、文字和选区插入、字数/Unicode边界、未知标记/任意BBCode原文显示、等待回执的编辑锁定、重连历史、关闭/输入焦点及本地状态隔离。`SSJX_EMOTE_CAPTURE_PATH` 指定已存在目录后，以真实渲染运行可输出面板展开和接收消息两张截图。

真实数据库/独立进程联调仍使用 `tests/run_shared_world.py --render`，需要Docker PostgreSQL；其中已增加表情消息原样传输和双方显示贴图的检查。两个界面实例的协议夹具不等于真实WSS/数据库联调通过。

2026-10-15，Windows / Godot 4.7.1：表情协议界面45项、真实OpenGL渲染47项、场景资源96项、公共频道协议43项、同屏界面27项、本地模式26项通过。Python32项中31项通过、1项跳过。截图已人工检查八个表情按钮及消息中的八种图片；本机缺少Docker，未运行本轮数据库/独立进程双客户端联调。
