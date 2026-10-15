# 同步优化v2：千人当前功能短测通过

2026-10-15，同一台i5-8300H（4物理核/8线程）本机环境，Rust release服务端、Rust协议机器人和临时PostgreSQL共机。沿用原 `capacity_profile.json`，没有改准入上限、10Hz世界推进、72px/s移动速度、每2秒目的格输入或全员互见范围。

**已通过：当前共享地图/公共聊天的1000人短时协议负载。未完成：完整玩法、Godot千人渲染、公网TLS/带宽、慢连接故障矩阵及60分钟长稳验收。**

## 结果

| 场景 | 实际在线（开始/结束） | 验过完整目标人口的客户端 | 重建状态更新/人 | 移动观察p95 | ping p95 | 聊天投递p95 | 未压缩应用正文下行 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 50人，60%移动 | 50/50 | 50 | 10.00Hz | 100ms | 3ms | 57ms | 0.32MiB/s |
| 200人，60%移动 | 200/200 | 200 | 10.00Hz | 103ms | 9ms | 138ms | 4.44MiB/s |
| 500人，60%移动 | 500/500 | 500 | 10.00Hz | 112ms | 25ms | 87ms | 26.82MiB/s |
| 1000人，空闲+聊天 | 1000/1000 | 1000 | 10.00Hz | — | 21ms | 115ms | 0.98MiB/s |
| 1000人，60%移动 | 1000/1000 | 1000 | 10.00Hz | 136ms | 43ms | 135ms | 103.89MiB/s |
| 1000人，全员参与移动 | 1000/1000 | 1000 | 10.00Hz | 156ms | 52ms | 161ms | 176.55MiB/s |

每档30秒，1000人60%移动档60秒；每档预热5秒。1000人入场并发16，三档入场分别7.15、6.28、6.93秒，均在原60秒预算内完成。1000账号真实注册/登录/建角准备27.13秒，并发2，不是千人同时密码登录爆发测试。

所有档均零协议/连接/服务器错误。每个千人客户端各安装一次初始快照，在计时开始前已重建完整1000人口；不是仅打开1000个空闲socket。每个发布均验证SHA-256、连续序号、身份集合、网络ID、进入/离开和移动字段。最慢客户端在60秒移动档收到599次完整人口状态边界（约9.98Hz），其余档每客户端至少300次，不以平均数掩盖个别客户端饿死。

移动份额指按原配置每2秒下发合法目标的角色比例；到达目标会自然停步，没有改目标序列或偷偷降低输入率。60%千人档实际发送17994条，计划约18000条；全员千人档发送14988条，计划约15001条。60%档计时截止时15条移动和4个心跳尚待观察；全员档55条移动尚待观察，均单列，不把末尾未知结果统计成成功。移动p95是输入到客户端验证并安装包含自身修订的状态的端到端延迟，不是纯服务端耗时。

60%千人档60条聊天均确认、投递60000次；全员档30条均确认、投递30000次。临时数据库无事务回滚/死锁，测试容器已清理。

## 修正内容与统计口径

- `server/src/world_replication.rs`：每100ms只构造/排序/编码一次公共状态，发布后不可变，连接共享引用。世界状态锁内仅采样/推进，不做逐连接全图复制、排序或编码。
- 初始JSON快照仍分块、验摘要、完整安装；记录JSON按发布版本懒缓存复用。之后仅发送进入、离开与变化的移动记录，不反复重发静态名字/职业。
- `VWD2`每移动记录26字节；空闲tick仅70字节。初始基线和订阅原子绑定，从基线后连续消费，每tick都有权威边界。每个客户端保留完整人口，未分线/隐藏玩家。
- 有界共享环仅保留32个tick；慢接收者落后或发送超时必须重连取全量，不能跳过生命周期事件继续显示残缺状态。
- Godot客户端整包校验后原子更新，覆盖重复/缺号、错误摘要/流代次、未知网络ID、同UUID离开重入、版本回退及1000身份上限。

优化前以“完整快照完成次数”衡量状态更新；v2以“初始快照+连续增量重建后的完整人口权威边界”衡量，**不是仍在每秒重复发送10份全图**。移动/ping延迟、输入计划、人数/互见要求未放宽，并新增最慢客户端至少8Hz与计时前全员重建完成的门槛。JSON结果的旧snapshot计数字段保留兼容，实际含义由world_sync_version=2和state_updates字段明确标注。

协议布局和跨语言固定十六进制样例在 `shared/protocol/world-sync-v2.json`。客户端和服务端须一起更新；旧世界协议明确返回 `WORLD_PROTOCOL_MISMATCH`，账号/HTTP协议仍为1。

## 与原失败基线比较

[优化前报告](capacity.md)及原 `capacity_results.json` / `capacity_results.md`保留不覆盖。

- 200人，同为约10Hz：正文83.25→4.44MiB/s，服务器平均CPU259%→31%。
- 500人：同步2.35→10.00Hz，移动观察p95 3484→112ms，服务器平均CPU425%→65%。
- 原1000目标只能入场538～594人；现在三档均真实满1000，所有客户端重建完整人口。不能拿原未满员的延迟冒充千人前后对比。

1000人60%移动时服务器平均CPU约83%（100%=1逻辑核）、峰值RSS270MiB；机器人CPU约196%、RSS260MiB；数据库CPU约27%。全员移动时服务器约93%、RSS278MiB，机器人约297%、RSS323MiB。未扩大数据库连接池或密码工作线程。

全员移动正文176.55MiB/s约1.48Gbit/s，尚未含TCP/TLS开销，**超过1Gbit/s公网出口能力**。因此本机通过不代表随便一台公网服务器都能承载；部署仍需验证实际链路，或继续做紧凑编码/共享压缩优化，不能隐藏玩家降低流量。

## 复现与产物

```sh
python tests/run_capacity.py --output /tmp/opencode/vssjx-capacity-delta
python tests/summarize_capacity.py /tmp/opencode/vssjx-capacity-delta \
  --output tests/capacity_delta_results.json --markdown tests/capacity_delta_results.md
```

完整数据：[capacity_delta_results.json](capacity_delta_results.json)、[自动表格](capacity_delta_results.md)。原始环境、阶段记录、逐秒CPU/RSS/FD和日志：`/tmp/opencode/vssjx-capacity-delta/`。源代码指纹`150f76329ec127a47bcfea7ad1d17ccc12c05a3181022ea08803d90dd5c4d4bc`，服务二进制指纹`6a623dcb9a9bad097ce101cbd51c3da0144b1a818b1bc5c2316e33a56cc38fba`；构建含未提交工作，不能仅用旧HEAD标识。

其他回归：

```sh
python tests/run_shared_world.py --render --output /tmp/opencode/vssjx-delta-ui-final
python tests/run_account_auth.py
python tests/run_characters.py
python -m unittest discover -s tests -p test_capacity_tools.py
cargo test --locked --offline --manifest-path server/Cargo.toml
cargo test --locked --offline --manifest-path tests/load_driver/Cargo.toml
```

- 双独立Godot客户端真实OpenGL离屏53项，8张截图，零失败；位置同步、聊天、原消息ID重试、掉线重入、离线隔离均通过。
- Godot世界增量协议50项、公共聊天协议42项；包含1000身份重建，但**不等于千人角色渲染测试**。
- 账号UI18项、角色UI47项及两套PostgreSQL回归通过。
- Rust服务26项、Rust压测工具3项、Python统计/门槛7项通过；服务端和压测工具Clippy所有target以`-D warnings`通过。

`.env`与正式数据库未使用，凭据只存在内存。测试记录生成时改动尚未提交；后续分阶段提交不替换本报告中当时的源代码、二进制指纹或原始HEAD。
