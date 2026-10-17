# Linux x86_64 原生便携包

在既有独立worktree和本地`feature/native-apk-exe`分支上加入Linux，不合并/推送共享`dev`，不覆盖此前已交付的APK和EXE。使用同一游戏、v1存档、线上协议和原生平台接口。

## 产物与运行

- `vssjx-linux-x64-preview.tar.gz`：解压后得到`vssjx-linux-x64/`，运行`./vssjx.x86_64`。
- release模式、ELF64 x86_64、PCK内嵌；无需Godot编辑器、额外PCK、FUSE、root安装或在线下载游戏资源。**不是AppImage、deb/rpm或ARM64包**。
- 依赖glibc **2.28+**以及可用的OpenGL 3.3桌面/驱动（或Godot支持的GLES 3兼容路径）；不适用于原生musl/Alpine。具体发行版、Wayland/XWayland、实体GPU及性能矩阵仍需验收。
- 归档保留可执行权限755，文档/许可644；不记录构建机用户名/组名。如果传输损失权限，执行`chmod +x vssjx.x86_64`。
- 存档和连接偏好使用系统XDG用户目录（默认`~/.local/share/godot/app_userdata/蜀山剑侠 · 归来/`），不是程序目录。删除解压目录不自动清除进度；删除应用用户数据会丢离线进度。不会导入Web槽或把离线角色导入线上。
- 离线体验：封面登陆后，服务器地址填`local`；联机填写合法HTTPS游戏服务地址。原生可编辑地址，但不会因此关闭TLS校验或放松账号/会话规则。

```sh
tar -xzf vssjx-linux-x64-preview.tar.gz
cd vssjx-linux-x64
./vssjx.x86_64
```

附带字体OFL、项目AGPL、Godot组件许可和对应代码提交说明；正式向外分发前仍须安排完整对应源码提供和原始美术授权核实。预览归档不是已完成全部发行门槛的声明。

## 构建

```sh
python3 tools/export_native.py --target linux \
  --linux-template /path/to/linux_release.x86_64 \
  --output /tmp/opencode/vssjx-linux-build
```

只构建Linux不需要Android SDK、JDK、签名证书或Windows模板。`--target all`现包含Linux、Windows、Android；Android仍须显式选择开发签名或外部正式签名。

使用官方Godot **4.7.2** release Linux x86_64模板，固定SHA-256：`d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63`。来源为官方发布tpz内`templates/linux_release.x86_64`，HTTPS范围提取并验证成员CRC，未声称核验整个tpz摘要。

沿用只复制公开客户端、排除admin/tests/隐藏配置/密钥、隔离XDG、拒绝覆盖既有dist及按提交/源文件/模板/产物记录摘要的策略。**仅`dist/`可交付**，不能分发父目录的源副本、测试profile和日志。

Linux导出预设独立增加`bundled_cjk`特性，只在发行包启用中文回退；不全局改变Linux开发工程的系统字体度量。即使机器没有中文系统字体，也有随包字体可用。没有修改玩法或存档schema。

## 验证及边界

构建器执行真实Linux导出、ELF架构/权限检查、内嵌资源70项审计、**直接执行产物自身**的版本检查和headless主场景启动，并从ELF符号版本记录glibc最低要求。资源审计使用Linux编辑器读取包，不能把它单独记作release进程的图形执行。

`tests/run_linux_release.py`进一步在自己拥有的Xvfb显示上启动真正release ELF，通过XTest发鼠标/键盘操作。它不使用编辑器进程、不注入Game API、不替换Platform、不把测试脚本打入产品，也不读取用户桌面/真实存档。使用独立XDG和空系统字体配置，截图、存档观察及结果只写测试输出。

```sh
python3 tests/run_linux_release.py \
  --executable /path/to/dist/linux-x64/vssjx.x86_64 \
  --output /tmp/opencode/vssjx-linux-gui-check \
  --xvfb /path/to/Xvfb
```

需要Xvfb、X11/XTest共享库、ImageMagick `import`及Pillow。自动化选择Mesa软件OpenGLES渲染，不是实体GPU/Wayland或所有Linux发行版验收；ASCII按键不是系统中文输入法证明。测试只观察实际v1文件，不修改存档来伪造进度，亦不接触真实账号。

## 本轮结果

- 真实Linux release导出、ELF/权限、内嵌PCK **70项审计**、产物自身`--version`和headless启动通过；ELF最大所需glibc符号版本为 **2.28**。预提交记录`/tmp/opencode/vssjx-linux-preview-first/`明确标记工作树有改动，不冒充来自旧提交的完整代码。
- 真正release ELF的隔离X11图形闭环 **22项通过**，包括v1创建、NPC任务、按键移动、山狼战斗和单次奖励、标准窗口关闭、重启新进程后读回并继续移动；保存仅由游戏产生。截图11张，记录`/tmp/opencode/vssjx-linux-release-ui-third/`，已检查中文界面及战斗/恢复画面，不用headless检查冒充渲染。
- 打包/安全单元测试 **13项通过**；平台边界 **15项通过**；导出排除/字体许可规则 **4项通过**。
- `--target all`完整构建通过，Linux/Windows/APK实际资源分别 **70项审计通过**，APK签名/权限/ZIP与ARM64段对齐检查继续通过。回归产物仅在`/tmp/opencode/vssjx-linux-all-target-regression/`，不替换已交付的APK和EXE。
- 之前已在基线复现的actor摘要、monster再生成及PVE测试PNG三项Python问题不在本单元修改范围，见[原生记录](native_packages.md)。未改动共享资源来隐藏它们。
