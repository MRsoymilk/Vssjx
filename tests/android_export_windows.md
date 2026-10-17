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
