# 门户统计与 APK 管理验证

[设计](../design/portal-management.md) · [运行说明](../deploy/PORTAL_STATS.md)

2026-10-19：仅在本地／隔离容器验证，没有 SSH、远程部署、游戏打包或推送；不会因为此前门户发布过而沿用远程操作授权。

## 命令

```sh
python -m unittest discover -s tests -p 'test_portal_*.py'
python -m unittest discover -s tests -p test_documentation.py
python tests/check_public_deployment.py --nginx --nginx-image nginx:1.29-alpine --openssl /usr/bin/openssl
node --check portal_stats/assets/app.js
```

路由测试只使用唯一名称的本地 Nginx 容器、临时证书、回环端口与伪造游戏字节，不连接游戏服务或数据库，也不拉取镜像。管理测试只使用临时 SQLite 和惰性 APK ZIP 夹具。

真实浏览器检查使用已有 `playwright-core`，通过 `PLAYWRIGHT_MODULE_PATH`／`PLAYWRIGHT_CHROMIUM_EXECUTABLE` 指定本机工具：

```sh
python tests/run_portal_admin_browser.py work/portal-admin-captures
```

门户本身的既有无脚本、布局与同源存储检查继续见 [导航测试](portal_navigation.md)，本轮门户链接改为固定统计跳转，但最终游戏和 APK 地址不变。

## 覆盖

- 采集：闭集字段、大小限制、无原始敏感日志落盘、UTC+8 边界、日期补零、重启重放去重、同 ID 内容冲突、事务回滚、退休日期防重复计数、Docker 流重连。
- Nginx：门户／页面／入口／APK 事件，HEAD／API／资源排除，原始查询、IP、凭据不出现在统计事件中，固定重定向不能变成开放重定向。
- APK：上传去重、摘要、配额、扩展名与截断输入、ZIP 路径穿越／缺清单拒绝、当前保护、显式发布、未知文件保护、旧版删除及中断重试、公开副本与原 APK 回落。
- 后台：非回环监听拒绝、Host／Origin／Sec-Fetch-Site／随机令牌、无 CORS、无任意文件／SQL／日志导入接口、日期／请求体上限与 CSV。
- 浏览器：统计卡片、日期查询、趋势与 CSV、真实上传／发布／删除、当前版禁删、恶意显示名纯文本、手机布局、无第三方请求与 CSP 错误。

## 已验证结果

- Python `test_portal_*.py` 共 39 项通过；原门户浏览器 33 项通过。
- 私有后台实际 Chromium 14 项通过，已人工查看桌面统计和手机 APK 页面。
- 公网 Compose／Nginx 检查 25 项通过，包含可选 APK 公开挂载不改变游戏／PostgreSQL 配置，以及原有 TLS／Web 覆盖保留；文档回归 6 项通过。
- 截图和夹具仅在 Git 忽略目录 `work/portal-admin-final-20261019/`、`work/portal-stats-browser-20261019/`，不提交私有数据库或 APK 文件。

额外 APK 插值参数使用独立 `deploy/portal-apks.local.env`，而不是根 `.env`，避免根配置被游戏 `env_file` 读取后间接改变其容器环境。两份 Compose／续期助手使用假 Docker CLI 验证参数顺序，不执行部署或证书申请。

不把请求指标当作独立访客、下载完成或安装人数。不以 APK 容器检查代替签名审计、真实 Android 安装或设备兼容验证。未用真实生产 APK、账号、玩家存档或数据库做破坏性操作。
