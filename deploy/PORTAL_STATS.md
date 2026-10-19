# 私有门户统计与 APK 管理

[部署导航](README.md) · [功能与安全设计](../design/portal-management.md) · [本地运行](../portal_stats/README.md) · [验证说明](../tests/portal_stats.md)

**当前只实现和本地验证，不部署、不推送。** 本指南供后续明确授权时使用；下面的采集或挂载示例不表示已经在公网执行。

## 1. 本地管理后台

Linux、Python 3.10+，无需额外 Python 包（门户图标准备工具另需 Pillow）。从仓库根目录执行：

```sh
python -m portal_stats init --database work/portal-admin/stats.sqlite3
python -m portal_stats serve --database work/portal-admin/stats.sqlite3 --apk-directory work/portal-admin/apks
```

打开 `http://127.0.0.1:9088/`。不自动采集任何远程数据，不调用游戏接口。省略 `--apk-directory` 可以只读查看统计；默认没有公开发布目录，上传不影响现有下载。

本地试验发布功能时，可额外指定：

```sh
python -m portal_stats serve --database work/portal-admin/stats.sqlite3 --apk-directory work/portal-admin/apks --apk-public-directory work/portal-apk-public
```

这只在本机管理独立目录，不自动设置 Nginx、安装服务或更新公网。点击“设为当前”前核对文件与 SHA256；点击删除需确认，当前版不可删除。

## 2. 采集与数据口径

未来启用新的 Nginx 配置后，白名单事件写入当前容器 stdout。使用有权读取 Docker 日志的**宿主采集进程**：

```sh
python -m portal_stats collect --database /受限目录/stats.sqlite3 --container vssjx-nginx-1
```

此命令跟随指定容器日志并重连，不启动或重建容器。部署前应核对 Docker 日志驱动支持读取和日志容量；当前 Compose 的日志轮转是 10 MiB × 3。丢失的历史日志无法恢复，采集应由运维配置独立进程托管。

也可以从脱敏事件流离线导入：

```sh
python -m portal_stats collect --stdin --database work/portal-admin/stats.sqlite3 < 已核对的事件文件
```

不通过 HTTP 上传日志。事件超过 4 KiB、字段不合法、非白名单或超出有效日期时不会计入。日汇总按 UTC+8；请求去重保留 30 天，汇总保留，旧日期退休后不会因重放重新计数。CSV 最多导出 366 天。

门户 PV、入口点击、游戏页面访问与下载请求是不同指标，不能相加当作独立访客。APK 多段 206 会产生多次请求，取消下载仍可能已发送部分正文；不提供“成功安装人数”或可证明的设备保存量。

## 3. 后台访问与权限

服务拒绝非回环绑定，只有读 API、CSV 和显式 APK 写操作，没有公网统计或事件入口。远程启用后通过 SSH 隧道访问，例如：

```sh
ssh -N -L 9088:127.0.0.1:9088 ssjx@47.93.114.190
```

本机访问 `http://127.0.0.1:9088/`。保持本地转发端口与管理端口一致，后台会严格校验 Host／Origin。不要将 `/api/summary`、后台根目录或 9088 接入公网反向代理，不因来源校验存在就认为同机用户被隔离。

管理写入要求浏览器同源 Origin、合法 Host 和页面内存中的随机进程令牌，重启后需刷新。令牌不是 URL 参数，不存浏览器本地存储。不要在公网 TLS 代理后伪造来源来绕过校验。

生产部署应分离采集与管理的系统权限：采集端可读容器日志，管理端只需读取汇总库并写独立 APK 目录，**不给管理进程 Docker socket、Docker 组或游戏数据库凭据**。共享统计文件的目录／ACL 和 WAL 读取权限需由运维明确配置；本工具不会修改系统账户或放宽已有目录权限。

## 4. APK 目录与发布

```text
私有目录/                    不挂载到 Nginx
├── registry.sqlite3
├── .manager.lock
└── packages/<随机ID>.apk

公开副本目录/                未来仅此目录只读挂载
├── current -> releases/<ID>
└── releases/<ID>/downloads/
    ├── vssjx-arm64.apk
    └── SHA256SUMS.txt
```

私有目录与公开目录不可互相包含。私有上传默认限制 1 GiB，单文件 256 MiB；发布副本和临时文件额外占用磁盘，至少按私有额度的两倍再加临时空间预留。

只管理通过后台上传登记的版本，不自动扫描、接管或删除网页导出目录中的旧 APK。需要纳入现有版本时，应明确导入其文件并核对摘要；不是让后台覆盖未知原文件。

APK 校验仅确认有限的 ZIP／AndroidManifest 结构，不检查应用 ID、版本号、签名或设备安装安全。上传前由发布者使用可信工具核验包名、版本、签名和权限；服务端不会执行任意上传工具或包内内容。

“设为当前”创建已校验的公开副本和校验文件，原子切换 `current`，不依赖重启服务。删除仅针对非当前的已登记文件；操作中断时显示未完成状态，可重试。不要手工改写后台管理的发布副本、链接或登记库。

## 5. 未来 Nginx 接入（当前不执行）

已有公网配置支持 `/go/webgame`、`/go/android` 固定跳转和白名单事件；门户新链接与配置需配套启用，不能只上传新 HTML 而遗漏路由。

如明确授权托管 APK，将 `SSJX_APK_PUBLIC_ROOT=/明确选择的公开副本目录` 放入独立、已被 Git 忽略的 `deploy/portal-apks.local.env`，不要加入游戏读取的根 `.env`。按需叠加 `deploy/public.apks.compose.yaml`。日常 Compose 及续期脚本仅在该独立文件存在时附加第二份插值配置与覆盖；该文件应只包含 APK 发布路径，不能覆盖游戏参数。

该覆盖只增加 Nginx 对公开副本目录的只读挂载。独立参数文件不进入游戏的 `env_file`，不会间接改变游戏／PostgreSQL 的容器配置或数据卷身份。

**新增 bind mount 可能需要重建 Nginx 容器，会使网页连接重连；它不是单纯 reload。** 应另行安排切换与备份，不能自动沿用以前的发布授权。

canonical 下载路径不变：`/downloads/vssjx-arm64.apk`。已挂载且存在当前副本时提供新版本，否则继续原 APK。管理版 APK 与校验文件禁用 ETag／时间条件复用并使用 no-store，避免连续切换同大小包时读到旧缓存；私有包和登记库永远不挂载。

## 6. 备份、回退与限制

统计数据和 APK 登记库使用独立 SQLite，不是游戏 PostgreSQL。备份时使用 SQLite 一致性备份或停止对应写进程后完整保存相关数据库；不能只复制活跃 WAL 模式的主 DB 文件。APK 备份还应包含私有包、公开副本与当前链接。

先发布其他已确认版本才能删除当前版。发布异常或文件摘要不符时停止操作，保留旧当前指针和未知文件，核对磁盘与备份；不以删库、清理玩家数据或修改历史迁移解决问题。

停用统计可以停止独立采集／后台并关闭定向日志，不需要改游戏逻辑。停用托管 APK 时应先确认回落到哪个包，再调整挂载或链接；不要让删除当前版成为常规回退方式。
