# 局域网网页入口（2026-10-17）

## 已部署

- 现有网页容器叠加 `deploy/web.lan.compose.yaml`，绑定本机 `192.168.1.6`：8443 提供 HTTPS 游戏/API/WSS，8001 只提供证书安装说明与公开证书。原 `127.0.0.1:8000` 保持可用。
- 使用本机 OpenSSL 生成一年有效的开发 CA、90 天有效的服务端证书，SAN 包含局域网 IP、localhost、127.0.0.1。服务端只增加准确的 `https://192.168.1.6:8443` 来源，不放宽客户端凭据、同源、原生 HTTP 或后端 Origin 策略。
- 私有证书集位于忽略目录 `work/web-deploy/lan-20261017`，CA 签名私钥不挂载容器、不发布网页，Windows ACL 仅部署用户及 SYSTEM 可读。容器分别只读挂载服务证书/密钥与公开安装文件。
- 通过正常 `Import-Certificate` 流程把本次 CA 安装到 Windows 当前用户根证书存储，用于真正的证书校验；没有导入 LocalMachine 存储，没有关闭浏览器 TLS 校验，没有使用 `ignoreHTTPSErrors`、证书忽略命令行参数或不安全来源模拟安全上下文。
- 后端在在线玩家为 0 时重启一次，使精确来源生效。没有替换数据库、用户密码或数据卷，没有改变 Windows 防火墙配置。

## 验证

```powershell
python tests/check_lan_deployment.py --lan-dir work/web-deploy/lan-20261017 --public work/builds/web-local-20261017-7c477c5/public
node tests/web_deploy_browser.cjs https://192.168.1.6:8443 work/web-deploy/lan-browser
python tests/check_web_deployment.py --public work/builds/web-local-20261017-7c477c5/public
```

- LAN HTTPS/WSS 19 项通过：Python 明确加载此 CA，正常校验证书链和主机 IP；游戏文件与导出包哈希一致；账号接口可达；公开根证书指纹与实际 CA 一致；iOS 配置与 CA 下载 MIME 正确；两种入口均不公开私钥、`.env` 或监控；WSS 握手摘要正确，未知来源仍返回 403。
- 实际 Windows Edge/Chromium 5 项通过：访问局域网 IP 的 HTTPS 地址，使用系统已信任 CA，不忽略证书错误；Godot WASM 正常启动、页面是安全上下文、真实 UI 登录请求到达代理并收到不存在账号的 401、浏览器 WSS 升级正常、没有凭据写入 key/value 存储、没有运行时脚本错误。
- 原本机入口 HTTP/WS 14 项回归通过。`nginx -t`、Compose 校验和容器健康检查通过。
- 浏览器首次检查时默认零延迟键盘输入仅让游戏收到一个字符，服务端正确返回 422 INVALID_USERNAME；调整测试输入为逐键 80ms 后通过。没有因此修改登录规则或把 422 当作 401 验收。

测试没有在用户数据库创建账号/角色，没有用玩家凭据登录。日志/截图在 `work/web-deploy/lan-check.log`、`lan-browser.log`、`lan-browser/`、`check-after-lan.log`。没有实际 Android/iPhone 或第二台物理设备验收，也没有公网或容量结论。

## 访问设备必须完成的步骤

手机/其他电脑连接同一局域网，先打开 `http://192.168.1.6:8001/`，在该设备安装并信任 **Vssjx LAN CA**，再访问 `https://192.168.1.6:8443/`。本机的信任不会自动复制给其他设备。iOS 还需要单独开启根证书完全信任，参考 [Apple 官方说明](https://support.apple.com/en-us/102390)。这不是给每个玩家账号加白名单。

服务器的 HTTPS 与可信安全上下文要求参照 [Godot Web 文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)、[Nginx HTTPS 配置](https://nginx.org/en/docs/http/configuring_https_servers.html)。LAN IP 变更或证书到期时按 `deploy/WEB.md` 重新生成证书并更新挂载、来源及设备信任。
