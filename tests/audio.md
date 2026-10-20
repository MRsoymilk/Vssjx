# 技能音频与资源管理验证

2026-10-19，Godot4.7.2，原生音频与实际OpenGL资源管理界面。

- `res://tests/skill_audio_test.tscn`：11项、0失败。覆盖WAV时长、无效ID、本地／联网真实命中时机、普通攻击不误播、同修订刷新不重复、默认音量与离开停止。原始文件与正式WAV的SHA256一致。
- `res://tests/audio_browser_test.tscn`：实际渲染16项、0失败。覆盖音频索引、真实导入信息、试听、停止、定位、音量、搜索、切换清理、播完复位、存档不变及窗口布局。设置 `SSJX_AUDIO_BROWSER_CAPTURE` 为PNG绝对路径可保存截图，本次位于忽略目录 `work/audio-browser.png`。
- `res://tests/admin_scene_layout_test.tscn`：311项、0失败。
- 原有 `skill_effect_mapping_test.tscn` 为222项、8失败，集中于两项被动反射技能的层数与触发预期；在测试进程中去掉本次音频绑定后仍为相同8项失败，未调整不相关的技能语义或测试。

仅修改源码与正式资源；未重新导出、推送或部署Web／APK。现有构建包需要后续重新导出才包含声音。


## 背景音乐（2026-10-21）

`background_music_test.tscn` 实际OpenGL运行19项通过，音频管理22项、技能音效22项通过，编辑器导入与文件SHA256核对正常。覆盖约192.477秒原始OGG、-18dB默认音量、主场景单播放器、本地地图及战斗切换不重启、末尾实际循环、失焦／挂起暂停与恢复、初次启动未获焦点后恢复、网页首个交互启动分支、后续点击不重启、退出释放，以及试听不循环／不自动播放／切换停止。等待音频混音线程释放后退出无资源泄漏报告。

网页分支通过相同控制器的手势等待参数验证，没有执行Web导出或浏览器端发布验证。没有修改服务端或数据库，也未打包、推送或部署；现有已发布网页／APK需要后续导出更新。

```powershell
godot --path client --rendering-method gl_compatibility res://tests/background_music_test.tscn
godot --headless --path client res://tests/audio_browser_test.tscn
godot --headless --path client res://tests/skill_audio_test.tscn
```
