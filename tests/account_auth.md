# 账号认证验证

当前覆盖账号注册、登录、刷新、注销、PostgreSQL持久化及Godot界面，不代表角色、WSS、多人大地图或1000人容量已经完成。功能契约见[design/auth.md](../design/auth.md)。

## 环境与隔离

- 命令从`Vssjx/`仓库根目录执行，需要Rust、Godot、Python及可用Docker。
- 实际数据库验证使用本机已有`postgres:17-bookworm`镜像；没有镜像时先自行拉取，脚本不会静默下载或跳过。
- `pg_fixture.py`创建随机名称、随机密码、随机回环端口和tmpfs数据目录的专属容器；退出时只清理自己成功创建的容器，不读取开发者的`SSJX_DATABASE_URL`。
- Godot使用独立连接设置文件；不写玩家存档、不保存账号或密码。测试生成的令牌仅用于临时数据库，不打印到日志。
- 测试进程以`SSJX_ENV_FILE=''`禁用真实私有配置，并覆盖访问/刷新期限为120/600秒，验证服务端从配置读取期限；不会改写私有`.env`。

## Rust与静态回归

```sh
cargo test --locked --manifest-path server/Cargo.toml
cargo fmt --check --manifest-path server/Cargo.toml
cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings
python -m unittest discover -s tests -p 'test_*.py'
```

Rust纯规则与接口案例在`server/tests/auth.rs`和`server/tests/service.rs`。它们不替代真实数据库事务验证。

## 真实数据库与客户端

```sh
godot --headless --path client --import
python tests/run_account_auth.py
```

脚本会构建Rust服务，迁移空PostgreSQL，并验证：

- 用户名规范化、弱密码、畸形/超限JSON及未知字段拒绝。
- 并发抢同一账号仅一个成功；密码保存为Argon2id，错误密码和不存在账号均401。
- 数据库仅保存令牌SHA-256摘要；身份只能由有效会话读取。
- 同一旧刷新令牌并发轮换仅一次成功，旧访问/刷新令牌失效，刷新不延长7天总期限。
- Rust重启后账号及已提交会话仍可使用；退出可重复执行，撤销后不能读取或刷新。
- 刷新与注销竞争仍能撤销会话，不因令牌先轮换而假报注销成功。
- 访问过期可刷新；账号禁用后身份、登录、刷新拒绝。
- 数据库暂停时进程健康仍200、就绪503；账号请求触发限流保护。
- Godot拒绝发送公网HTTP密码、注册后转登录、错误密码、成功身份、刷新、面板关闭后会话保留、内存到期后重新登录、退出及离线资产隔离。

旧的地址和服务发现回归仍使用`python tests/run_server_connection.py`，该脚本主动移除数据库环境变量，以连接检查模式运行，不触碰账号库。

## 真实渲染离屏

```sh
mkdir -p /tmp/opencode/vssjx-auth-ui
SSJX_AUTH_CAPTURE_PATH=/tmp/opencode/vssjx-auth-ui LIBGL_ALWAYS_SOFTWARE=1 \
  python tests/run_account_auth.py --render
```

需要Xvfb及OpenGL/Mesa，支持`XVFB_BIN`和`GODOT_BIN`覆盖。输出注册页、已认证状态、退出状态三张截图，界面密码为隐藏显示，成功后输入框清空。

## 结果记录

环境为Linux、Rust/Cargo 1.97.1、Godot 4.7.2；离屏使用Xvfb与Mesa llvmpipe/OpenGL ES 3.2。具体检查数以实际输出为准，真实数据库案例不得用mock替代。

| 检查 | 本轮结果 |
|---|---|
| Rust纯规则与接口 | 7项通过 |
| 格式与Clippy | 通过，Clippy拒绝警告 |
| 真实PostgreSQL/API场景 | 通过，包含并发注册、轮换/注销竞争、禁用、重启和数据库暂停 |
| 账号界面与离屏 | 21项检查、0失败，输出3张截图 |
| 旧地址/发现联调 | 56项检查、0失败，跨进程保存/读取各1项通过 |
| 现有完整玩法 | 379项检查、0失败 |
| 六角色运动 | 6018项检查、0失败 |
| Python素材与目录 | 12项通过 |
| 开发Compose配置 | 校验通过，未启动持久化开发库 |

临时数据库容器与服务进程已清理，未修改个人数据库。验证产物位于`/tmp/opencode/vssjx-auth-ui/`等独立目录，不写入客户端素材或README。

公网TLS、代理公平性、账号恢复与管理、线上角色、游戏会话接管和容量压测不在本阶段通过范围。当前限流和资源上限是开发阶段技术起点，不是已证实的1000人服务指标。
