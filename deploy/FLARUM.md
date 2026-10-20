# Flarum 论坛部署与维护

[部署导航](README.md) · [门户路由](PORTAL.md) · [2026-10-20 发布与验证](../tests/flarum_release_20261020.md)

## 当前状态

2026-10-20 已按明确授权部署 **Flarum 2.0.2 + PHP 8.3.35 + SQLite**，简体中文界面：

- 论坛：`https://47.93.114.190/flarum/`；管理页：`https://47.93.114.190/flarum/admin`。
- 门户已经开放论坛链接；游戏入口和原 APK 不变。
- **公开注册关闭**，邮件为 `log`，尚无可用 SMTP。不要把当前状态当作完整开放运营。
- 游戏与论坛账号独立，论坛没有 PostgreSQL、游戏凭据或 Docker socket 挂载。
- 本轮没有部署私有统计、APK 管理，也没有推送 Git。

## 独立运行边界

```text
现有公网 Nginx（原容器，平滑 reload）
└── /flarum/ → 127.0.0.1:8082 → vssjx-forum-forum-1
                                  └── /data → 独立论坛状态
```

Compose 为 `deploy/flarum/compose.yaml`，项目名 `vssjx-forum`，不叠加到游戏 Compose。只发布 `127.0.0.1:8082`，限制 384 MiB 内存、总内存加 Swap 512 MiB、0.75 CPU、96 PID，Apache 最多两个请求进程。根文件系统只读，只有状态目录与少量 tmpfs 可写。

宿主独立目录为 `/home/ssjx/services/vssjx-forum`：

| 路径 | 用途 |
|---|---|
| `release/` | 已校验镜像归档、独立 Compose 和维护工具 |
| `forum.env` | 镜像 ID 和独立状态路径，不进入游戏环境 |
| `state/` | `forum.sqlite`、`config.php`、缓存／会话／日志、公开 assets |
| `bootstrap/admin-credentials.json` | 初始管理员凭据，权限 0600，上层目录 0700 |
| `backups/` | 原代理／门户／容器／静态摘要与论坛初始备份，均不公开 |

只将应用 `public/` 暴露给 HTTP，SQLite、配置、vendor 和日志路径均被拒绝。会话 Cookie 为 Secure、HttpOnly、SameSite=Lax，限制在 `/flarum`。同源路径仍不是浏览器安全隔离；不要随意安装不可信插件。

## 管理员交接与邮件

用户名 `admin`，使用随机密码，未在聊天、源码或日志中显示。由有权限的操作者在自己的终端读取：

```sh
ssh ssjx@47.93.114.190 'cat /home/ssjx/services/vssjx-forum/bootstrap/admin-credentials.json'
```

首次登录后改为本人邮箱并修改密码；`admin@example.invalid` 只是占位地址。之后按凭据管理规则处理初始凭据文件，不把它放进 Git 或公开备份。临时 `install.json` 已移除。

开放注册前需要另外配置 SMTP、实际验证注册／验证邮件／找回密码，并审查发帖权限、防垃圾注册和上传策略。不要在 `log` 邮件模式下开放公众注册，也不要借用游戏密码做论坛单点登录。

## 镜像准备与升级边界

首次安装的本地准备入口：

```sh
python tools/prepare_flarum.py --output work/flarum-context
docker build --build-arg COMPOSER_SHA384="$(cat work/flarum-context/composer.sha384)" -t vssjx-forum:2.0.2-20261020 work/flarum-context
```

工具使用固定 SHA256 核验官方 Flarum 安装包与 Composer 2.10.3；Dockerfile 固定 PHP 基础镜像摘要。简体中文包固定 2.0.0。已部署镜像 ID：`sha256:901df9daf6d20a5f4ca454094776a6df35ce189ffc659a1ad535f601adac79cf`。本轮在本机准备后传输镜像，没有在低内存服务器运行 Composer 或游戏构建。

仅新安装可用 `tools/initialize_flarum_config.py` 创建私有输入，再显式运行镜像内 `flarum-initialize`；它拒绝覆盖现有 `config.php`。常态启动不自动安装／迁移，不重新生成管理员密码。不要把首次安装流程当作升级命令。

升级前备份论坛数据库和 assets，核验核心与扩展兼容性；新镜像的依赖审计、迁移、测试和部署需要新的明确授权。PHP 配置启用 OPcache 且不检查文件时间，修改应用配置或代码后需仅重启论坛容器，不需重启游戏。

## 日常查看与备份

以下为已部署目录的只读检查入口：

```sh
docker compose --env-file /home/ssjx/services/vssjx-forum/forum.env -f /home/ssjx/services/vssjx-forum/release/compose.yaml ps
docker exec -u www-data vssjx-forum-forum-1 php flarum info
```

`ssjx` 用户 crontab 每分钟通过 `flock` 串行运行一次该容器的 `php flarum schedule:run`，不触碰游戏；任务输出不写公开日志。初始执行已经验证，原 crontab 内容另有备份。

手动生成论坛备份（在服务器上执行）：

```sh
python3 /home/ssjx/services/vssjx-forum/release/backup_flarum.py --directory /home/ssjx/services/vssjx-forum/backups/forum
```

使用 SQLite 在线备份 API 生成一致的数据库快照，再与 `config.php`、assets 一起归档；不会直接复制活跃 WAL 主文件，不归档会话或初始明文密码。初始备份已检查 SQLite 完整性。assets 是在线复制，若需严格对应大量并发上传，应安排仅论坛维护窗口。

**尚未配置每日自动备份、异机备份或自动清理**，也未完成停服恢复演练。备份包含论坛私有数据，应限制读取并监控磁盘；不要将备份放入静态目录。恢复必须先停论坛写入，将归档中的 `.backup-<时间>.sqlite` 恢复为 `forum.sqlite` 并配套恢复配置／assets、权限与版本；不要向运行中的数据库覆盖文件，不操作游戏 PostgreSQL。

## Nginx 与门户维护

路由片段为 `deploy/flarum/public.locations.conf`。`tools/configure_flarum_proxy.py` 只接受恰好一组已核对的 404 预留块，输出新候选，不覆盖原文件；保留 `/flarum` 前缀。已经启用论坛的配置不应再次套用这个首次接入工具。

本次使用**实际线上配置**生成候选，未整份发布当前仓库模板，因此没有夹带尚未授权的统计／APK 管理。以后维护时先读取真实挂载配置，保留论坛代理；直接覆盖 `deploy/public.web.https.nginx.conf` 或全套 Compose 重建可能会关闭论坛或误启用其他本地功能。

`tools/prepare_portal.py --forum` 可显式生成含论坛链接的候选，默认仍保留筹备状态供无论坛的部署使用。但当前源模板的统计跳转尚未上线，不能不加核对地将整份新模板上传。此次仅对线上原 HTML 开放论坛链接，原游戏和下载 href 保留。

回退时，先使用 `backups/original.portal.html` 恢复门户，再原位恢复 `backups/original.nginx.conf` 到实际单文件挂载源，`nginx -t` 后平滑 reload。停止论坛及移除带 `# vssjx-forum scheduler` 的专属 cron 行即可停止独立运行；保留状态与备份，不执行 `down -v`，不回退游戏数据库。

## 已知限制

- 当前是低流量试运行，空闲论坛实测约 95 MiB，不代表峰值或并发容量保证。
- 未做真实邮件、公众注册、真实用户上传、高并发或长稳验收；管理员登录／管理页只用本地临时夹具验证。
- 论坛默认表情可能按需访问其配置的第三方 CDN；初次页面加载实测没有第三方请求，不等于所有交互都完全离线。
- 新插件、扩容、邮件及公开注册应单独评审，不自动延伸本次授权。
