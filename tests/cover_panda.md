# 封面熊猫（2026-10-23）

## 素材与交互

- 原始证据为 `analysis/unpacked/ssjx/zairu.ani` 和已解码的 `load00`～`load05`。`tools/build_cover_panda.py` 复用原生ANI解析、变换和合成逻辑，保留18个合成帧与4条原始序列，输出 `client/assets/ui/cover_panda.png` 和 `cover_panda_frames.tres`。
- 遵循ANI帧表和序列表倒序寻址；默认显示未经变换的 `load00`（序列化帧14）。点击播放原生序列2：`load05 → load01 → load02 → load03 → load03+load04 → load03 → load02 → load01 → load05`，然后恢复默认姿态。
- 保留原始层坐标、镜像、叠层与每帧1／2 tick权重；沿用客户端原生动画的10 tick/s播放约定，回头动作共1.1秒。封面点击与自动恢复是本次新增交互。
- 封面左下角落点为 `(40,468)`，共同图集原点 `(-12,-24)`；使用2倍整数最近邻缩放。透明按钮范围 `(12,412,56,60)`，右侧菜单独立。播放中再次点击不重启动作；打开登录或退出确认会复位并禁用熊猫，返回封面后可再次点击。
- 运行时直接加载Godot原生 `SpriteFrames`，场景位置／缩放可在 `client/scenes/ui/original_cover.tscn` 调整。

## 验证

```sh
python3 -B tools/build_cover_panda.py
python3 -B tools/build_cover_panda.py --check
godot --headless --path client res://tests/login_ui_test.tscn
```

- 资源重建校验18帧、4条原生序列，0处过期；Godot资源导入成功。
- 既有登录／退出界面回归59项、0失败。
- 实际OpenGL窗口通过鼠标事件点击熊猫，截图查看默认姿态、回头过程、自动复位、连续点击、登录／返回、退出确认及返回后再点击。日志记录原生动作逐帧推进，菜单非活动期间不触发播放。
- 图片：`/tmp/opencode/cover-panda-sequence.png`、`/tmp/opencode/cover-panda-preview/`；运行日志：`/tmp/opencode/cover-panda-preview.log`、`/tmp/opencode/cover-panda-login.log`。
- 退出时仍有既有的4个音频对象／1个资源清理报告；verbose定位为 `background.ogg` 的Ogg播放对象，没有熊猫节点或资源泄漏记录。
