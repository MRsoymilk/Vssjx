# Rust服务与服务器地址入口验证

本阶段只包含服务发现、客户端地址持久化和连接检查，不含账号、数据库、WSS或多人玩法。所有命令在`Vssjx/`根目录执行；使用隔离设置文件，不覆盖个人连接偏好或角色存档。

## Rust服务

```sh
cargo test --locked --manifest-path server/Cargo.toml
cargo fmt --check --manifest-path server/Cargo.toml
cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings
```

用例位于`server/tests/service.rs`：健康/就绪阶段、服务信息契约、不伪造登录成功、监听与显示名称配置。依赖已缓存时可添加`--offline`运行。

## Godot地址与界面

首次导入新增脚本与全局类：

```sh
godot --headless --path client --import
godot --headless --path client res://tests/server_connection_test.tscn
```

单独场景检查IP、域名、IPv6、前缀、非法输入、配置文件读写、页面返回与地址回填。没有设置本地集成服务地址时，不运行网络案例，不能将它视为完整服务联调。

## Rust/Godot真实联调与跨进程保存

```sh
python tests/run_server_connection.py
```

脚本构建并启动实际Rust服务，监听操作系统分配的本机端口；启动本地HTTP夹具提供代理前缀、错误服务、协议不兼容、损坏JSON、重定向、503、大响应体和超时案例。最后分别启动两个Godot进程，在同一隔离配置文件中写入域名并重新读取，验证不是依赖页面或进程内存。

测试服务器在脚本退出时关闭，不作为长期运行的开发服务。Linux集成脚本需要可用的Cargo、Godot与本机TCP端口；可用`GODOT_BIN`指定Godot路径。

## 真实渲染离屏

```sh
mkdir -p /tmp/opencode/vssjx-login
SSJX_LOGIN_CAPTURE_PATH=/tmp/opencode/vssjx-login LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_server_connection.py --render
```

需要Xvfb与OpenGL/Mesa，`XVFB_BIN`可指定Xvfb路径。输出`01_saved_server.png`、`02_connected_server.png`，验证地址输入、回填、连接结果与按钮布局。

测试隔离变量`SSJX_CONNECTION_PATH`仅覆盖连接设置路径，不影响`SSJX_SAVE_PATH`。跨进程写入/读取阶段由集成脚本管理，不应指向玩家真实配置。

## 本阶段运行记录

环境：Linux，Rust 1.97.1/Cargo 1.97.1，Godot 4.7.2；离屏使用Xvfb、Mesa llvmpipe/OpenGL ES 3.2。

| 检查 | 结果 |
|---|---|
| Rust服务案例 | 4项通过 |
| Rust格式与Clippy | 通过，Clippy拒绝警告 |
| Godot/Rust真实网络联调 | 56项检查，0失败 |
| 两个独立进程写入/恢复域名 | 每阶段1项检查，均通过 |
| 离屏界面及网络联调 | 58项检查，0失败，保存2张截图；随后跨进程写入/恢复通过 |
| 原有客户端完整流程 | 379项检查，0失败 |
| 六角色运动逻辑 | 6018项检查，0失败 |
| Python素材与目录回归 | 12项通过 |

本次未部署真实公网域名、未验证公网TLS证书，也没有1000人容量结论。域名规范化和本地代理前缀已验证，实际域名上线后仍需执行TLS与网络环境验证。
