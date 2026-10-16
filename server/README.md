# Vssjx 服务端

Rust/Tokio/Axum服务已支持服务器发现、PostgreSQL账号认证、角色创建/查询/幂等回执、单次连接票据、共享地图权威移动与公共聊天。线上任务/PVE尚未接入，当前仅支持一个世界服务进程，不能将多进程直连同库作为世界集群运行。

- `src/`：启动入口、环境配置与HTTP服务。
- `migrations/`：SQLx启动时执行的PostgreSQL版本化迁移。
- 当前使用Rust、Tokio、Axum、Serde、tracing、Argon2id、SQLx与PostgreSQL。
- 架构与实施阶段见[design/README.md](../design/README.md)。

## 启动

在仓库根目录运行：

```sh
cargo run --locked --manifest-path server/Cargo.toml
```

默认仅监听`127.0.0.1:8080`。没有`SSJX_DATABASE_URL`时只开放连接检查，账号接口明确返回不可用；配置数据库后才启用账号服务。账号登录成功也不代表已经进入多人世界。

## 配置文件

部署参数统一放在仓库根目录`.env`，样例为[.env.sample.txt](../.env.sample.txt)。首次使用可复制样例；已有`.env`不要覆盖。`.env`及`.env.*`不提交Git，只有`.env.sample.txt`纳入版本管理，样例不包含真实密码。

Rust自动读取当前工作目录的`.env`；当前目录没有时，开发构建会读取仓库根目录`.env`，因此也可以在`server/`中运行Cargo。已打包的二进制建议从部署目录启动或使用`SSJX_ENV_FILE=/绝对路径/.env`明确指定文件。

优先级：**进程环境变量 > `.env` > 内置安全默认值**。`.env`支持引号、注释和`${变量名}`引用；解析不会修改进程环境。`SSJX_ENV_FILE`设为空字符串可完全禁用文件读取。显式指定文件不存在、语法错误、无效数值或越界配置时启动失败，错误信息不回显敏感配置行。

修改配置后重启Rust服务；数据库容器参数变更需重新创建对应Compose服务，但不要删除已有数据卷或随意更换已有库密码。已签发会话仍保留原刷新截止时间，不因修改配置而自动延期。

| 参数组 | 用途 |
|---|---|
| `SSJX_BIND_ADDR`、`SSJX_SERVER_NAME`、`RUST_LOG` | 服务监听、显示名称和日志 |
| `SSJX_POSTGRES_*` | 开发PostgreSQL镜像、绑定、账号、库名、密码与端口 |
| `SSJX_DATABASE_URL` | 实际连接地址；为空时仅连接检查，不启用账号 |
| `SSJX_AUTH_ACCESS_SECONDS`、`SSJX_AUTH_REFRESH_SECONDS` | 会话期限；访问60～86400秒，刷新300～2592000秒且不能短于访问期限 |
| `SSJX_AUTH_MAX_SESSIONS`、`SSJX_AUTH_HASH_WORKERS` | 认证会话与并行密码任务上限 |
| `SSJX_AUTH_RATE_*` | 限流窗口、全局/IP/账号额度及键数量上限 |
| `SSJX_DB_*` | 数据库连接池、查询、等待、空闲事务及就绪检查超时 |
| `SSJX_WORLD_*` | 世界准入人数、位置保存间隔及重连所有权窗口；人数上限不是容量实测结论 |
| `SSJX_WEB_ALLOWED_ORIGINS`、`SSJX_WEB_DEV_ORIGINS` | 浏览器WebSocket精确来源白名单；默认均为空，开发项仅允许显式回环来源 |
| `SSJX_CHAT_*` | 公共聊天有限历史、去重窗口、有界队列与个人/全局额度 |
| `SSJX_MONITOR_BIND_ADDR` | 独立本机监控/通知监听，默认`127.0.0.1:9090`；只能用回环IP，空值关闭 |
| `SSJX_LOG_DIR` | JSON日志目录，相对服务启动工作目录；默认`logs`，空值只保留控制台日志 |
| `SSJX_LOG_FILE_MIB`、`SSJX_LOG_FILES` | 单文件1～1024MiB、总文件数1～100（包含当前文件）；默认10MiB×7，按大小轮转 |

客户端不会读取或打包服务端`.env`，避免泄露数据库密码；客户端服务器地址仍由用户输入并保存到独立的`user://connection.cfg`。

## 日志、Web 监控与全局通知

正常启动后，在服务所在机器打开 **http://127.0.0.1:9090/**。这是独立的本机监听，不挂到游戏HTTP端口，也不提供账号管理、禁言或资产修改接口。静态页面无需额外Node服务或外部CDN；`GET /api/status`提供同一份JSON快照。

页面的“全局通知”可发布1～240字消息，并设置1～1440分钟有效期，默认10分钟。发布后向所有支持通知的在线角色推送，在游戏顶部用金色横条从右向左循环滚动；有效期内新上线/重连也能看到。发布新通知会替换当前通知，可点击“撤下通知”提前停止，到期自动停止。通知不打断移动、聊天或菜单操作。local单人模式不连接服务端，不接收全服通知。

通知只保存在当前服务进程，重启后清空。发布/撤下接口仅位于本机监听的`/api/announcements`，要求同源请求和页面读取的操作令牌；统计接口保持只读。客户端与服务端均需更新，服务端更新后重启生效。协议及验证见[全局通知](../tests/announcements.md)。

远程排查使用SSH隧道，不要把监控端口加入公网反向代理：

```sh
ssh -N -L 9090:127.0.0.1:9090 user@server
```

随后在本机打开上述地址。监控没有账号密码：安全边界是回环监听、实际TCP对端、Host校验及拒绝跨站请求，而不是任意代理头。非回环监控地址会被拒绝启动；本机其他用户仍可读取统计，应在可信主机使用。端口占用会明确启动失败，不静默换端口；需要多份开发服务时配置不同端口或空值关闭。

页面每5秒刷新，显示在线/移动/保留角色数量、WebSocket连接及下行应用字节、世界tick间隔/工作耗时、聊天队列长度、HTTP路由耗时/错误、进程RSS、数据库健康/连接池、日志丢弃/写盘失败和最近100条异常。数据库独立每5秒探测一次，页面不等待数据库查询；数据库失败、采样过期或世界tick停滞会提示关注。内存趋势只保留在当前页面，计数重启清零并更换`boot_id`，不是历史监控平台。

控制台仍输出可读日志，文件为`logs/server.jsonl`及`server.jsonl.1`等（`.1`较新）。两种输出各有4096条有界非阻塞队列，避免慢磁盘/控制台阻塞游戏；队列满时丢弃日志并在监控计数，写盘故障另计数。默认文件总预算约70MiB，普通新建文件在Unix下权限为`0600`；目录应只给服务用户写入，每个进程使用独立日志目录。修改更小的保留数量并重启时会清理本日志器的超限编号文件；无关文件不处理。由systemd/Docker接管的控制台日志还需由部署层单独配置留存上限。

HTTP响应带服务端生成的`X-Request-Id`，调用方传入的同名值不会被采信。WebSocket另有`connection_id`，与升级请求ID同时记录在连接span中；最近异常中的关联ID可直接用于搜索：

```sh
rg --fixed-strings '复制的请求或连接UUID' logs/server.jsonl*
tail -n 100 logs/server.jsonl
```

默认`RUST_LOG=info`：普通业务请求记录结果/耗时，探活和发现成功降到debug，4xx/协议拒绝为warn、5xx/数据库失败为error；连接打开、认证、关闭及健康变化有独立事件。临时排查可用`RUST_LOG=debug`后重启，结束后恢复info。日志仅允许本应用target；即使trace也不输出第三方SQL/HTTP调试信息。数据库错误只记录固定操作分类、错误种类与SQLSTATE，不记录SQL、参数或原始错误详情。

日志/监控不保留密码、令牌、票据、请求/响应正文、聊天内容、账号名、昵称、原始URL参数或完整请求头；路由使用模板，未知路径统一`unmatched`，避免敏感数据与高基数标签。Web页面不提供任意文件读取或完整日志下载。技术性容量轮转不等于已确定的审计保留政策，正式告警、历史指标、备份与D08运营权限仍需另行确定。故障排查与回归记录见[tests/observability.md](../tests/observability.md)。

## 启用账号数据库

开发环境可使用仓库中的PostgreSQL Compose配置。先编辑私有`.env`：填写强随机`SSJX_POSTGRES_PASSWORD`，将空的`SSJX_DATABASE_URL=`替换为样例中带`${...}`的URL，或直接填写已有数据库的完整URL。然后在仓库根目录执行：

```sh
docker compose --env-file .env -f deploy/compose.yaml up -d
cargo run --locked --manifest-path server/Cargo.toml
```

首次创建数据库时安全保管密码；已有数据库再次启动时使用原密码，不要重新随机生成。Compose数据使用持久化卷，默认仅绑定本机；可在`.env`中设置镜像、库名、用户、绑定和端口。自定义密码含URL特殊字符时需进行百分号编码，可选择随机十六进制密码避免编码歧义。使用外部数据库时不必启动Compose。

配置了数据库但连接或迁移失败时，服务启动失败，不退回伪登录或内存账号。不要把数据库URL和密码提交到仓库、截图或普通日志。

## 客户端账号

封面“注册账号”或“登录游戏”进入同一账号面板，服务器地址会自动回填。注册后重新输入密码登录；退出账号会撤销服务端会话。关闭面板不清除内存会话，重启客户端则重新输入密码。服务器地址是唯一写入本地偏好文件的字段。

登录账号使用3～32位英文字母、数字或下划线，首尾空白清理后按小写比较。密码为12～128个Unicode字符、最多512个UTF-8字节，不能全为空白，不裁剪密码。账号名不是角色昵称；登录后可在“线上角色”创建或查看服务器角色，具体昵称与回执契约见[design/characters.md](../design/characters.md)。

密码使用带随机盐的Argon2id保存。默认访问令牌15分钟、刷新总期限7天，可通过`.env`在有效范围内调整，刷新不延长已签发会话的总期限；刷新同时轮换两种令牌，数据库仅存令牌摘要。账号禁用、注销或令牌过期后，身份查询和刷新被拒绝。

局域网开放监听时，在`.env`中设置：

```sh
SSJX_BIND_ADDR=0.0.0.0:8080
SSJX_SERVER_NAME="蜀山剑侠服务器"
```

`SSJX_BIND_ADDR`支持IP和端口（IPv6用`[::1]:8080`），`SSJX_SERVER_NAME`设置显示名称，`RUST_LOG`控制日志级别。地址占用或配置错误时启动失败，不静默换端口；Ctrl+C或SIGTERM触发优雅关闭。

## 当前接口

| 路由 | 用途 |
|---|---|
| `GET /healthz` | 进程健康，返回当前阶段 |
| `GET /readyz` | 账号启用时检查真实数据库，故障返回503；无数据库时仅表示连接检查就绪 |
| `GET /api/v1/server-info` | 服务标识、协议版本、名称、版本、阶段和能力列表 |
| `POST /api/v1/auth/register` | 创建账号，返回公开身份，不自动登录 |
| `POST /api/v1/auth/login` | 验证密码，签发账号会话 |
| `POST /api/v1/auth/refresh` | 单次轮换刷新令牌与访问令牌 |
| `GET /api/v1/auth/me` | Bearer令牌查询本人账号 |
| `POST /api/v1/auth/logout` | 撤销该Bearer会话，重复注销可安全重试 |
| `GET /api/v1/characters` | 当前账号的角色基本行，至多一个，不读取离线存档 |
| `POST /api/v1/characters` | 账号级幂等创建，昵称全服唯一，初始资产同事务提交 |
| `GET /api/v1/character-operations/{operation_id}` | 读取当前账号的原创建回执，成功与明确拒绝均持久化 |
| `POST /api/v1/world/ticket` | 账号角色归属校验后签发短时单次票据 |
| `GET /api/v1/world/ws` | WebSocket升级后交换票据、进入世界、移动与公共聊天 |

未配置数据库时`stage=connection_only`且能力列表为空；配置后为`stage=account_auth`、`capabilities=["account_auth","character_creation","shared_world","public_chat"]`。详细契约见[账号](../design/auth.md)、[角色](../design/characters.md)、[共享地图](../design/shared_world.md)与[聊天](../design/chat.md)。公开能力不代表1000人容量或公网TLS代理已经验收。

## 域名与路径前缀

公网使用带有效证书的HTTPS反向代理，Rust服务放在受控内网。客户端支持`https://game.example.com`和`https://game.example.com/ssjx`；使用前缀时代理应将`/ssjx/api/v1/server-info`转发到后端`/api/v1/server-info`。

域名无需修改客户端或重新编译服务端；把客户端地址改为域名即可。客户端不关闭证书校验，也不自动跟随重定向。完整地址与保存规则见[连接入口设计](../design/connection.md)。

共享地图还需代理支持WebSocket升级，并保留相同路径前缀；客户端将HTTPS地址转换为WSS。Rust本体不终止TLS。浏览器Web客户端尚未完成；服务端已提供下述Origin安全前置，不代表已交付Web游戏。

### 浏览器WebSocket来源

默认拒绝所有携带`Origin`的世界连接。未来部署网页时，在服务端私有配置中明确填写网页来源，例如：

```dotenv
SSJX_WEB_ALLOWED_ORIGINS=https://game.example.com,https://game.example.com:8443
SSJX_WEB_DEV_ORIGINS=
```

只填写协议、主机和可选端口，不能带路径（即使网页位于`/ssjx`）、尾部`/`、查询、片段、用户信息或通配符。按协议、规范化主机和有效端口精确匹配；DNS大小写、IPv6等价表示及省略的默认端口归一化，但子域、尾点域名和不同端口不自动获准。国际化域名使用浏览器序列化后的ASCII/Punycode形式。

正式项只接受HTTPS；本地测试另用`SSJX_WEB_DEV_ORIGINS=http://127.0.0.1:8060`，仅允许显式`localhost`、`127.*`或`[::1]`回环来源，生产保持为空。每项最多32个逗号分隔来源、总长8192字节、单来源2048字节；配置无效时拒绝启动且不回显原始值。

未知、`null`、空值、异常多值或重复Origin头均返回`403 ORIGIN_NOT_ALLOWED`；不根据Host、Forwarded类代理头或客户端URL参数扩大白名单。代理必须保留真实Origin，不删除、合并或替换成受信值。无Origin的原生连接仍须票据认证；来源匹配也不能跳过版本、角色归属、占用、限流或消息大小约束。

这里只配置游戏世界WebSocket，不启用HTTP跨域CORS，也不开放本机监控/通知或PC admin场景。公开网页仍需受控同域HTTPS/WSS入口，不能把Origin当身份凭据。验证范围见[tests/web_origins.md](../tests/web_origins.md)。

客户端发送密码或令牌要求HTTPS，仅`localhost`、`127.*`、`[::1]`允许本机HTTP。局域网HTTP地址仍可用于连接检查，账号操作需要HTTPS；Rust本身当前不终止TLS，公网部署必须由受控反向代理提供TLS且限制后端直连。应用不信任任意`X-Forwarded-For`来放宽限流。
