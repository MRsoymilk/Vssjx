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
| `SSJX_CHAT_*` | 公共聊天有限历史、去重窗口、有界队列与个人/全局额度 |

客户端不会读取或打包服务端`.env`，避免泄露数据库密码；客户端服务器地址仍由用户输入并保存到独立的`user://connection.cfg`。

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

共享地图还需代理支持WebSocket升级，并保留相同路径前缀；客户端将HTTPS地址转换为WSS。Rust本体不终止TLS；仅原生客户端接入，本阶段拒绝浏览器Origin。

客户端发送密码或令牌要求HTTPS，仅`localhost`、`127.*`、`[::1]`允许本机HTTP。局域网HTTP地址仍可用于连接检查，账号操作需要HTTPS；Rust本身当前不终止TLS，公网部署必须由受控反向代理提供TLS且限制后端直连。应用不信任任意`X-Forwarded-For`来放宽限流。
