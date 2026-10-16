# 手机网页文本输入（2026-10-17）

Web 的 `LineEdit` 现在由浏览器原生单行输入框负责实际编辑。触摸焦点交接在用户手势中进行；密码使用 `type=password`，关闭自动大小写、拼写检查和自动纠错。Godot 保留原有控件边框及焦点，聚焦时暂停其原生编辑状态，避免重绘时反复启用引擎隐藏 IME、抢走 HTML 输入焦点。原生客户端仍使用原来的 Godot 文本适配器。

输入框位置随画布和 `visualViewport` 更新；软键盘压缩可视区域后，游戏整体缩放以保留输入框。未聚焦的输入框由 Godot 绘制，HTML 层不拦截地图或弹窗。移除场景、隐藏控件或销毁适配器会删除相应 DOM 输入框并清空其值。

中文候选保留在浏览器的组合输入中，`compositionend` 后才同步到 Godot 草稿。组合期间的 Enter/229 不提交登录或聊天；正常发送仍经过原有提交检查及聊天幂等回执。光标和选择按 UTF-16 与 Unicode 码点转换，支持汉字、表情、粘贴、程序化清空和表情插入。平台结果、配置、日志及浏览器存储不包含密码或草稿；DOM 仅保留当前编辑所必需的值。

## 验证

```powershell
$env:PLAYWRIGHT_MODULE_PATH='<playwright-core 路径>'
$env:PLAYWRIGHT_CHROMIUM_EXECUTABLE='<Chromium/Edge 路径>'
$env:SSJX_TEST_SERVER_BIN='<已构建的测试服务器>'
python tests/run_web_text_input.py --public <导出目录/public> --output work/web-text-input-live
python tests/run_web_game.py --public <导出目录/public> --output work/web-text-input-ui
```

输入测试启动独立 PostgreSQL 容器和 Rust 服务，仅使用临时账号，通过测试专用同源 HTTP/WebSocket 转发连接真实 WASM。不会使用现有游戏服务、账号或玩家数据库。测试密码经子进程标准输入传递，不写入报告。临时数据库和服务在结束后清理。

- Windows Chromium 触摸及手机尺寸模拟：13 项通过。密码焦点稳定超过隐藏 IME 的定时周期，快速输入及含中文的测试密码成功登录；缩小视口后密码框可见；进入地图后，中文候选确认不会发送拼音，中文和 emoji 完整发送一次并收到实际服务端回执，双端草稿清空。
- 公共 Web 包启动、一次点击进入登录、拒绝登录、返回、横竖屏与重载：6 项通过。
- Windows Godot 4.7.1 原生回归：输入接口 35、登录页 49、游戏模式 1048、公共聊天 48、表情 45、扩展聊天 37 项通过。修正输入接口旧断言：离线创建完成后进入角色选择，与当前产品流程一致。
- 实际 Web 包使用官方 Godot 4.7.2 单线程模板，输入适配器 JS 随 PCK 打包；不额外下载输入插件。

组合事件由测试明确构造，浏览器模拟不能替代 Android/iOS 真机系统键盘验收。尚未在实体手机上检查搜狗、系统拼音、Safari 自动填充及候选窗口位置。

此项接续 [P1c 原生输入历史记录](platform_input_actions.md)，不将其中历史验证改写成手机验收。

参考：Godot [LineEdit](https://docs.godotengine.org/en/stable/classes/class_lineedit.html)、[Web 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)，以及锁定版本 [LineEdit 原生实现](https://github.com/godotengine/godot/blob/4.7/scene/gui/line_edit.cpp) 中绘制时更新 IME 的行为；引擎 JS 行为也对照实际导出的官方 `index.js`。
