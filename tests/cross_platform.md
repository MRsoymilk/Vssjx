# Windows / Linux 测试边界

通用客户端、服务端及集成测试入口支持 Windows 和 Linux。两端均需准备对应平台的 Godot 4.7、Rust/Cargo、Python 3.10+，Python 素材测试需要 Pillow 和 NumPy；数据库集成使用 Docker 和本地已有的 `postgres:17-bookworm` 镜像。

## 通用入口

在仓库根目录执行；Linux 将 `python` 换为 `python3`，`godot` 可替换为引擎可执行文件路径：

```sh
python -m unittest discover -s tests -p 'test_*.py'
cargo test --locked --manifest-path server/Cargo.toml
godot --headless --path client --editor --import --quit
godot --headless --path client res://tests/test_runner.tscn
python tests/run_server_connection.py
python tests/run_account_auth.py
python tests/run_characters.py
python tests/run_shared_world.py --output /absolute/path/to/test-output
```

集成脚本通过 `GODOT_BIN` 选择引擎。Windows 终端建议设置 `PYTHONUTF8=1`，避免其他集成脚本通过系统旧编码解码中文日志；`run_server_connection.py` 已显式使用 UTF-8。Docker CLI 必须在当前进程的 PATH 中。

## 平台专用部分

- `run_capacity.py` 的真实容量采样依赖 Linux `/proc`、资源限制与 CPU 亲和性，仅在 Linux 执行；Windows 会明确拒绝运行，不会生成伪造采样。
- `test_capacity_tools.py` 的 `/proc` 读取案例仅在 Linux 执行；汇总、判定等通用案例在两端运行。
- `run_offscreen.py` 依赖 Linux Xvfb。Windows 实际渲染直接运行 Godot 测试场景，按 `testing.md` 设置截图输出目录。
- 代理、Rust 镜像与数据库配置按本机环境准备；`.env`、`.cargo/config.toml` 和本地代理文件被 Git 忽略，不从其他机器复制秘密配置。

## 2026-10-15 验证范围

- Windows：Python 31 项，30 通过、1 项 Linux 采样检查跳过；Rust 34 项、格式与 Clippy 通过。服务发现、账号、角色和双客户端共享世界真实联调通过，详细记录见 `build_run_windows.md`。
- Linux：使用本机 Ubuntu / WSL2 的原生 Python 3.14.4，真实执行子进程管道案例 2 项及容量工具案例 7 项，全部通过；其中包含 Windows 跳过的 `/proc` 读取案例。
- 当前 WSL 尚未安装原生 Godot/Rust、Pillow/NumPy，因此本轮没有重跑 Linux 完整客户端、服务端及数据库集成，不把历史 Linux 记录视为本次改动的完整复测。准备上述依赖后可使用相同入口执行。
- 本轮未重新执行千人容量或公网长稳测试。
