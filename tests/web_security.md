# P2b：Web凭据隔离与受控服务配置

本单元建立Web配置实现和真实调用方的安全边界。**Web工厂仍返回不支持**（即使显式传入`native`也不能在实际Web运行时回退）；没有启用网页登录或新增Web导出。下面的Web策略测试在原生Godot中注入页面Origin，不是实际Godot Web/浏览器验收。

## 契约与接入

`PlatformRuntimeConfigInterface`新增：

| 操作 | 默认契约 | 原生实现 | Web实现 |
|---|---|---|---|
| `connection_options()` | 不支持 | 可编辑地址，仍使用原来的地址偏好 | 只读、固定的本站API基址 |
| `check_network_target(address)` | 不支持 | 保留已有地址/HTTPS校验职责 | 仅接受固定API基址 |
| `allows_remembered_login()` | 否 | 保留已有用户主动勾选行为 | 否 |

- Web配置只读`JavaScriptBridge.eval("window.location.origin", true)`与随包发布的`interface/profiles/web_runtime.tres`。不读取页面路径、查询、片段、DOM配置、JS配置全局变量、环境变量或已保存地址。
- 默认API基址为当前HTTPS Origin，静态游戏可以在`/game/`，请求仍走`/api/v1/...`。需要路径前缀时，发布方在构建资源中设置`api_prefix="/ssjx"`，得到`Origin/ssjx/api/v1/...`，不是玩家通过URL参数选择服务器。
- 前缀只允许`/`分隔的ASCII字母、数字、下划线和连字符段，不允许尾斜杠、空段、点段、百分号编码、查询、片段或完整URL。无效配置返回`WEB_CONFIG_INVALID`，不回显原始值。
- `allow_loopback_http`默认`false`。只有本机测试构建可显式启用，且仅允许`localhost`、`127.*`和`[::1]`；不能放宽局域网或任意HTTP。服务端仍需独立配置P2a的精确开发Origin。
- 在既有地址规范化后精确匹配固定基址；错误来源、协议、端口、子域和API前缀均拒绝为`TARGET_NOT_ALLOWED`。不把任意同域路径扩展成可选服务基址。
- 地址偏好在固定配置下完全绕过原生路径与同步存储；确认固定地址只是确认配置有效，不是持久化成功。`local`只表示离线入口，不能作为网络目标，且不向线上导入任何离线资产。离线选择的浏览器持久化不在本单元实现。
- 账号请求（含Bearer、刷新、注销及票据）、服务发现、票据返回后的WebSocket建连均在创建网络对象前检查平台目标。账号目标检查先于自动刷新，防止篡改会话地址后触发错误目标请求；HTTP继续保持`max_redirects=0`。

## 凭据边界

- `RememberedLogin`构造及每次读取、写入、删除均先检查能力；另有实际`OS.has_feature("web")`硬防护，不能靠误装原生上下文开启浏览器凭据文件IO。
- Web策略下不选择凭据路径，不读取/迁移/覆盖/删除原生`.login`、`.login.key`或临时文件。平台未就绪同样禁止凭据IO。原生加密文件格式、设备本地密钥及主动勾选行为保持不变；这仍不等同于系统凭据保险库。
- 登录UI隐藏并禁用“记住密码”和地址修改。程序化切换复选框、遗留的待保存密码、注销回填及迟到登录回调不能绕过底层保护。页面提示刷新后需重新登录，不声称网页持久保存了服务地址或身份。
- 原有密码清理、内存访问/刷新令牌、注册后内存自动登录和退出清空规则继续沿用；不新增Cookie、Web Storage、IndexedDB、URL令牌、HTML输入桥接或凭据日志。浏览器自身的密码管理器不由本接口管理。

## 可复现验证与隔离

```sh
python3 tests/run_web_security.py --output /tmp/opencode/vssjx-web-security-final
python3 tests/run_platform_interface.py --render --network \
  --output /tmp/opencode/vssjx-web-security-acceptance
python3 tests/run_game_export.py --output /tmp/opencode/vssjx-web-security-export
python3 -m unittest discover -s tests -p 'test_*.py'
```

`run_web_security.py`复制独立源码与协议夹具，隔离XDG数据/配置/缓存目录，清除继承的`SSJX_*`，只创建两个自身持有的回环HTTP监听。不读取私有`.env`，不使用真实账号、数据库或存档。页面Origin与本机HTTP开关只在测试子类/复制的资源中注入；正式资源始终保持HTTPS默认值。虚拟显示渲染依赖配置见[testing.md](testing.md)。

测试层次：

1. `platform_web_security_test`：原生Godot上执行Web配置验证，使用存储计数夹具检查无同步文件操作；真实原生加密凭据在策略切换前后摘要一致。通过真实登录UI、OnlineAccount、发现及世界客户端检查错误目标被拒绝。
2. `platform_web_network_test`：真实原生`HTTPRequest`驱动注册、内存自动登录、角色查询、票据、令牌轮换、重定向拒绝和注销；服务监听核对8个准确的`/ssjx/api/v1/...`请求。另一回环监听必须收到0个请求，不能只凭客户端错误提示推断没有泄漏。
3. 静态检查配置来源、默认安全设置、每个网络入口的目标检查顺序和凭据IO前置保护；全量原生回归及实际PCK审计另行运行。

### 本机验证（2026-10-16）

Linux、Godot `4.7.2.stable.gentoo.ed1daf0bf`：

| 检查 | 结果 |
|---|---|
| Web策略与真实调用方（注入Origin） | 121项检查通过 |
| 相同策略场景的实际原生渲染 | 121项通过；Xvfb/Mesa llvmpipe/OpenGL ES，不是浏览器渲染 |
| 真实原生HTTP夹具 | 28项检查通过；受控服务8请求，外部测试监听0请求 |
| 原生平台完整执行器 | 32步骤通过，含既有游戏流程383项、行走6018项、登录/注册/角色/输入/资源回归、真实退出及窗口关闭保存、Rust发现与地址跨进程恢复 |
| 真实PostgreSQL/Rust共享世界 | 两个独立Godot headless客户端25/28项通过；票据、隔离、权威移动、公共聊天、接管/撤权和位置持久化集成通过 |
| Python全量 | 85项通过 |
| Linux/Windows预设实际PCK | 各60项通过，含包内原生策略、Web配置拒绝原生回退和公开构建默认值；由Linux引擎加载两包，不是Windows可执行文件验收 |

报告在`/tmp/opencode/vssjx-web-security-final/report.json`；Python日志为`/tmp/opencode/vssjx-web-security-python.log`；实际导出与最终扩展审计日志在`/tmp/opencode/vssjx-web-security-export/`的`linux-audit-final.log`及`windows-audit-final.log`。新夹具显式检查日志没有测试密码、票据或访问/刷新令牌。以上结果不改写P1/P2a的历史验收范围。

完整原生回归报告为`/tmp/opencode/vssjx-web-security-acceptance/report.json`，输出37张游戏页面截图，已检查角色创建和地图代表图。虚拟显示环境未提供真实系统输入法；不把X11输入法警告下的控件测试当作中文候选事件顺序验收。

共享世界回归使用`python3 tests/run_shared_world.py --output /tmp/opencode/vssjx-web-security-shared-world`，日志为`/tmp/opencode/vssjx-web-security-shared-world.log`；本轮独立运行一次通过，不声称修复了P2a记录中的既有偶发失败。

## 未完成

实际浏览器中`JavaScriptBridge`及HTTP/重定向行为、页面刷新/回收后的凭据消失、Web导出包审计仍须后续实测。本单元不代表已支持Web、Windows实际运行或iOS/Android真机。Web异步存储和所有调用方迁移、单线程资源策略、显示/生命周期适配、外壳、Web离线/在线入口选择及受控同域HTTPS/WSS部署仍未完成；不把当前同步原生存储或能力快照交给Web工厂冒充可用。

服务端来源准入与本单元相互独立，不能相互替代，见[web_origins.md](web_origins.md)。PC admin仍在游戏导出之外，现有非本单元admin/主题改动不纳入提交。
