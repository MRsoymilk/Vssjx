# 主游戏 Web 导出

这是主游戏的单线程 Compatibility 导出，不再是只有存档的夹具。使用同一套主场景、地图、战斗、v1存档和网络调用方；不新增线上导入离线角色的路径。

## 打包

Godot **4.7.2**，匹配官方 `web_nothreads_release.zip`（debug构建对应debug模板）。可安装官方导出模板后在编辑器选择 **Game (Web)**，也可使用隔离构建脚本：

```sh
python3 tools/export_web.py --output /tmp/opencode/vssjx-web-release \
  --template /path/to/web_nothreads_release.zip
```

脚本固定核验提供的官方模板ZIP摘要；不提供`--template`时使用已安装模板，并在报告中标记未由脚本校验模板摘要。release模板SHA-256：`d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0`；debug：`08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a`。本机模板从官方HTTPS发布资产按范围提取，验证ZIP成员CRC，**不等于校验整个tpz摘要**。

只发布输出目录中的 **`public/`**，不要发布其父目录。源工程副本、测试、报告和用户目录均不在public内。脚本只复制客户端公开子目录，排除admin、tests、隐藏文件及导入缓存；预设也独立排除admin和tests。不会复制服务端、`.env`、数据库或用户存档。已有非空public目录拒绝覆盖，防止混入旧产物。

包含网页外壳、JS、WASM、PCK及中文字体许可。Noto Sans CJK SC按SIL OFL 1.1随包提供，来源/摘要在`client/assets/fonts/provenance.json`；仅Web挂入SystemFont回退，不改变原生系统字体及控件的原有高度。

## 运行与部署边界

- 用HTTP服务器打开，不支持直接双击`file://`。本机离线预览：在`public/`运行`python3 -m http.server 8000 --bind 127.0.0.1`，访问`http://127.0.0.1:8000/`。不要把开发服务器暴露公网。
- 正式站点使用HTTPS，WASM响应须为`application/wasm`，整个public保持同一路径布局。联机API由构建配置确定在同Origin；默认`api_prefix=""`，即`/api/v1/`；WebSocket走WSS。服务端仍须显式允许网页Origin；静态文件部署不等于部署游戏服务。
- 本机联机HTTP只能构建时加`--allow-loopback-http`；这是开发包开关，不读取查询参数/页面全局变量，不允许非回环HTTP。正式包不加该选项。
- 不用线程/GDExtension/PWA/service worker，不要求为线程设置跨域隔离头。网页提供点击启动、错误提示、2:3固定游戏画面、CSS安全区。画布保持640×960渲染表面，对应320×480逻辑坐标，通过CSS等比适配，不修改玩法坐标。
- Web工厂只在真实Web运行时组装浏览器端口，禁止显式native覆盖；原生进程也不能伪装成Web。Platform等待IndexedDB初始化后才就绪，失败不降级为原生或内存假存档。
- 资源队列沿用共享任务、取消、所属页面、代次、超时及类型检查；Web每帧最多加载一个未缓存包内资源，不调用线程API。单个`ResourceLoader.load`仍是同步的，不能承诺无长帧或可中断；完成后再次检查期限。
- 页面失焦/隐藏清理按键、导航/接近目标，离线逻辑不积累后台移动/自动战斗时间；在线网络仍按原有状态机处理断线/重连，不在生命周期回调伪造结算或存档成功。浏览器挂起时不能保证STOP包送达。
- Web封面“登陆游戏”直接进入账号登录页，使用同源游戏服务，不再经过额外的模式选择弹窗。账号密码/令牌不进离线槽，Web记住密码仍被硬禁用。原生本地玩法和存档隔离逻辑保留；浏览器不能由游戏直接关闭。
- 保留[IndexedDB存储边界](web_storage.md)：事务完成才算成功；多标签最后提交覆盖；清站点数据/驱逐可能丢档；没有退出瞬间保存或永久保留保证。

## 验证方式

```sh
python3 tests/run_platform_interface.py --output /tmp/opencode/web-native-check
python3 tests/run_game_export.py --output /tmp/opencode/web-native-pck-check
PLAYWRIGHT_MODULE_PATH=/path/to/node_modules/playwright-core \
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/path/to/chromium \
python3 tests/run_web_game.py --public /path/to/export/public \
  --output /tmp/opencode/web-game-browser-check
```

当前主游戏浏览器脚本通过真实按钮、键盘和画布验证封面直接进入登录、返回、刷新及屏幕适配；不注入Game状态、不替换Platform、不把测试API装进生产包。回环夹具需使用带 `--allow-loopback-http` 的开发导出，明确拒绝登录并返回503，不提供真实账号或世界服务。脚本只允许一次主动登录请求，不再执行已移除模式弹窗中的离线入口。实际部署验证使用 `tests/web_deploy_browser.cjs`，见下方最新记录。使用独立浏览器profile和回环端口，页面不接触实际账号和存档。SwiftShader WebGL不代表手机GPU性能，英文按键测试不代表中文系统IME。

### 移除重复入口（2026-10-17）

- 删除 `_web_entry` 及其模式弹窗，Web 与原生封面统一调用账号登录页。没有修改登录表单、账号接口、同源与凭据策略、原生本地角色或存档格式。下方2026-10-16的14项离线UI验证是历史记录，不表示移除该入口后仍能从网页封面进入原离线选择流程。
- 新导出目录 `work/builds/web-direct-login-20261017/public`，已替换本机8000和局域网HTTPS8443的网页挂载。保留旧包作为回退；没有重启Rust游戏服务或修改数据库，证书安装页不变。
- 原生登录页49项、双模式1048项通过。真实WASM浏览器入口6项通过，覆盖一次封面点击即能提交到拒绝夹具、返回、手机/横屏尺寸、触摸、刷新与无脚本错误。
- 已部署本机HTTP及局域网HTTPS的真实浏览器各5项通过：一次封面点击后直接使用账号表单，主动登录不存在账号，收到真实服务401；同源WebSocket升级和浏览器运行正常。没有创建账号、修改角色或使用玩家凭据。
- 部署文件/HTTP/WS14项、CA验证的LAN HTTPS/WSS19项通过，检查实际挂载的是本轮文件。日志和截图在 `work/web-deploy/direct-*`，部署检查仍不等于手机真机或成功账号登录验收。

### 本轮结果（2026-10-16）

- 主游戏debug包：真实Godot WASM/Chromium **14项通过**，覆盖创建v1角色、NPC领任务、移动、单线程战斗资源准备、击败山狼并只结算一次、刷新后实际Game继续移动、重启浏览器进程后恢复、手机尺寸布局及模拟触摸、横屏尺寸等比显示。截图位于`/tmp/opencode/vssjx-web-game-browser-closure/`。
- 正式HTTPS-only配置的release包：同一完整浏览器流程**14项通过**，不是仅对debug或存储夹具的验证。报告/截图`/tmp/opencode/vssjx-web-game-release-browser-verified/`。本机离线HTTP测试不开放联机HTTP。
- 存储专用真实Web回归：**110项通过**，包括配额/中止/完成通知丢失和超时恢复，见`/tmp/opencode/vssjx-web-game-storage-regression/`。
- 原生平台：**28步骤通过**，新增单线程队列**13项**，原生资源/输入/存档/游戏/HTTP夹具/退出继续通过，见`/tmp/opencode/vssjx-web-game-native-final/`。
- Linux和Windows预设实际PCK，以及release Web PCK：分别**70项通过**，含动态资源、中文实际字形、admin/tests排除与原生兼容；不是Windows可执行文件验收。输出`/tmp/opencode/vssjx-web-game-pck-audit/`及`/tmp/opencode/vssjx-web-game-release/`。
- Python全量：105项中104项通过，唯一错误仍是既有`test_original_monsters.py:71`期望独立导出器未生成的`animation_audit.json`。未修改/删除并行资源产物，不把该项记为通过。

浏览器使用Chromium `153.0.8010.12`及官方Godot `4.7.2` WASM；debug开发包显式允许回环HTTP联机，release配置保持HTTPS-only。测试中离线流程没有请求账号/世界API。

### 本机交付产物

从干净的代码提交`3aed515`重新构建release，输出`work/builds/web/`及`work/builds/vssjx-web.zip`（25,536,955字节）。ZIP根目录即完整public内容，已逐文件对照构建报告核验摘要和ZIP CRC；包SHA-256为`ae863db946fde029e96a72dc59704d760951714824d392fd0b337e05d6bca954`，旁置`vssjx-web.sha256`及`web-build-report.json`。这些是忽略的本机构建产物，不提交到仓库。

最终交付目录再次通过真实Chromium完整**14项**及Web PCK **70项**检查。证据在`/tmp/opencode/vssjx-web-game-final-package-browser/`及`/tmp/opencode/vssjx-web-release-3aed515/pck-audit.log`，构建报告记录代码提交、工作区是否干净及公开源文件摘要；不将测试profile、源副本或日志放入ZIP。

在项目根目录预览：

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory work/builds/web
```

访问`http://127.0.0.1:8000/`，选择开始游戏→登陆游戏→离线单人。请勿直接双击HTML，也不要将此开发HTTP服务暴露公网。

## 尚未验收

完整线上登录/角色/共享世界浏览器闭环、HTTPS/WSS部署、严格CSP（可信JSBridge模块仍使用eval）、Safari/WebKit、iOS/Android真机、系统中文IME和软键盘、触摸/横竖屏设备矩阵、真实配额/驱逐/崩溃、持久存储权限UX及离线导入导出。能打包和Chromium离线通过不等于P2整体、P3/P4或公网发布验收通过。
