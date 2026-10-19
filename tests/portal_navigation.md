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

## 子路径与代理验证

```sh
python -m unittest discover -s tests -p test_portal_routes.py
python -m unittest discover -s tests -p test_web_static_assets.py
python tests/check_public_deployment.py --nginx --nginx-image nginx:1.29-alpine --openssl /usr/bin/openssl
```

路由测试需要 Linux Docker host 网络、OpenSSL 及已缓存的 Nginx 镜像。`SSJX_TEST_NGINX_IMAGE` 可指定本地镜像；不拉取镜像，缺少依赖时报告跳过。测试创建唯一名称的容器、临时证书和回环端口，不使用现有容器、证书、私有 `.env` 或数据库。夹具的 JS／WASM／PCK／APK 都是不可执行占位字节，不构建游戏。

覆盖首页文件存在性开关及回退、预览、新旧入口字节一致、尾斜杠与查询参数、版本资源 gzip／缓存、缺失资源 404、WASM MIME、APK、隐藏文件及管理路径、API 授权／Origin 不改写、Flarum 404 预留。测试在真实 TLS WebSocket 上发送消息，平滑 reload，等待新 worker 的专用响应头出现后，再验证原连接继续收发。

浏览器检查另调用**真实的游戏 IndexedDB 适配源码**，在测试旧路径写入专用记录，经过导航点击进入同源 `/webgame/` 后读取相同记录。测试页面本身没有游戏引擎；这只验证路径与存储契约，不冒充完整 Godot 游玩或生产存档迁移。

### 最终结果（2026-10-19）

- 导航静态 5 项、真实 Nginx／TLS 路由 7 项、既有静态资源回归 2 项通过（平台中立调整前的基线）。
- 公网 Compose／配置验证 23 项通过，包含真实 Nginx 解析与续期脚本检查；使用缓存的 `nginx:1.29-alpine`，不宣称已在远程实际镜像重新验收。
- Chromium 页面及真实存储适配检查合计 32 项通过；最终截图在 `/tmp/opencode/vssjx-portal-captures-final-20261019/`。
- 公网配置保留原静态挂载，无需新增卷、PHP／论坛服务或游戏数据库迁移；页面与路由只提交本地候选，未推送、导出游戏或远程部署。

## 平台中立的游戏条目调整

按用户要求，门户不默认引导网页版：顶部“游戏”和主按钮先定位到同一张游戏卡片，网页游玩与 Android 预览版作为该条目的并列选择；删除独立下载条目。论坛仍是另一个筹备中条目。

静态回归增加同一游戏卡片、平台选择和无网页默认跳转检查；浏览器检查通过主按钮定位后，再显式选择网页，继续验证同源存档。

调整后：静态 6 项、真实浏览器 33 项、Nginx／TLS 路由 7 项通过；已人工复核桌面及手机截图。最新截图位于 `/tmp/opencode/vssjx-portal-project-entry-captures-20261019/`，不替换或发布现有游戏。

## 后续公网切换

上述是本地制作阶段的记录。2026-10-19 后续经明确授权，已仅部署门户与兼容路由；未更新游戏包或后端。实际远程镜像、76 份静态文件摘要、容器保留、48 项 HTTPS 检查和 13 项浏览器验收另见 [门户发布记录](portal_release_20261019.md)，不以本地夹具结果替代公网事实。
