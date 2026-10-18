# 公网 Docker 部署：Ubuntu/Debian，只有公网 IP

本方案部署游戏后端。PostgreSQL、Rust、Nginx和Certbot均在Docker中运行；宿主机只需要Docker Engine、Compose v2及定时任务。游戏客户端仍单独运行，Web游戏的静态导出另见`WEB.md`。

适用于常规rootful Linux Docker Engine。游戏与Nginx使用host网络，Rust绑定127.0.0.1:8080，监控绑定127.0.0.1:9090，PostgreSQL仍通过现有Compose仅发布127.0.0.1:5432。Nginx对外提供80/443。host网络不使用ports映射，也不适用于未启用host网络支持的Docker Desktop或rootless Docker。

来源：Docker [host网络](https://docs.docker.com/engine/network/drivers/host/)、[启动与健康依赖](https://docs.docker.com/compose/how-tos/startup-order/)。

## 1. 同步代码与现有数据库

在服务器检出包含这些部署文件的已推送提交；只同步`dev`不会取得其他尚未合入的分支。服务器构建Linux二进制，不使用Windows的exe，也不需要宿主机安装Rust。

所有命令在仓库根目录执行。以下示例假设仓库位于`/opt/Vssjx`，按实际路径调整。不要覆盖已有`.env`，不要更换已有数据库密码，不执行`down -v`。两份部署覆盖文件不修改基础`compose.yaml`的项目名与`postgres-data`卷；如果原部署使用`-p 自定义项目名`，所有命令都继续带同一个项目名，避免接入新空卷。

先确认已有容器及80/443/8080/9090端口的使用情况；不要同时运行宿主机版Rust/Nginx与这套监听相同端口的容器。

## 2. 私有配置

参考`public.env.sample.txt`，把下面字段合并进仓库根目录的私有`.env`：

```dotenv
SSJX_POSTGRES_BIND_ADDR=127.0.0.1
SSJX_POSTGRES_PORT=5432
SSJX_POSTGRES_USER=vssjx
SSJX_POSTGRES_DB=vssjx
SSJX_POSTGRES_PASSWORD=现有数据库密码
SSJX_DATABASE_URL="postgresql://vssjx:现有数据库密码@127.0.0.1:5432/vssjx"
SSJX_PUBLIC_IP=你的真实公网IP
SSJX_ACME_EMAIL=你的有效邮箱
SSJX_SERVER_NAME="蜀山剑侠服务器"
SSJX_WEB_DEV_ORIGINS=
```

使用已有账号、库名、端口和密码；密码含URL特殊字符时，在数据库URL中百分号编码。新库可用随机十六进制密码。由于游戏容器使用host网络，数据库URL使用宿主回环地址，不能把主机改为`postgres`。

原生Godot客户端不需要浏览器Origin配置；若还部署Web游戏，将准确的`https://公网IP`加入`SSJX_WEB_ALLOWED_ORIGINS`。服务环境文件由Compose读取，不打入镜像；构建上下文白名单只允许Rust源码、迁移与编译嵌入的JSON定义。

云安全组/防火墙保留实际SSH端口，并允许公网TCP80/443。80需持续开放以支持证书验证与续期。8080、9090和5432不对公网开放。

## 3. 构建、启动数据库与HTTP验证入口

```sh
cd /opt/Vssjx
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  up -d --build
```

这是首次启动、尚无证书时的配置。Certbot在tools profile中，不会自动申请证书。Compose等待PostgreSQL健康后启动游戏，游戏启动自动执行数据库迁移。此时公网80只提供ACME验证文件，其他路径404；账号API仍未公开。

```sh
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml ps
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml logs --tail=100 game
curl --fail http://127.0.0.1:8080/readyz
```

## 4. 显式申请公网IP证书

Let’s Encrypt现已支持IPv4/IPv6证书；必须使用shortlived配置，证书约6天有效。本方案固定Certbot5.8.0（IP webroot支持要求至少5.4），证书名称固定为`vssjx-ip`，Nginx配置无需手工替换IP路径。

```sh
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  run --rm certbot
```

该命令读取`.env`中的真实IP与邮箱，向Let’s Encrypt生产环境申请受信任证书。成功后才执行下一步。失败时检查公网80到当前服务器的可达性、IP准确性与Nginx日志，不用自签名证书替代公网证书，也不关闭客户端验证。

官方说明：[IP证书与Certbot](https://letsencrypt.org/2026/03/11/shorter-certs-certbot/)。证书、ACME账号及续期配置位于持久卷中。

## 5. 启用HTTPS

```sh
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  -f deploy/public.tls.compose.yaml up -d
```

TLS覆盖文件只替换Nginx配置挂载，不更换数据库或证书卷。之后日常up/ps/logs/exec操作始终带三份Compose文件，避免恢复成首次HTTP配置。

```sh
curl --fail https://你的公网IP/api/v1/server-info
```

应在正常证书验证下返回服务JSON，客户端服务器地址填写`https://你的公网IP`。Nginx保留WebSocket升级、Authorization及原始Origin，仅转发`/api/v1/`；监控和源代码不发布。网站根路径返回404是预期行为，此方案没有托管Web游戏静态文件。

WebSocket依据：[Nginx官方说明](https://nginx.org/en/docs/http/websocket.html)。

## 6. 自动续期

先测试ACME续期：

```sh
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  -f deploy/public.tls.compose.yaml run --rm certbot renew --dry-run
```

在Linux宿主机以能运行Docker的用户设置定时任务（例如`sudo crontab -e`）：

```cron
0 */6 * * * /bin/sh /opt/Vssjx/tools/renew-public-certificate.sh
```

脚本自动切换到自己的仓库根目录，不source或执行`.env`；Certbot成功更新证书时写入持久卷标记，宿主脚本再检查并重载Nginx，成功后清除标记。失败时保留标记供重试。Certbot容器不挂载Docker socket。定期检查定时任务结果与证书有效期；6天证书不可只依靠手动更新。

机制依据：[Certbot renew与deploy hook](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)。

### 同时迁移已有网页客户端

将已导出的`public`目录复制到服务器，例如`/opt/Vssjx/public`。仅复制可公开的导出产物，不将项目源码或配置目录作为网页根目录。在`.env`中设置`SSJX_PUBLIC_WEB_ROOT=/opt/Vssjx/public`，并保持`SSJX_WEB_ALLOWED_ORIGINS=https://真实公网IP`。

申请证书并启用TLS后，额外应用网页覆盖文件：

```sh
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  -f deploy/public.tls.compose.yaml -f deploy/public.web.compose.yaml up -d
```

以后日常操作都保留这四份Compose文件。`renew-public-certificate.sh`检测到`.env`中的非空`SSJX_PUBLIC_WEB_ROOT`时自动保留网页覆盖文件。浏览器访问`https://真实公网IP/`，API仍通过同源`/api/v1/`连接；网页缺失资源返回404，带版本的资源保留长期缓存。

## 7. 监控、更新与备份

监控从本机SSH隧道访问：

```sh
ssh -N -L 9090:127.0.0.1:9090 用户名@公网IP
```

浏览器打开`http://127.0.0.1:9090/`。因为游戏容器使用Linux host网络，监听及实际TCP对端都保持原来的本机监控约束。无需把9090发布到公网。

更新前备份数据库（备份目录在仓库之外且仅当前用户可读）：

```sh
umask 077
mkdir -p /opt/vssjx-backups
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  -f deploy/public.tls.compose.yaml \
  exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "/opt/vssjx-backups/vssjx-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

数据库备份包含账号、角色和其他持久化进度；`.env`及证书卷也需纳入受限备份。备份应复制到独立存储，并定期验证恢复。

同步明确的新提交后重建并更新游戏容器：

```sh
docker compose --env-file .env \
  -f deploy/compose.yaml -f deploy/public.compose.yaml \
  -f deploy/public.tls.compose.yaml up -d --build game
```

迁移会自动执行。数据库迁移后的回退需结合兼容性和备份，不保证旧二进制可直接读取新结构。本方案仍为单个权威世界进程，不要直接扩展game副本共用数据库。

## 验证与限制

```sh
python tests/check_public_deployment.py
python tests/check_public_deployment.py --nginx --context --openssl /usr/bin/openssl
```

检查仅使用独立临时配置、假数据库参数、测试证书与唯一名称的容器/镜像，不读取私有`.env`，不启动现有Compose服务、不请求公网证书、不修改系统信任。

2026-10-18：19项检查通过，覆盖Compose合并与私有监听、两份真实Nginx配置解析、续期脚本语法，以及实际Docker构建上下文的白名单隔离。当前电脑访问Docker Hub授权接口超时，Rust/Debian基础镜像未能拉取，因此完整Rust镜像构建及Linux公网运行尚未验收；服务器需实际执行构建、健康检查、证书申请与续期测试后再开放玩家。
