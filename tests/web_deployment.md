# 当前电脑网页部署验证（2026-10-17）

部署说明见 `deploy/WEB.md`。本轮没有修改客户端或服务端源码，没有推送远程分支。

## 部署状态

- Docker Compose 项目 `vssjx-web`，容器 `vssjx-web-web-1`，默认只监听 `127.0.0.1:8000`，健康检查通过。
- 挂载 `work/builds/web-local-20261017-7c477c5/public`，Godot 4.7.2 官方单线程模板，源码为 `7c477c5` 加部署文件；只在导出副本允许本机回环 HTTP。原正式 HTTPS 包保留。
- `/api/v1/` 原路径代理到宿主 `127.0.0.1:8080` 对应服务，经 Docker Desktop 的 `host.docker.internal` 访问。Authorization 与浏览器 Origin 保留，WebSocket 升级正常。
- 服务端私有 `.env` 合并 `http://127.0.0.1:8000`、`http://localhost:8000` 精确开发来源后重启一次；重启前监控显示在线玩家为 0。原配置备份位于忽略的 `work/web-deploy/server.env.before`，未更换数据库、账号或数据卷。
- 这不是 Windows 开机服务安装，也没有配置手机、公网 HTTPS、域名、端口映射或并发容量。

## 验证

```powershell
python tests/check_web_deployment.py --public work/builds/web-local-20261017-7c477c5/public
node tests/web_deploy_browser.cjs http://127.0.0.1:8000 work/web-deploy/browser
```

浏览器脚本使用 `PLAYWRIGHT_MODULE_PATH` 与 `PLAYWRIGHT_CHROMIUM_EXECUTABLE` 指定已有 Playwright/浏览器路径，运行独立临时浏览器上下文。不会使用玩家 Cookie、密码或创建账号。

- HTTP/WS 14 项通过：部署文件逐一哈希一致、WASM MIME 正确、同源账号服务可达、未认证账号接口返回 401、私有配置/监控/管理脚本不发布、缺失 WASM 返回 404、可信 Origin 升级成功、非可信 Origin 仍由后端拒绝。
- 实际 Edge/Chromium 浏览器 5 项通过：Godot WASM 启动并进入本站联机登录页、真实 UI 的不存在账号登录请求通过同源代理返回 401、浏览器原生 WebSocket 携带本页 Origin 升级成功、无凭据写入浏览器 key/value 存储、无浏览器或 GDScript 运行时错误。
- 浏览器检查没有验证真实账号登录后的多人游戏；既有联机角色与战斗验收见 `tests/online_pve.md`。本轮不创建测试账号或角色到已有用户数据库。

日志、截图和本机参数仅保留在忽略的 `work/web-deploy/` 及 `work/web-deploy.local.env`。`nginx -t`、Compose 参数解析和容器健康检查通过；PostgreSQL 原容器持续运行。
