# Godot原生人物／NPC／怪物资源迁移

## 阶段一：原生场景和动画资源

235套资源全部生成独立可打开的 `.tscn`、真正的 `SpriteFrames.tres` 和轻量 `NativeActorDefinition.tres`。包括人物72套、NPC20套、怪物77套，以及创建界面、特效、场景物件等配套资源。原PNG未改动。

- 例：`client/scenes/actors/catalog/hero/mfs.tscn`、`npc/ssjx_baishouxian.tscn`、`monster/langw.tscn`。
- 动画及逐帧时长：`client/assets/actor_resources/<分类>/<名称>_frames.tres`，可在SpriteFrames编辑器调整。
- 帧尺寸、锚点及原战斗位移：相邻 `<名称>.tres`；纹理路径仅作准备阶段使用，不在枚举资源时加载图像。
- 场景均继承 `client/scenes/actors/native_actor.tscn`，直接实例化即可播放待机，并在攻击／施法／受击结束后回待机。
- 导入工具：`python tools/build_godot_actors.py`；只检查：追加 `--check`。这是显式重建操作，会重新生成所属文件；手工修改原生资源后不要不加区分地重建覆盖。

阶段一保留旧运行入口作迁移前对照。4项Python专项通过；真实OpenGL ES离屏 **20,551项**对比通过，检查全部动画的纹理、帧区域、时长、循环、锚点，以及人物／NPC／怪物待机和攻击像素一致。截图：忽略目录 `work/native-actors/native-parity-{idle,attack}.png`，左旧、右新。

未推送、打包或部署。
