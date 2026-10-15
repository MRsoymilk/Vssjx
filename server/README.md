# Vssjx 服务端

预留的Rust服务端目录，目前仅完成目录划分，尚未建立Cargo工程，也没有可启动的网络服务。

- `src/`：后续Rust服务端源码。
- `migrations/`：后续PostgreSQL数据库迁移。
- 技术方案：Rust、Tokio、Axum、Serde、SQLx与PostgreSQL。
- 架构与实施阶段见[design/README.md](../design/README.md)。

账号、地图同步、公共聊天、个人任务与独立PVE将在后续阶段实现。不要将当前离线客户端视为已经接入服务器。
