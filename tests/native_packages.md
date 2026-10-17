# Android APK / Windows EXE 原生预览包

后续新增Linux x86_64 release便携包，构建方式及实际执行验证见[Linux发布记录](linux_packages.md)。本文APK/EXE的交付摘要保持其原始含义，不覆盖旧包。

2026-10-17：发布推进优先转为Android原生APK和Windows x64 EXE；保留既有Web实现，不删除或回退共享分支的更新。本单元在独立worktree、本地`feature/native-apk-exe`分支开发，起点`05ed199`。不合并、不推送、不重写共享`dev`。

## 包的定位

- **Windows x64**：release模板，PCK嵌入单个`vssjx.exe`，无需另装Godot；另提供含字体许可和说明的ZIP。当前EXE未做Authenticode签名，Windows可能显示未知发布者/SmartScreen提示。预览阶段不修改PE资源，EXE文件图标/产品版本仍可能显示Godot模板信息，不伪称正式安装器。
- **Android**：release模式APK，ARM64+ARMv7，不含x86；模板声明最低API 24、目标API 36，使用Compatibility/OpenGL ES 3。APK已签名才能安装；本轮通过显式`--development-signing`使用专用本地**测试签名**，包名为`com.mrsoymilk.vssjx.preview`，不冒充正式生产证书或商店包，且不是可调试APK。
- 测试签名材料只在外部私有目录中，目录0700、私钥/密码记录0600，不进Git、源副本或交付包。保留该材料才可对同一预览应用连续签名更新；换签名通常需要先卸载，**卸载/清理应用数据会丢本地存档**。生产包须使用发布方自己保管的正式签名，并决定升级/迁移策略。
- Android关闭系统备份，仅申请`INTERNET`权限，不申请外部存储、通讯录、定位等权限。ARM64原生库检查16KiB ELF段对齐，APK检查16KiB ZIP对齐，但这些静态检查不是在16KiB设备上运行通过的证明。

## 原生行为与边界

- 复用同一主场景、玩法、v1文件存档和线上协议；原生存档在系统应用用户目录，不迁移Web的IndexedDB，不把离线角色或资产导入线上。
- 原生可编辑服务器地址并保存，不受浏览器同源、Origin和网页密码桥接限制；账号HTTPS/证书校验及会话、角色互斥不放宽。线上服务须另行部署，APK/EXE不包含服务端或私有配置。内网自签名TLS是否被设备信任仍须实测，不通过忽略证书错误解决。
- 本地离线体验：进入封面“登陆游戏”，在服务器地址输入`local`后登陆；联机填入合法HTTPS游戏服务地址。记住密码仍是原生既有的用户主动选择行为，非系统凭据保险库。
- Android使用固定竖屏、320×480逻辑画面的等比适配；不改变桌面窗口的原有逻辑坐标。启用Android要求的ETC2/ASTC资源导入；Windows/Android追加随包中文字体回退，系统字体仍优先，避免非中文系统缺字。
- Android系统返回键使用现有“等待当前存档→确认保存→退出”路径，保存失败不直接退出；后台强杀仍不能保证最后一刻写盘。生命周期/软键盘/全面屏/后台恢复的完整真机矩阵尚未验收。
- 新增独立矢量剑形应用图标用于当前原生包标识，不把它标成恢复的原版图像。

## 构建

要求Godot 4.7.2、匹配的Windows/Android模板、OpenJDK 17、Android SDK（本机Build Tools 36.0.0、Platform 36）。标准APK不启用Gradle构建，不需要将Gradle工程或SDK拷进客户端。

```sh
python3 tools/export_native.py \
  --output /tmp/opencode/vssjx-native-preview \
  --windows-template /path/to/windows_release_x86_64.exe \
  --templates /path/to/4.7.2.stable \
  --android-sdk /path/to/android-sdk --java-sdk /path/to/jdk17 \
  --development-signing
```

只构建单个平台时使用`--target android`或`--target windows`。只有输出的 **`dist/`** 可以交付，不能分发父目录；测试结果、源副本、隔离Godot配置、用户目录、原始APK资源审计ZIP都在dist外。

Windows模板固定SHA-256为`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`，来自官方4.7.2导出模板tpz中的`templates/windows_release_x86_64.exe`。通过HTTPS范围下载并校验ZIP成员CRC，不声称验证了整个tpz摘要。Android模板来自本机已安装的4.7.2模板，构建报告记录实际SHA-256，不把未经完整上游比对的本机模板说成独立验证过的官方二进制。

正式签名构建不加`--development-signing`，通过Godot支持的`GODOT_ANDROID_KEYSTORE_RELEASE_PATH`、`GODOT_ANDROID_KEYSTORE_RELEASE_USER`、`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`环境变量提供证书配置；密码不写入预设、命令行或公开报告。正式预设包名`com.mrsoymilk.vssjx`，与预览包隔离。商店发布/AAB、Windows正式签名、正式包名/版本/更新策略需另行确认。

构建器拒绝覆盖已有非空dist；只复制客户端公开子目录，排除admin/tests/隐藏配置/密钥。使用独立XDG目录配置Android工具链，不改用户全局Godot设置。`build-report.json`记录提交、是否有未提交改动、源摘要、模板摘要和交付文件摘要；`SHA256SUMS.txt`在dist内。

交付附带项目AGPL许可、字体OFL许可、构建编辑器生成的Godot及组件许可说明，并将项目/引擎许可放入APK资源。`SOURCE.txt`明确对应本地代码提交，不伪造已发布的源码链接；正式向外分发前须安排完整对应源码的提供，并核实原始美术授权。私钥、密码、服务器私有配置不是交付源码的一部分。

## 验证范围

1. Windows检查真实PE32+ x64文件、未伪称签名、PCK嵌入，Linux Godot从EXE中的实际PCK启动并审计资源和存档。
2. APK检查签名、ZIP CRC、ZIP对齐、库架构/ARM64 ELF对齐、包名/SDK/权限/备份/非debuggable属性以及admin/tests/私钥排除。
3. 从实际APK取出assets重新打包，使用Linux Godot检查真实APK里的主场景、动态资源、中文字体和存档业务。**这不是Android进程执行，也不是APK已经在手机安装通过。**
4. 原生既有存档/输入/资源/游戏/账号夹具及Rust服务发现回归；新增构建安全和原生预设单元测试。

本机没有连接Android设备，也没有Windows/Wine运行环境。因此Windows可执行文件启动、Android安装/触摸/输入法/返回/前后台、真实线上登录/战斗/断线、硬件性能与崩溃矩阵仍须实际设备验收。资源使用授权、生产签名、公网运维和D07/D08门槛不因打包完成而自动通过。

## 本轮验证记录

- Windows实际release EXE导出成功，PE32+ x64、无Authenticode签名、内嵌PCK读取/主场景/动态资源/字体/文件存档等**70项审计通过**。
- Android实际release APK导出成功，`apksigner verify`的v2/v3签名校验通过；ZIP CRC、16KiB ZIP对齐、ARM64原生库16KiB ELF段对齐、ARMv7库、最小权限及非debuggable检查通过；从实际APK取出的assets在Linux Godot下**70项审计通过**。
- 本地测试证书SHA-256：`a55572336c440d81b06a2b6599b6722b67e9611267314caf993b13afad084bcc`。这是本轮开发证书指纹，不是生产身份声明。
- 原生完整回归含Rust服务发现：**29步骤通过**，结果`/tmp/opencode/vssjx-native-packages-regression/`。新增构建与原生预设安全测试**10项通过**。
- Python全量124项，121通过、2失败、1错误：actor catalog的既有摘要不一致、monster再生成缺`animation_audit.json`、既有在线PVE夹具引用不存在的测试PNG。三项均在不含本单元改动的`05ed199`归档快照复现，证据`/tmp/opencode/vssjx-native-upstream-baseline-ac3ff6f4d2004612afdfd70db1938920/`。未更改并行资源/夹具来掩盖这些结果。

预提交的实际二进制及审计日志位于`/tmp/opencode/vssjx-native-preview-third/`；该报告明确标记工作树有本单元未提交改动。最终交付从本地功能提交再次构建，不能把上游基线提交当作全部改动的来源。

## 最终本地交付

从干净的本地功能提交`e202e1e`重新构建，完整构建/签名/包内资源审计通过；记录和日志位于`/tmp/opencode/vssjx-native-preview-e202e1e/`。交付副本在原项目忽略目录`work/builds/native-preview-20261017/`，未将二进制或私钥加入Git，也未修改共享工作区源码或共享分支。

| 文件（相对交付目录） | 字节 | SHA-256 |
|---|---:|---|
| `vssjx-android-preview.apk` | 68,541,681 | `860e36b47899de0f14dc8674f5982dca833c98b85237f32e1d1191ee1e7a38f1` |
| `windows-x64/vssjx.exe` | 125,607,080 | `683c3b60a688d29494096394ba0cc2cb272d6ce0ff6bb61564f758bda6c44e30` |
| `vssjx-windows-x64-preview.zip` | 53,404,250 | `94b644fdf9a75af91e3045b99f56fee35f7dd28ef6af23496fa313ea3a5fe993` |

交付副本逐文件对照最终构建报告核验摘要，检查Windows ZIP内容与单文件EXE相同，并对复制后的APK再次验证签名。旁置`native-preview-20261017.build-report.json`；交付目录内有`SHA256SUMS.txt`、使用说明及许可。APK的`.idsig`是可选增量安装侧文件，普通手动安装只需要APK。

这仍是待真实Windows/Android设备验收的内部预览，不是正式对外发行或已完成AGPL对应源码公开提供的声明。
