# 昼夜与场景时钟

## 联机场景时钟

```sh
godot --headless --path client res://tests/world_clock_test.tscn
godot --headless --path client res://tests/world_delta_test.tscn
cargo test --locked --manifest-path server/Cargo.toml
python tests/run_shared_world.py --output /tmp/opencode/vssjx-day-night-world
```

- `world_clock_test`：握手先校时再发出地图变更，单调时钟推进，心跳重新校时，断连／切图不重置，退出清空；拒绝未认证、负数、小数、溢出等时间，兼容缺少字段的旧服务。
- `run_shared_world.py`：自建临时 PostgreSQL 和隔离 Rust 服务，验证真实握手／心跳时间，并继续验证两位 Godot 玩家、移动、聊天及重连；不访问生产数据库。
- 2026-10-23：Godot 4.7.2 场景时钟 20 项、原世界增量协议 50 项检查通过；Rust 全套测试零失败（原有数据库专项测试 1 项按原规则忽略）。
- 同日真实隔离联调通过握手／心跳时间校验、公共聊天 53 项及两位独立 Godot 玩家 25／28 项检查，并覆盖接管、注销、位置持久化及服务重启。
