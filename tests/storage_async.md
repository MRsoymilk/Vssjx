# P2c-1：可等待的存档契约与调用方迁移

本单元是浏览器持久化的前置迁移，**不是Web存储实现或浏览器存档验收**。保留原生文件格式、版本1规则和离线/在线边界；Web工厂仍明确拒绝运行，不把同步原生文件API或内存写入冒充浏览器持久化。

## 契约

- `PlatformStorageInterface.probe/read/write`返回`PlatformStorageRequest`，调用`await request.wait()`得到`PlatformResult`。即时原生结果与延迟结果使用同一契约；先完成、后等待、多个等待者和重复完成均有定义，只接受第一次完成。无效完成返回明确失败，不使等待者静默挂起。
- `probe`成功值为严格布尔值：`false`才表示没有存档；无权限、读取失败和超限不是“没有存档”。原生检查通过有界读取区分缺失与不可读，避免误入创建覆盖流程。
- `write`的成功必须带`written=true`及明确持久化边界。当前真实原生实现返回`native_file`（完成既有flush/rename，不承诺断电保护或备份）；为后续浏览器适配预留`browser_sync`，只可在真实同步完成后返回，仍不承诺浏览器永久保留。
- `Game.save_game/load_game/probe_save`均为可等待的`PlatformResult`，不是旧布尔同步API。所有游戏调用方及测试已显式迁移；移除把文件存在性直接当作可加载性的`has_save`路径。
- 保存提交时序列化独立快照。`Game`同一时刻只受理一个存档操作，冲突返回`STORAGE_BUSY`，不隐式覆盖、排队或重放业务命令。未确认/内存回执返回`SAVE_UNCONFIRMED`，不会保留上一次成功回执冒充本次成功。
- 新建角色、切换存档路径、页面切换/释放使相关旧结果失效。旧读取/检查不应用到新页面或新角色；旧写入仍被收尾，但不能更新新角色的回执或错误。**失效不等于物理取消已提交写入**，不承诺撤回底层IO；新写入须等待前一次收尾后重新显式提交。

同步`exists/read_text/write_text_atomic`只保留给原生地址偏好和原生文件回归检查；Web固定同域配置在读取本地路径/偏好前即返回，不调用这些方法。原生记住密码仍受P2b硬防护，Web不迁移、不读取或保存凭据文件。

## 真实调用方

| 入口 | 迁移后的行为 |
|---|---|
| 创建/本地入口/继续角色 | 等待检查与读取；检查失败不当作空槽；初次保存失败不进入地图；旧页面读取不覆盖当前角色 |
| 手动保存/自动保存 | 等待实际结果后提示；自动保存失败可见；未确认时不显示“修行已保存” |
| 任务/奖励/恢复/门派/签名/换图 | 保存前后的输入和页面代次有保护；结果未完成不重复执行；保存失败保留/恢复原有业务内存语义并明确提示 |
| 背包 | 等待结果后刷新反馈；等待期间不重复购买/使用/丢弃；整理失败不再被“整理完毕”覆盖 |
| 战斗结算 | 按原规则先幂等结算一次，再等待保存；失败只重试持久化，不重发奖励或重算回合；结算面板能显示保存未确认 |
| 系统返回登录 | 保存确认后才能离开；失败保留当前页面与提示 |
| 原生窗口关闭 | 等待已有操作收尾，再保存最新状态；最终保存失败留在应用中，不请求退出；重复关闭合并为一次关闭流程 |
| 在线世界关闭 | 不额外写入离线角色，不导入任何离线资产 |

只有实际待完成的操作触发等待提示、暂停离线UI/移动。即时原生操作不触发暂停/恢复事件，不清理寻路标记、不重置动画或闪出等待层。暂停输入不重新采集旧地图坐标，不能覆盖换图时已选定的目的地。

返回值、存储回执和输入等待状态不写入v1存档；旧可选字段默认值、玩家规则、账号协议、在线资产和D01～D08未改动。窗口关闭的失败路径改为“保存失败不退出”，避免异步保存尚未确认就丢失内存进度。

## 测试与隔离

```sh
python3 tests/run_platform_interface.py --render --network \
  --output /tmp/opencode/vssjx-async-storage-final
python3 tests/run_game_export.py --output /tmp/opencode/vssjx-async-storage-export-final
python3 -m unittest discover -s tests -p 'test_*.py'
```

执行器使用独立源码、协议夹具、XDG目录、配置与测试存档；原生关闭探针在独立进程中真正结束并由Python读回存档。虚拟显示配置见[testing.md](testing.md)，无头执行不能替代渲染。

新增`platform_storage_async_test`及`fixtures/delayed_storage.gd`手动控制每个完成屏障，验证实际Game、页面、背包、战斗和退出调用方。它只模拟“尚未完成/成功/失败”的契约，**不模拟IndexedDB、Godot Web文件系统、浏览器配额或页面回收**。测试中注入的`browser_sync`仅检查调用方解释和等待顺序，不是浏览器持久化证据。

实际PCK审计新增包内异步保存、检查、v1读取与清理自身测试槽；继续排除admin场景/脚本/专用资源和所有测试，不用源码资源冒充打包成功。Python检查所有生产存档调用方显式等待，并确认Web没有被工厂启用。

## 验证结果（2026-10-16）

Linux、Godot `4.7.2.stable.gentoo.ed1daf0bf`：

| 检查 | 结果 |
|---|---|
| 新延迟存档场景 | 无头64项、实际OpenGL进程64项，零失败；不是浏览器持久化测试 |
| 完整原生执行器 | 34步骤通过，含Game整流程383项、行走6018项、资源/输入/配置/聊天/属性回归 |
| 原生退出 | 封面退出、窗口关闭两个独立进程实际结束；窗口关闭后读回v1存档并确认铜钱73 |
| 原生网络入口 | Rust发现及地址跨进程恢复58+1+1项通过；账号/角色HTTP夹具50/69/19项通过 |
| Linux/Windows预设PCK | 各64项通过，含包内存档回执及v1读回；由Linux引擎加载两包，不是Windows可执行文件验收 |
| Python全量 | 87项通过 |

完整报告为`/tmp/opencode/vssjx-async-storage-final/report.json`；新增场景日志为同目录下`platform_storage_async_test.log`和`platform_storage_async_test-rendered.log`。导出及审计位于`/tmp/opencode/vssjx-async-storage-export-final/`，Python日志为`/tmp/opencode/vssjx-async-storage-python-final.log`。输出37张既有游戏页面截图，另有遇敌截图用于原生回归，已检查创建角色和地图代表图；不把这些截图当作浏览器存储证据。验证基线为`b289688`加本单元修改，期间远端新增的两项怪物动画提交未合并或纳入这些结果。

渲染环境：独立Xvfb、Mesa 26.2.4 llvmpipe/OpenGL ES。此前临时Xvfb目录已不存在，首次渲染未启动；在`/tmp/opencode/vssjx-async-xvfb/`从Debian Bookworm官方包恢复测试依赖、按Packages索引SHA-256逐包核验，仅解包到该测试目录，未安装/修改系统包或使用当前桌面。最终命令使用：

```sh
XVFB_BIN=/tmp/opencode/vssjx-async-xvfb/usr/bin/Xvfb \
LD_LIBRARY_PATH=/tmp/opencode/vssjx-async-xvfb/usr/lib/x86_64-linux-gnu:/tmp/opencode/vssjx-async-xvfb/lib/x86_64-linux-gnu \
LIBGL_ALWAYS_SOFTWARE=1 python3 tests/run_platform_interface.py --render --network \
  --output /tmp/opencode/vssjx-async-storage-final
```

虚拟显示仍有非致命XKB/XIM警告，不证明真实中文输入法、手机键盘或系统IME事件顺序。本轮未改Rust服务或在线协议，也未重新执行PostgreSQL故障/容量矩阵。

## 后续阻塞

浏览器存储初始化、真实持久化同步、失败/超时与状态恢复、配额及清理风险、存档导入/导出尚未实现。还需单线程资源、显示/生命周期、外壳和Web离线/在线入口；必须经过实际浏览器刷新、重新打开、故障和手机真机测试后，才能宣称网页存档可用。P2a来源校验与P2b凭据/配置边界保持独立，不因可等待API而被绕过。
