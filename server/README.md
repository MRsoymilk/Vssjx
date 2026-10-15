# Vssjx 服务端

已建立Rust/Tokio/Axum服务，目前开放服务器发现和连接检查。账号、角色、数据库、WSS、共享地图与公共聊天尚未实现。

- `src/`：启动入口、环境配置与HTTP服务。
- `migrations/`：后续PostgreSQL数据库迁移。
- 当前使用Rust、Tokio、Axum、Serde和tracing；后续持久化采用SQLx与PostgreSQL。
- 架构与实施阶段见[design/README.md](../design/README.md)。

## 启动

在仓库根目录运行：

```sh
cargo run --locked --manifest-path server/Cargo.toml
```

默认仅监听`127.0.0.1:8080`。客户端选择“登录游戏”，填写`127.0.0.1:8080`并“保存并连接”。当前成功结果仅代表服务可访问，不代表账号认证或进入多人世界。

局域网开放监听：

```sh
SSJX_BIND_ADDR=0.0.0.0:8080 SSJX_SERVER_NAME='蜀山剑侠服务器' \
  cargo run --locked --manifest-path server/Cargo.toml
```

`SSJX_BIND_ADDR`支持IP和端口（IPv6用`[::1]:8080`），`SSJX_SERVER_NAME`设置显示名称，`RUST_LOG`控制日志级别。地址占用或配置错误时启动失败，不静默换端口；Ctrl+C或SIGTERM触发优雅关闭。

## 当前接口

| 路由 | 用途 |
|---|---|
| `GET /healthz` | 进程健康，返回`stage=connection_only` |
| `GET /readyz` | 当前连接检查阶段就绪，不表示数据库或游戏业务就绪 |
| `GET /api/v1/server-info` | 服务标识、协议版本、名称、版本、阶段和能力列表 |

当前能力列表为空，不发布虚假的账号或游戏接口。

## 域名与路径前缀

公网使用带有效证书的HTTPS反向代理，Rust服务放在受控内网。客户端支持`https://game.example.com`和`https://game.example.com/ssjx`；使用前缀时代理应将`/ssjx/api/v1/server-info`转发到后端`/api/v1/server-info`。

域名无需修改客户端或重新编译服务端；把客户端地址改为域名即可。客户端不关闭证书校验，也不自动跟随重定向。完整地址与保存规则见[连接入口设计](../design/connection.md)。
