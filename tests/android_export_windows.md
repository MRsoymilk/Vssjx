# Windows 导出 Android APK（2026-10-17）

游戏源码为 `0be5ad5`，包含人物与怪物的原版死亡动画和墓碑。本轮修正 `tools/export_native.py` 在 Windows 下的工具扩展名、隔离的 APPDATA/LOCALAPPDATA 路径，以及开发签名目录的 NTFS 权限处理。Linux 原有权限检查保留。签名目录先检查是否属于本工具，再处理权限；拒绝覆盖无关文件。

构建工具使用官方 Godot 4.7.2 与匹配的 Android 模板、Microsoft OpenJDK 17、Android build-tools 36.0.0 和 platform-tools。工具链位于忽略目录 `work/android-toolchain/`，不纳入 Git。开发测试签名保存在仓库外，后续更新包复用相同密钥，不打入 APK 或分发目录。

本机构建命令（新的一次构建需换用空输出目录）：

```powershell
$env:GODOT_BIN = 'F:/project/Vssjx/work/web-toolchain/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe'
$env:JAVA_HOME = 'F:/project/Vssjx/work/android-toolchain/java/jdk-17.0.20.1+1'
$env:PATH = "$env:JAVA_HOME/bin;$env:PATH"
python -X utf8 tools/export_native.py --target android --output work/builds/android-20261017-0be5ad5 --templates work/android-toolchain/templates --android-sdk work/android-toolchain/sdk --java-sdk "$env:JAVA_HOME" --development-signing --development-key-dir 'C:/Users/milk/AppData/Local/VssjxBuild/development-signing'
```

产物 `work/builds/android-20261017-0be5ad5/dist/vssjx-android-preview.apk`：

- 68,567,980 字节，SHA-256：`b4ef4b1f024957d723ed08bf8fb817a9bd21d1c368447afd93d6fbc9349b896d`。
- 包名 `com.mrsoymilk.vssjx.preview`，版本 `0.1.0-preview`，ARM32 / ARM64，最低 Android API 24（Android 7.0），目标 API 36。
- Release 导出，开发测试证书签名；非 debuggable，APK v2/v3 签名验证、16 KB 对齐及原生库 ELF 对齐检查通过。
- 仅申请 INTERNET 权限，关闭备份；CRC、动态 JSON、中文字体、许可证和管理页／测试／私有文件排除检查通过。
- 从 APK 实际 assets 提取后，使用桌面 Godot 进行包内主场景与接口检查：71 项通过。这不是 Android 设备执行测试；本次未完成真机或模拟器运行验收。
- Android 配置、私有文件排除、ARM64 对齐拒绝错误输入、导出器不修改 Git 的 4 项 Python 检查通过。

日志、源码哈希和签名证书摘要保留在同级 `build-report.json` 与各步骤日志。构建时仅打包工具存在未提交的 Windows 兼容修改，游戏目录与上述提交一致；没有推送远端或更新网页部署。

## 蓝叠 x86 启动修正

原 ARM 包在本机 BlueStacks Nougat32（Android 7.1.1，ABI `x86,armeabi-v7a,armeabi`）上选择了 `armeabi-v7a`，在进入 Godot 主循环之前报 `java.lang.UnsatisfiedLinkError: undefined symbol: _ZN8AObbInfoD2Ev`，重复崩溃并停留在启动图。该符号不在四套 Godot 模板原生库的符号字符串中；不据此判断 ARM 真机也会失败。

新增 `--android-emulator`，在隔离导出配置里同时加入 x86 / x86_64，保留 ARM32 / ARM64；默认手机导出配置不变。原生库校验增加两种 x86 ELF class / machine 检查，继续验证 64 位库的 16 KB 对齐。复用相同开发签名及包名，可覆盖安装。

在上述构建命令追加 `--android-emulator`，改输出为 `work/builds/android-universal-20261017-1a1e29c`。产物 `dist/vssjx-android-preview-universal.apk`，121,042,128 字节；签名、四种 ABI、ZIP CRC、16 KB 对齐、权限及包内资源 71 项检查通过。相关 Python 检查增加至 5 项。

本机模拟器实际验证：

- 使用 `adb install -r` 覆盖安装，未卸载或清除数据，安装结果 Success。
- 系统选择 `primaryCpuAbi=x86`；Godot 原生层初始化、OpenGL ES 3.0 与主循环启动成功。
- 实际截图确认进入游戏封面，并点击进入登陆游戏页；进程保持存活，没有原生链接错误、FATAL EXCEPTION 或 SCRIPT ERROR。
- 未修改蓝叠图形配置或重启模拟器；未进行账号登陆、联机、战斗或 ARM 真机运行验证。

日志与截图在忽略目录 `work/android-emulator/`。模拟器执行结果独立记在构建目录的 `emulator-verification.json`；`build-report.json` 中的 `actual_android_execution=false` 仍表示导出器本身不执行设备测试。
