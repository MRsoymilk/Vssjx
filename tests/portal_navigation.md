# 导航首页与游戏子路径验证

## 范围与隔离

2026-10-19：导航页面与 `/webgame/` 兼容路由的本地候选验证，不修改游戏逻辑、旧导出包、存档、服务端或数据库，不推送、导出游戏或切换公网。

页面源文件在 `deploy/portal/`；`tools/prepare_portal.py` 仅准备三个导航静态文件，使用原应用图标缩小生成 WebP，不重绘或覆盖原图。论坛保持“筹备中”，不自动安装或连接 Flarum。

## 导航静态回归

```sh
python -m unittest discover -s tests -p test_portal_page.py
python tools/prepare_portal.py --output work/portal-preview
```

输出目录必须为空或不存在。回归覆盖游戏／APK 链接、禁用论坛、无脚本／表单／自动资源预取、锚点、外链保护、图标体积与可重复准备、不覆盖既有文件。

## 实际浏览器预览

需要 `playwright-core` 和匹配的 Chromium，依赖可放在独立工具目录，不加入项目运行依赖。沿用现有测试约定，通过 `PLAYWRIGHT_MODULE_PATH` 与 `PLAYWRIGHT_CHROMIUM_EXECUTABLE` 指定路径：

```sh
node tests/portal_browser.cjs work/portal-preview work/portal-captures
```

脚本仅启动临时回环 HTTP 服务，提供三个导航文件，无游戏服务或账号接口；自动关闭测试浏览器与监听。检查 1440×1000、390×844、320×740、844×390 布局、禁用状态、图像解码、键盘跳转、减少动态效果及实际网络请求，并保存截图。

## 页面阶段结果

- Python 静态检查 5 项通过。
- 实际 Chromium 浏览器 29 项通过，无脚本／CSP 错误，无横向溢出；导航未请求游戏引擎、API、论坛或第三方资源。
- 已人工查看桌面和手机全页截图；导航三文件共 40,101 字节，图标 26,604 字节，相比原 2.8 MB 图片大幅缩小。
- 截图在本机 `/tmp/opencode/vssjx-portal-captures-20261019/`，不提交截图、浏览器依赖或测试产物。

页面预览不是实际 Godot 启动、手机真机或论坛验收。真实远程版本与现有 Nginx 挂载仍需在明确部署授权后核对。
