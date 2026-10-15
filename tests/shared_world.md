# 多人同图验收

运行：

```sh
python tests/run_shared_world.py --render
cargo test --locked --manifest-path server/Cargo.toml
cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings
```

依赖Docker PostgreSQL、Godot、Xvfb与Pillow；`--render`使用真正的OpenGL离屏渲染，非headless截图。测试使用临时数据库和测试账号，禁用私有.env，结束清理容器。可通过`--output`设置截图/日志目录。

本机渲染环境：

```sh
XVFB_BIN=/tmp/opencode/vssjx-xvfb/usr/bin/Xvfb \
LD_LIBRARY_PATH=/tmp/opencode/vssjx-xvfb/usr/lib/x86_64-linux-gnu \
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_shared_world.py --render
```

## 2026-10-15 验证

- 两个独立Godot进程经真实登录→角色大厅→共享地图：Alice 16项、Bob 17项，零失败。
- 双向互见、目的格移动同步、断线移除/重连恢复、同会话代次增加、原位置恢复、无重复角色及离线存档哨兵保持不变。
- 协议/数据库：未认证和越权拒绝、地图摘要校验、单次票据与重新签发失效、票据过期、河流/树木阻挡、重复输入拒绝、第二登录会话拒绝、旧连接代次隔离、刷新不踢游戏连接、注销/封禁踢出、退出落库、服务重启恢复位置。
- 6张640×960实际渲染截图；地图区域移动前后像素不同。人工查看移动后截图，双方角色和同图人数可见。
- 截图及两进程日志：`/tmp/opencode/vssjx-shared-world/`。
- 账号UI回归18项、角色UI回归47项通过；两套PostgreSQL集成回归通过。
- Rust 17项测试通过；Clippy所有target以`-D warnings`通过。

不将此双人验证当作1000人容量或公网WSS验证。当前广播为完整地图快照，尚需热点/混合负载、慢客户端、网络故障与TLS代理验收。

地图重导出工具：`client/tests/export_online_map.tscn`，以`SSJX_MAP_EXPORT`指定输出路径；导出后同步到`shared/data/qingyun-v1.json`和`client/assets/data/qingyun-v1.json`，两份原始字节必须一致。

后续集成脚本已增加公共聊天验收；新增测试和当前结果见 [公共聊天测试](public_chat.md)。以上33项/6张截图是多人同图初始阶段的记录，不覆盖后续聊天测试数量。

世界同步现已升级v2：初始全量+有序共享增量，新增二进制布局/摘要/生命周期边界用例。完整快照、增量序列、生命周期和双客户端离屏回归随本阶段接入；以上原始阶段记录保留，千人负载另行验收。
