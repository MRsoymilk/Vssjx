# 角色删除验证（2026-10-21）

入口为选角页“菜单 → 删除角色 → 确定删除”，同时支持本地与联机。确认框显示选中角色昵称、等级；取消和 Esc 不删除，确认期间不能切换角色或进入游戏。

运行：

```powershell
godot --headless --path client res://tests/character_deletion_test.tscn
$env:SSJX_TEST_SERVER_BIN='<从当前源码构建的服务端>'
$env:GODOT_BIN='<Godot 控制台程序>'
python -X utf8 tests/run_character_deletion.py
```

服务测试只启动随机命名、临时 PostgreSQL，禁用私有 `.env`；本地测试仅使用进程专用存档路径。联机界面验证另建测试账号及带哨兵内容的离线文件，不访问玩家存档。

已验证：

- 本地与传输回执 18 项，无头通过；实际 OpenGL 渲染 19 项通过，确认框布局与文字已目视检查。
- 真实联机选角界面 17 项通过：取消不提交、删除锁定、首次成功响应丢失后复用原请求重试、刷新后仅移除目标、删除最后一个角色后可创建、离线存档隔离。
- Rust/PostgreSQL 与 HTTP/WebSocket 42 项通过：认证/归属/昵称匹配/严格请求体，在线、战斗、公会、队伍拦截，并发重复请求只删除一次且只写一条成功审计，历史战斗保留，旧创建回执不能复活角色，同名新建使用新 UUID，旧删除重试不能影响同名新角色，五个槽位释放及重启后保持空列表。
- 原有选角组件 12 项、本地五角色 27 项、角色 Rust 契约 2 项通过。
- 原有线上创建界面 99 项断言通过，但 `run_characters.py` 严格日志门槛仍因退出时的 4 个 ObjectDB 与 1 个资源未释放报告失败；同类退出告警也出现在原有本地五角色及部分删除用例运行中，相关断言和进程退出码均正常。
- `cargo test --locked --manifest-path server/Cargo.toml --target-dir work/npc-map-cargo --tests` 全部通过。

联机功能依赖当前源码服务端及 `0031_character_deletion.sql`，启动服务时沿用自动迁移。此次未发布或重启现有服务。
