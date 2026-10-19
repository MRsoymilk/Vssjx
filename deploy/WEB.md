# 网页入口

[部署导航](README.md) · [公网 Docker](PUBLIC.md) · [平台方案](../design/platform_interface.md)

本指南分别覆盖本机回环、局域网 HTTPS 与公网同源部署。按一个目标环境操作；示例目录、IP、域名及工具路径需替换，不需要把所有方案依次执行。

网页入口与已运行的 Rust 游戏服务分开部署。Nginx 只挂载 Web 导出的 `public/`，同源转发 `/api/v1/` 到游戏监听，支持 WebSocket 升级。数据库、`.env`、源代码、PC 管理页面和 9090 监控不发布。

## 本机开发

用 Godot 4.7.2 及匹配模板生成本机测试包：

```powershell
python tools/export_web.py --output work/builds/web-local --template work/web-toolchain/web_nothreads_release.zip --allow-loopback-http
```

`GODOT_BIN` 指向 4.7.2 控制台程序。输出目录必须为空或不存在；后续升级使用新目录。

创建不提交的 `work/web-deploy.local.env`，按实际位置填写：

```dotenv
SSJX_WEB_ROOT=C:/workspace/Vssjx/work/builds/web-local/public
SSJX_WEB_BIND_ADDR=127.0.0.1
SSJX_WEB_PORT=8000
SSJX_WEB_UPSTREAM=http://host.docker.internal:8080
```

上例是 Windows Docker Desktop 路径与上游示例；按实际检出位置修改 `SSJX_WEB_ROOT`。Linux 宿主机上游可达性见公网部分，不照搬 `host.docker.internal` 与回环监听组合。在服务端私有 `.env` 中将这两个来源合并到 `SSJX_WEB_DEV_ORIGINS`，保留已有来源：

```dotenv
SSJX_WEB_DEV_ORIGINS=http://127.0.0.1:8000,http://localhost:8000
```

重启 Rust 服务使白名单生效，再启动独立的网页 Compose 项目，不操作已有 PostgreSQL 数据卷：

```powershell
docker compose --env-file work/web-deploy.local.env -f deploy/web.compose.yaml up -d --wait
docker compose --env-file work/web-deploy.local.env -f deploy/web.compose.yaml ps
```

打开 `http://127.0.0.1:8000/`。本机包允许的 HTTP 仅限回环来源；不能直接替换成局域网 IP 来联机。

更新网页时，重新导出到新目录，修改本地 env 的 `SSJX_WEB_ROOT`，再次执行 `up -d --wait`。只更新网页不需要重启 Rust。

## 同一局域网的手机与电脑

可选叠加 `web.lan.compose.yaml`，保持本机 8000 入口，同时在指定局域网 IP 发布 HTTPS 8443 和证书安装页 8001。Godot 启动和浏览器存档要求安全上下文；不改为允许局域网明文账号、不删除 Origin 校验、不让用户关闭浏览器安全功能。

先确认当前电脑的局域网 IPv4，例如 `192.168.1.6`，用 OpenSSL 生成仅本机持有的开发 CA 和 90 天服务端证书：

```powershell
python tools/prepare_lan_https.py --ip 192.168.1.6 --output work/web-deploy/lan-cert --openssl C:/Tools/Git/usr/bin/openssl.exe
```

按本机实际 OpenSSL 路径调整。工具拒绝覆盖已有证书集；CA 私钥位于输出根目录，只有 `server/` 中的服务证书/私钥和 `public/` 中的公开证书/安装页会分别挂载到容器。保护 CA 私钥，仅让部署用户及系统读取，不能把输出目录提交 Git 或作为网页根目录。

向私有 `work/web-deploy.local.env` 添加：

```dotenv
SSJX_LAN_IP=192.168.1.6
SSJX_LAN_DIR=C:/workspace/Vssjx/work/web-deploy/lan-cert
SSJX_LAN_TLS_PORT=8443
SSJX_LAN_SETUP_PORT=8001
```

将 `https://192.168.1.6:8443` 合并到 Rust 私有 `.env` 的 `SSJX_WEB_ALLOWED_ORIGINS`，保留原来的来源，重启游戏服务，然后运行：

```powershell
docker compose --env-file work/web-deploy.local.env -f deploy/web.compose.yaml -f deploy/web.lan.compose.yaml up -d --wait
```

后续管理这个容器时始终带上两个 Compose 文件，避免重建时移除 LAN 端口和证书挂载。操作不涉及 PostgreSQL 数据卷。Windows 防火墙启用时，只对局域网子网放行这两个端口，不公开 8080、9090 或 5432，也不需要修改整个网络的安全类别。

在访问设备上先打开 `http://192.168.1.6:8001/`，按页面说明安装并信任 **Vssjx LAN CA**，再打开 `https://192.168.1.6:8443/`。每台设备首次安装一次，不是每个玩家账号添加白名单。iOS 需要另外开启根证书完全信任；Android 的菜单名称随厂商变化。只有网页/证书已配置不能代替访问设备信任。不要在未完成信任时声称手机已验收。

Windows 当前用户可用正常的证书安装流程，或执行以下命令后确认系统提示：

```powershell
Import-Certificate -FilePath work/web-deploy/lan-cert/public/vssjx-lan-ca.cer -CertStoreLocation Cert:\CurrentUser\Root
```

这会增加当前用户的根证书信任，不修改整个机器的信任。结束开发后可按证书名称在当前用户根证书存储中移除。CA 有效期一年，服务证书 90 天；IP 变化或证书到期需重新生成并更新挂载、来源及设备信任。

## 域名与公网

正式导出省略 `--allow-loopback-http`。对外入口使用有效证书的 HTTPS，将网页及 `/api/v1/` 放在同一来源，并转发 WebSocket 升级。在 Rust 私有配置的 `SSJX_WEB_ALLOWED_ORIGINS` 中登记准确的 HTTPS 来源，生产关闭开发来源。代理必须原样保留 Origin，不能通过删除或伪造它绕过检查。

更换公网域名后，也必须更新该精确来源并重启 Rust 服务。这里登记的是网站来源，不是每位访客的 IP 或账号；同一个网址供多人使用只需登记一次。网页能打开、账号能登陆，但共享地图反复断线时，检查 `/api/v1/world/ws` 是否返回 `403 ORIGIN_NOT_ALLOWED`；正常升级应返回 `101`。隧道将完整域名转发到本机网页入口 `http://127.0.0.1:8000` 即可，网页、API 与 WebSocket 共用这个入口，不需要额外公开游戏或数据库端口。

两份 Docker Nginx 模板通过容器 DNS `127.0.0.11` 动态解析上游，并设置 `ipv6=off`。这是为避免 Docker Desktop 同时返回不可达的宿主 IPv6 地址而间歇性代理失败；不会关闭 HTTPS、浏览器来源检查或宿主机 IPv6。机制见 [Nginx resolver 文档](https://nginx.org/en/docs/http/ngx_http_core_module.html#resolver)。修改模板后重启网页容器，使入口脚本重新生成配置。

默认 Compose 仅发布本机 8000；局域网叠加配置不自动配置公网域名、路由器映射或 Windows 防火墙。公网手机访问仍需要可到达且证书受信任的 HTTPS 地址。Linux 的 `host-gateway` 通常不能访问仅绑定宿主回环的服务，应把上游设置为受控容器网络内的服务地址，或配置专用私有监听；不要因此公开数据库或监控端口。

这里只部署单个游戏进程的网页入口，不构成集群或并发容量验收。

WebSocket 配置依据 [Nginx 官方代理说明](https://nginx.org/en/docs/http/websocket.html)，缺失文件处理依据 [try_files 文档](https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files)。本机检查见 [网页部署验证](../tests/web_deployment.md)，公网历史事实见 [发布基线](../tests/release_20261018.md) 和 [后续聊天更新](../tests/chat_moderation.md)。

## 网页加载与静态资源缓存

`export_web.py` 为引擎与资源生成 `assets/<内容版本>/` URL，入口 HTML 保持重新验证；只有内容版本目录使用一年 immutable 缓存。新引擎或资源会生成新版本，避免浏览器混用旧资源。根目录文件保留为旧链接兼容入口，不赋予长期缓存。滚动升级时应保留仍被访问的旧版本静态目录，不能清理玩家浏览器存档来更新游戏。

导出同时生成 `.wasm`、`.pck`、JavaScript 的预压缩 `.gz` 副本。两份 Nginx 模板协商 `Accept-Encoding` 后发送 gzip，正确保留 MIME、Vary 与解压后的文件内容；不支持 gzip 的客户端仍能获取原文件。API 与账号响应不采用静态缓存策略，缺失版本文件不会被缓存一年。

Cloudflare 默认缓存扩展名不包含 `.wasm`、`.pck`，仅发送 Cache-Control 不能证明 CDN 已命中缓存。需在域名的 **缓存 → 缓存规则** 创建仅针对游戏静态目录的规则，例如：

```text
(http.host eq "game.example.com" and starts_with(http.request.uri.path, "/assets/"))
```

设置缓存资格为“符合缓存条件”，遵循源站 Cache-Control。不要将 `/api/v1/`、账号或 WebSocket 纳入此规则。通过响应 `CF-Cache-Status: HIT` 验证，不以本机测试代替公网命中结果。官方依据：[默认缓存扩展名](https://developers.cloudflare.com/cache/concepts/default-cache-behavior/)、[缓存规则](https://developers.cloudflare.com/cache/how-to/cache-rules/)。

加载页显示已加载 MB、资源总大小及下载／初始化阶段。20 秒没有新增进度时显示网络停顿说明与手动重新加载按钮；不会自动同时启动多个引擎或清除存档。MB 代表引擎报告的已加载资源字节，不作为压缩网络吞吐测速。
