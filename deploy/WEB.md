# 网页入口

网页入口与已运行的 Rust 游戏服务分开部署。Nginx 只挂载 Web 导出的 `public/`，同源转发 `/api/v1/` 到游戏监听，支持 WebSocket 升级。数据库、`.env`、源代码、PC 管理页面和 9090 监控不发布。

## 当前电脑

用 Godot 4.7.2 及匹配模板生成本机测试包：

```powershell
python tools/export_web.py --output work/builds/web-local --template work/web-toolchain/web_nothreads_release.zip --allow-loopback-http
```

`GODOT_BIN` 指向 4.7.2 控制台程序。输出目录必须为空或不存在；后续升级使用新目录。

创建不提交的 `work/web-deploy.local.env`，按实际位置填写：

```dotenv
SSJX_WEB_ROOT=F:/project/Vssjx/work/builds/web-local/public
SSJX_WEB_BIND_ADDR=127.0.0.1
SSJX_WEB_PORT=8000
SSJX_WEB_UPSTREAM=http://host.docker.internal:8080
```

在服务端私有 `.env` 中将这两个来源合并到 `SSJX_WEB_DEV_ORIGINS`，保留已有来源：

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
python tools/prepare_lan_https.py --ip 192.168.1.6 --output work/web-deploy/lan-cert --openssl F:/Git/usr/bin/openssl.exe
```

按本机实际 OpenSSL 路径调整。工具拒绝覆盖已有证书集；CA 私钥位于输出根目录，只有 `server/` 中的服务证书/私钥和 `public/` 中的公开证书/安装页会分别挂载到容器。保护 CA 私钥，仅让部署用户及系统读取，不能把输出目录提交 Git 或作为网页根目录。

向私有 `work/web-deploy.local.env` 添加：

```dotenv
SSJX_LAN_IP=192.168.1.6
SSJX_LAN_DIR=F:/project/Vssjx/work/web-deploy/lan-cert
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

默认 Compose 仅发布本机 8000；局域网叠加配置不自动配置公网域名、路由器映射或 Windows 防火墙。公网手机访问仍需要可到达且证书受信任的 HTTPS 地址。Linux 的 `host-gateway` 通常不能访问仅绑定宿主回环的服务，应把上游设置为受控容器网络内的服务地址，或配置专用私有监听；不要因此公开数据库或监控端口。

这里只部署单个游戏进程的网页入口，不构成集群或并发容量验收。

WebSocket 配置依据 [Nginx 官方代理说明](https://nginx.org/en/docs/http/websocket.html)，缺失文件处理依据 [try_files 文档](https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files)。本机检查记录见 `tests/web_deployment.md`。
