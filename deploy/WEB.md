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

## 域名、手机与公网

正式导出省略 `--allow-loopback-http`。对外入口使用有效证书的 HTTPS，将网页及 `/api/v1/` 放在同一来源，并转发 WebSocket 升级。在 Rust 私有配置的 `SSJX_WEB_ALLOWED_ORIGINS` 中登记准确的 HTTPS 来源，生产关闭开发来源。代理必须原样保留 Origin，不能通过删除或伪造它绕过检查。

该 Compose 默认仅发布本机 8000，不自动配置公网域名、TLS、路由器映射或 Windows 防火墙。手机远程访问仍需要可到达且证书受信任的 HTTPS 地址。Linux 的 `host-gateway` 通常不能访问仅绑定宿主回环的服务，应把上游设置为受控容器网络内的服务地址，或配置专用私有监听；不要因此公开数据库或监控端口。

这里只部署单个游戏进程的网页入口，不构成集群或并发容量验收。

WebSocket 配置依据 [Nginx 官方代理说明](https://nginx.org/en/docs/http/websocket.html)，缺失文件处理依据 [try_files 文档](https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files)。本机检查记录见 `tests/web_deployment.md`。
