# 默认本地入口与控制指令帮助

2026-10-21。源码与实际 Godot OpenGL 界面验证，无部署、打包、远端推送或用户数据库变更。

- 原生无地址配置时默认 `local`，无需账号，默认值不隐式写入文件；已有有效地址照常回填，非法草稿不覆盖历史地址。Web 同样默认 `local`，可填写本站配置的联机地址；对外站目标的拒绝、凭据存储限制与同源策略保持有效。
- 本地／联机共用十行菜单，在“系统”下方追加“帮助”，保持原菜单顺序、窄宽及底部对齐。帮助使用纸面、木纹主题，展示已实现的 `/control`、`/control help`、`lv`、`hp`、`money` 用法、范围与示例；长内容可滚动、选中复制。
- 打开帮助暂停本地移动、阻止联机背景移动输入；返回及 Escape 可关闭。查看帮助不修改等级、气血、铜币或存档，也不会发送控制指令；联机帮助明确提示仅 local 生效。
- 菜单旧回归中的社交、队伍、帮派预期已按现有已实现面板更新，保留具体路由和本地存档不变的断言。

结果：服务器地址42项、Web策略124项、登录界面59项、菜单及帮助77项、本地指令59项通过，共361项；编辑器导入和 `git diff --check` 通过。菜单、帮助与原控制指令使用实际 OpenGL 运行，已检查本地和联机帮助截图。

```powershell
$godot="work/web-toolchain/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path client res://tests/server_connection_test.tscn
& $godot --headless --path client res://tests/platform_web_security_test.tscn
& $godot --path client --rendering-method gl_compatibility res://tests/login_ui_test.tscn
$env:SSJX_MENU_CAPTURE_PATH="$PWD/work/help-menu"
& $godot --path client --rendering-method gl_compatibility res://tests/game_menu_test.tscn
& $godot --path client --rendering-method gl_compatibility res://tests/local_control_test.tscn
```

截图和日志只保存在忽略的 `work/help-menu`、`work/help-current-*.log`，不提交临时存档、连接配置或凭据。
