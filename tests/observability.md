# 服务端日志与 Web 监控验证

## 执行

在仓库根目录：

```sh
cargo test --locked --manifest-path server/Cargo.toml
cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings
python tests/run_observability.py --output /tmp/opencode/vssjx-observability
python tests/run_env_config.py
python tests/run_shared_world.py --render --output /tmp/opencode/vssjx-monitor-shared-world
python tests/run_capacity.py --profile tests/capacity_smoke.json --output /tmp/opencode/vssjx-monitor-capacity-smoke
```

需要Docker及本机已有`postgres:17-bookworm`镜像。测试使用随机容器名、tmpfs数据库、随机密码、本机临时端口和指定的测试日志目录，不读取私有`.env`，不接触真实账号/存档。异常退出也清理测试容器；轮转日志、JSON结果与截图只保留在输出目录。

真实浏览器可选`--browser`，不使用逻辑模拟替代截图。安装`playwright-core`到仓库外，并指定已有Chromium或按Playwright指引安装浏览器，例如：

```sh
npm install --prefix /tmp/opencode/vssjx-browser --no-audit --no-fund playwright-core
PLAYWRIGHT_MODULE_PATH=/tmp/opencode/vssjx-browser/node_modules/playwright-core \
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/绝对路径/chrome-headless-shell \
python tests/run_observability.py --browser --output /tmp/opencode/vssjx-observability
```

Godot真实离屏渲染需要Xvfb和OpenGL；当前环境仍使用`tests/testing.md`所述的Xvfb/Mesa变量，不在桌面弹窗。

## 自动断言

### Rust

- 默认监听安全、非法地址/容量边界拒绝、错误不回显输入配置。
- 游戏端口不存在监控API；监控只接受真实回环TCP对端、回环Host、同源读取；拒绝伪Host、Origin、跨站/同站不同源请求、无对端信息和POST写入。
- IPv6回环正常；监控具有no-store、nosniff、禁止嵌入的CSP且不启用CORS。
- 错误计数、请求UUID、固定路由模板、HTTP直方图与最大值正确；120个不同未知URL只产生一个标签，最近事件最多100条。
- 请求头、body、查询参数、动态回执UUID与调用方注入ID不进入指标标签或异常内容。
- Socket RAII计数、世界tick工作量、超时tick与共享编码字节计数正确。
- JSON日志轮转大小/数量有界、新建文件Unix权限0600、减少留存数量会清理超限自有文件但保留无关文件；文件系统错误计数且移除故障后恢复；阻塞写入线程时调用线程不阻塞、有限队列丢弃计数可见。

### 真实进程、数据库及浏览器

- 注册/登录/角色/单次票据/两条世界连接、权威移动、公共聊天真实执行，监控人数、tick及发送字节随实际状态变化。
- 错误登录响应ID能在监控与控制台日志中定位；非法WebSocket握手计数且能关联连接。
- 4000次错误请求真实触发1MiB文件轮转；保留不超过3个文件，每个不超过1MiB，每行都能独立解析为JSON；优雅退出可见最后的`server stopped`。
- PostgreSQL暂停后后台探测转为unavailable，监控API仍在1秒内回应，readyz返回503；恢复数据库后重新转为ok/200。
- 服务重启更换boot_id、清空进程计数/内存异常，不把旧状态显示为当前状态。
- `RUST_LOG=trace`下仍不输出第三方target；已知密码、数据库URL、access/refresh token、票据、账号名、昵称、聊天正文、URL查询值和任意header值均不出现在控制台、文件或监控快照中。
- Chromium真实打开页面，验证在线人数、数据库状态、路由统计、5秒自动刷新、390px无整页横向溢出、错误字段按纯文本显示、不执行HTML；boot变化清空趋势，网络断开明确标识旧数据。

## 2026-10-15执行记录与产物

最终日志/监控真实集成130项、Chromium13项均零失败；Rust34项、Python29项及Clippy零警告通过。输出在`/tmp/opencode/vssjx-observability-final/`：

- `report.json`：集成断言、实际文件数/字节数、丢弃计数、源码与二进制SHA-256及当时git_head/dirty。
- `browser.json`：浏览器版本与页面断言。
- `dashboard-desktop.png`、`dashboard-mobile.png`、`dashboard-disconnected.png`：3张真实Chromium截图。
- `status.json`、`console-*.log`、`logs/server.jsonl*`：实际状态/运行日志，不提交包含运行标识的原始产物到仓库。

最终轮转实测保留2个文件、1,496,268字节、4051条完整JSON，队列丢弃0；DB暂停探测约1001ms后报告失败。最终后端源码SHA-256为`3d5f9d06aaaf23c072489e12a8f92475167c234bf8da84ea7c9d9b3fa61a7a3b`，二进制与源码指纹在报告中保留，不替换为之后的提交号。

双Godot客户端离屏回归也通过：聊天协议42项、增量协议50项、双端共53项，8张真实截图，覆盖重连接管、撤销、位置持久化、聊天与互见，产物在`/tmp/opencode/vssjx-monitor-shared-world/`。配置文件真实进程回归通过。源码修改后的结果应以最后一次`report.json`指纹为准，不能把提交前结果改写为后续commit。

账号数据库/令牌轮换/撤销/重启与Godot账号界面18项回归通过；角色创建/回执/数据库事务与角色界面47项回归通过。10人release容量smoke的闲置/60%移动均保持全员互见，约10Hz，移动观察p95为98ms、零协议/连接错误；原始结果在`/tmp/opencode/vssjx-monitor-capacity-smoke/`，该次记录的源码指纹独立保留（最终格式化和监听错误日志优化前），不冒充本次源码的千人验收。

## 指标含义与限制

- HTTP耗时只统计处理到生成响应头，不含响应体传输和WebSocket存活时间；p95为非累积固定直方图推导的桶上界，不是精确分位数。
- 在线角色与Socket数量可能不同（握手、接管与离线宽限）；保留角色包括未过期的离线所有者。不会返回玩家清单或私人资产。
- tick间隔包含调度等待；工作耗时为该tick推进/聊天排队/编码的总耗时，不含网络或数据库IO。late_intervals统计大于150ms的间隔。
- shared_publication_bytes是每tick共享编码只计一次；sent_application_bytes是成功交给WebSocket发送的应用内容合计，不等于客户端确认到达，也不含TCP/TLS/代理开销。
- 数据库快照约5秒更新，带checked_at_ms；DB故障与采样过期明确区分。RSS仅Linux`/proc`可用，其余平台返回null，不冒充0。
- dropped_records为控制台/文件两个队列的丢弃数之和，镜像输出可能重复计同一事件；file_io_errors为文件写入失败，不等于丢失日志条数。硬退出、磁盘损坏或严重背压仍可丢日志，非审计型持久回执。
- 容量smoke只验证10人、小规模闲置/移动与聊天，不重新认证已有千人结果；容量工具默认关闭文件输出和监控监听以避免端口冲突，核心计数/健康采样仍运行。本次没有验证千人完整混合负载、长稳、正式TLS/公网或生产磁盘性能。
- 默认10MiB×7只是可调的技术容量预算，不定义D08审计天数；不提供历史指标仓库、告警通知、跨进程汇聚、运维写接口或日志全文Web搜索。
