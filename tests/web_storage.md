# P2c-2：浏览器离线槽的真实 IndexedDB 持久化

后续状态：主游戏Web预设/工厂已在后续单元接入，见[主游戏Web导出](web_game.md)。下文“工厂未启用”是本存储单元完成时的历史边界，不代表当前状态；IndexedDB契约保持不变。

本单元新增`adapters/web/web_storage.gd`及其随包发布的`indexeddb_storage.js`。使用上一单元的可等待契约，不改v1存档、玩法或在线协议。**生产Web工厂仍返回不支持**；实际Web验证使用独立的存储夹具，不代表完整Web游戏、手机或生产部署已验收。

## 存储边界

- 使用当前Origin的独立IndexedDB：数据库`vssjx-offline-v1`、对象仓库`saves`、键`save-v1`。Web存档路径配置只返回逻辑槽`offline://save-v1`，不接受显式本地路径、查询参数或环境变量覆盖。
- 直接保存现有v1 JSON文本，不包入新的玩家数据结构，不迁移原生`user://`存档或凭据，不存账号、密码、访问/刷新令牌、服务器地址偏好。存储层不掌握玩法字段；合法性仍由Game验证。
- 不调用Godot虚拟文件系统的写入/`syncfs`，不调用没有完成回调的`JavaScriptBridge.force_fs_sync()`。可信JS模块从PCK读取一次，操作通过JS对象方法和参数传递，玩家内容不插入`eval`源码。临时工厂全局名随机生成并立即删除。
- 仅在安全上下文初始化；HTTPS及浏览器认可的本机回环测试可用，公开HTTP不开放。浏览器拒绝、API缺失、打开失败/受阻都是失败，不当作空槽。
- 每个适配器同一时刻只受理一个操作，不自动重放写入。初始化成功后才能读写；`initialize()`可在超时/故障后显式恢复，`close()`为终态。未来生产平台入口必须等待初始化后才允许Game使用，目前未接入生产工厂。

### 何时算保存成功

`put`请求的`onsuccess`不能证明事务已提交，后续仍可能中止。只有`IDBTransaction.oncomplete`才能返回：

```text
written=true, durability=browser_sync, bytes=<UTF-8字节数>,
retention=<unknown/best_effort/persistent>, transaction_durability=<浏览器报告值>
```

写入在浏览器支持时请求`durability: strict`；旧签名仅在`TypeError`时回退。`browser_sync`表示IndexedDB事务完成，不是设备断电、磁盘故障、浏览器永久保留或云备份保证。`retention`是最近一次异步`navigator.storage.persisted()`查询的状态快照，不是本次写入成功条件，也不自动申请持久存储权限。

### 失败、超时和释放

- 每次读写/检查最多1MiB UTF-8；限制无效、记录类型错误、超过上限均有明确错误。使用精确键游标区分“缺失”与“已存在但值为undefined的坏记录”，不把坏记录误判为空槽。
- 配额不足映射`QUOTA_EXCEEDED`，拒绝访问为`STORAGE_DENIED`，事务中止为失败。仅使用允许的稳定错误码和固定中文消息，不回显原始浏览器异常、路径或数据。
- 默认15秒超时会尝试中止事务并关闭连接，返回`STORAGE_TIMEOUT`；写入同时标记`uncertain=true`，没有成功回执。完成通知丢失时事务可能已经提交，**不能假定一定回滚**。端口进入失败状态，重新初始化并读取实际状态后才能继续。
- 超时后到达的打开连接会被关闭；旧完成不能重新标记成功/就绪。页面后台的浏览器计时器可能节流，15秒不是后台实时保证，不改变服务端断线或闲置计时。
- `close()`和RefCounted释放都会解绑JS回调、尝试中止自己的事务并完成待处理消费者；不让旧回调访问已释放的GDScript。PREDELETE中不调用已经归零的self方法。取消/释放同样不保证撤回已提交的底层写入。
- `status()`区分`uninitialized/initializing/ready/failed/closed`、忙状态和保留策略；原生环境不能初始化该端口，旧同步存储方法仍不支持，不能降级为原生文件或内存假保存。

同Origin的离线槽为单槽；IndexedDB串行化事务，但本单元不做多标签页的角色合并或写入冲突协商，最后提交覆盖该槽。线上角色/会话互斥仍由服务端处理，不从离线槽导入资产。

## 真实 Web 验证方式

`tests/run_web_storage.py`构建一个独立96×96的单线程Compatibility Web工程，只复制公开接口、真实`game_state.gd`、账号安全守卫及`tests/fixtures/web_storage/`。测试Platform仅组装存储和配置，等待真实初始化；不复制Game的存档业务，也不启用主游戏工厂、地图、admin或线上服务。

Playwright使用自身输出目录中的持久Chromium profile和自己持有的回环HTTP端口，不读取用户浏览器profile、私有`.env`、真实账号或玩家存档。测试包括：

1. 真实Godot WASM/JavaScriptBridge下写入原v1 JSON，刷新、关闭页面重开、**关闭并重启浏览器进程**后，从IndexedDB恢复角色/铜钱/性别/签名；不使用Playwright storageState恢复数据冒充持久化。
2. 真实Game保存路径中的配额错误、中止事务和丢失完成通知故障注入。验证请求成功后事务仍可失败；原存档保留；事务已提交但通知丢失仍返回超时未确认，恢复后读取真实新记录，而非猜测回滚。
3. 错误槽、UTF-8超限、损坏JSON/非字符串/undefined记录、不同Origin隔离、站点数据删除、连接关闭、晚到结果和RefCounted释放。清理后重新加载应明确无存档，不能返回内存缓存成功。
4. 实际`OS.has_feature("web")`为真时，即使测试暂时注入“允许记住密码”的原生策略，RememberedLogin仍拒绝读/写/删；无凭据路径、文件或IndexedDB凭据。测试HTTP监听也检查没有账号/世界API请求。

故障代码仅在测试目录，通过浏览器API包装注入，不在生产适配器放URL/全局开关。配额场景是浏览器API故障注入，不代表真实设备配额耗尽、断电或崩溃矩阵已验收。

## 工具链与命令

- 编辑器：Godot `4.7.2.stable.gentoo.ed1daf0bf`。
- Web模板：[官方4.7.2发布](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)的`Godot_v4.7.2-stable_export_templates.tpz`内`templates/web_nothreads_debug.zip`。夹具固定模板SHA-256为`08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a`，运行时还核对实际Web引擎版本。
- 本次模板由官方GitHub HTTPS资产的字节范围读取，校验ZIP成员CRC并计算/固定上述SHA-256，共下载约10MiB；未下载1.28GB完整模板包，**未核验完整tpz的摘要**。来源和范围记录在`/tmp/opencode/vssjx-web-toolchain/template-provenance.json`，不将模板二进制或依赖提交。
- Chromium采用实际WebGL/SwiftShader，不是原生端口模拟；仍不是手机硬件或Safari证明。

```sh
PLAYWRIGHT_MODULE_PATH=/tmp/opencode/vssjx-web-toolchain/node_modules/playwright-core \
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/home/vv/.cache/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell \
python3 tests/run_web_storage.py \
  --template /tmp/opencode/vssjx-web-toolchain/web_nothreads_debug.zip \
  --output /tmp/opencode/vssjx-web-storage-final-verified

python3 tests/run_platform_interface.py --network --output /tmp/opencode/vssjx-web-storage-native-final
python3 tests/run_game_export.py --output /tmp/opencode/vssjx-web-storage-export-verified
python3 -m unittest discover -s tests -p 'test_*.py'
```

两个原生游戏预设仅增加可信JS模块的打包过滤项，不增加生产Web预设；实际PCK审计继续排除admin和测试，并核对模块可读及不能在原生环境冒充浏览器持久化。

## 验证结果（2026-10-16）

| 检查 | 结果 |
|---|---|
| 真实Godot Web/IndexedDB/故障及恢复 | 110项通过；WASM引擎`4.7.2-stable (official)`，Chromium `153.0.8010.12` |
| 原生适配器防回退与回调清理 | 18项通过，且无脚本/析构错误 |
| 原生平台完整回归 | 28步骤通过，含存档迁移、游戏流程、行走、输入/资源、账号/角色HTTP夹具、退出保存及Rust地址恢复 |
| Linux/Windows预设实际PCK | 各67项通过；由Linux引擎加载两包，不是Windows可执行文件验收 |
| Python全量 | 92项通过 |

浏览器报告为`/tmp/opencode/vssjx-web-storage-final-verified/browser-report.json`，工具链/生产模块摘要为同目录`report.json`（模块SHA-256 `fd8be8674beb311a8e840eb1b43068a513ced5eeb308231c65609dca409ed574`）。原生报告、导出审计和Python日志分别位于`/tmp/opencode/vssjx-web-storage-native-final/`、`/tmp/opencode/vssjx-web-storage-export-verified/`、`/tmp/opencode/vssjx-web-storage-python-verified.log`。本轮没有以原生模拟或浏览器数据快照注入替代刷新/进程重启后的真实读回；没有重新执行手机、生产TLS或PostgreSQL容量矩阵。

本单元在本地功能分支`feature/web-offline-storage`独立提交；未推送或改写共享远端。验证基线为`46beef5`加本单元修改，未覆盖原生怪物动画等其他工作的文件。

## 仍待推进

Safari/WebKit、iOS/Android真机、隐私模式及真实配额/回收、用户持久权限请求、导入/导出、完整游戏Web启动与离线/在线选择、单线程资源/生命周期/安全区、公开HTTPS/WSS和发布CSP均未验收。JSBridge使用可信源码eval，严格CSP的兼容/发布政策仍须独立处理。本单元不启用网页账号登录，不改变Origin白名单、票据、会话或原生存档行为。

相关：前置调用方迁移见[storage_async.md](storage_async.md)，凭据与目标边界见[web_security.md](web_security.md)，服务端来源准入见[web_origins.md](web_origins.md)。
