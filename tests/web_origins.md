# P2a：WebSocket Origin安全前置

本单元只完成服务端浏览器来源准入，不启用Godot Web工厂、不增加Web导出，不改玩法、票据协议、原生凭据或PC admin。P2整体仍未通过。

## 配置与边界

- `SSJX_WEB_ALLOWED_ORIGINS`：逗号分隔的正式HTTPS来源，默认空。
- `SSJX_WEB_DEV_ORIGINS`：单独配置的本机HTTP(S)来源，只接受显式`localhost`、IPv4回环或`[::1]`，默认空；生产保持空。
- 每个设置最多32项、8192字节；单来源最多2048字节。无效配置拒绝启动，错误只指出设置名，不回显值。
- 按协议、主机和有效端口精确匹配。协议/DNS大小写、IPv6表示和默认端口规范化；不解析DNS，不跟随重定向，不把子域、尾点域名或不同端口合并。IDN使用ASCII/Punycode。
- 不接受路径、尾部斜杠、用户信息、查询、片段、通配符、IPv4缩写/八进制/十六进制别名。未知、空、`null`、异常多值及重复Origin头拒绝为`403 ORIGIN_NOT_ALLOWED`。
- 缺少Origin保留原生路径，但仍需认证。来源通过不改变票据单次/过期规则、角色归属、同会话接管/异会话占用、协议/配置校验、IP准入及帧大小限制。
- 校验在世界升级入口、账号服务/限流前进行；不可信Origin不进入认证及数据库路径。可信Origin和原生连接继续共用原有准入额度。
- 不信任Host或Forwarded类头扩大来源范围；代理必须保留真实Origin。Origin可被非浏览器伪造，绝不是身份凭据。
- 本设置不启用HTTP CORS，不修改本机监控/通知接口边界，也不开放PC admin。网页仍须使用受控同域HTTPS/WSS入口。

运行方式与配置示例见[server/README.md](../server/README.md#浏览器websocket来源)。两个设置只放服务端配置，不放玩家URL参数或客户端公开配置。

## 可复现验证

```sh
cargo test --locked --manifest-path server/Cargo.toml

PLAYWRIGHT_MODULE_PATH=/绝对路径/playwright-core \
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/绝对路径/chrome-headless-shell \
python3 tests/run_web_origins.py --browser \
  --output /tmp/opencode/vssjx-web-origins

python3 tests/run_shared_world.py \
  --output /tmp/opencode/vssjx-web-origins-shared-world
```

`run_web_origins.py`不读取私有`.env`，清除继承的`SSJX_*`服务设置，启动独立临时PostgreSQL和自身回环监听。默认使用已有Docker镜像`postgres:17-bookworm`；也可按`pg_fixture.py`显式配置测试专用便携PostgreSQL。不接触已有账号、数据库或存档。测试结束清理自身进程/容器；日志和报告只留在指定测试目录。

真实Chromium测试加载两个不同端口的本机空白测试页，验证允许页的浏览器原生WebSocket携带来源并完成票据交换、快照和离场，另一来源无法连接；票据仅通过子进程标准输入进入页面内存，不放URL、命令行、存储或结果文件。浏览器页只检查快照数量和自身角色；完整快照摘要/分片/二进制连续性由Python WebSocket夹具与既有共享世界回归覆盖。

### 本机结果（2026-10-16）

- Rust全量：52项通过，包含6项新增Origin策略测试。
- 真实PostgreSQL/Rust集成：65项检查通过；其中包含Chromium运行成功检查，浏览器内部另有6项检查通过。
- Chromium：`153.0.8010.12`，实际无头浏览器进程，不是Godot渲染测试。
- 集成覆盖：默认拒绝、合法来源、重复头/多值/异常字节/转发头伪造、无Origin原生连接、无效/重放/过期票据、错误协议/配置、角色归属、异会话占用、同会话接管、共图可见、帧上限、共用IP限流。
- 在`RUST_LOG=trace`下检查测试日志不包含测试密码、数据库URL、访问/刷新令牌、票据或异常Origin中的凭据标记。
- Python既有测试：82项通过。
- 既有共享世界回归独立复跑通过：聊天协议48项、增量协议50项、两个独立Godot headless客户端分别25/28项，以及票据、隔离、移动、聊天、所有权、撤权和位置持久化集成。没有执行渲染验收。
- 日志：`/tmp/opencode/vssjx-web-origins-rust.log`、`/tmp/opencode/vssjx-web-origins-integration.log`；报告：`/tmp/opencode/vssjx-web-origins/report.json`、`browser.json`。
- 共享世界首次与新集成并行运行时，在现有脚本`error(a, 'INVALID_TARGET')`的80包查找上限处失败；未修改该脚本或游戏规则，独立复跑通过。首次失败日志保留在`/tmp/opencode/vssjx-web-origins-shared-world.log`，通过记录为`/tmp/opencode/vssjx-web-origins-shared-world-retry.log`及同名目录。尚未确定首次失败原因，不将重跑成功当作消除了偶发失败。

未证明：Godot Web启动/离线或在线闭环、Web凭据隔离与受控配置、浏览器异步存储、单线程资源加载、公网TLS/WSS代理、Windows实际运行、iOS/Android真机浏览器兼容性及容量。下一单元应先完成Web凭据/配置边界，再开放浏览器登录。
