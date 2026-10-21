# Godot原生人物／NPC／怪物资源迁移

> 当前人物结构已进一步收敛为六份基础场景，武器／衣服／头饰用`.tres`切换；66份固定换装及6份创建预览场景已移除。旧标识仍兼容，NPC／怪物场景不变。当前用法见 [六个基础人物场景](hero_base_scenes.md)，下文保留前两阶段迁移记录。

## 阶段一：原生场景和动画资源

235套资源全部生成独立可打开的 `.tscn`、真正的 `SpriteFrames.tres` 和轻量 `NativeActorDefinition.tres`。包括人物72套、NPC20套、怪物77套，以及创建界面、特效、场景物件等配套资源。原PNG未改动。

- 例：`client/scenes/actors/catalog/hero/mfs.tscn`、`npc/ssjx_baishouxian.tscn`、`monster/langw.tscn`。
- 动画及逐帧时长：`client/assets/actor_resources/<分类>/<名称>_frames.tres`，可在SpriteFrames编辑器调整。
- 帧尺寸、锚点及原战斗位移：相邻 `<名称>.tres`；纹理路径仅作准备阶段使用，不在枚举资源时加载图像。
- 场景均继承 `client/scenes/actors/native_actor.tscn`，直接实例化即可播放待机，并在攻击／施法／受击结束后回待机。
- 导入工具：`python tools/build_godot_actors.py`；只检查：追加 `--check`。当前工具默认只补缺失文件，发现已有原生文件与导入证据不同会拒绝覆盖；只有明确追加 `--force` 才重新生成。即使强制导入也不覆盖像素编辑器的原生修改清单。

阶段一保留旧运行入口作迁移前对照。4项Python专项通过；真实OpenGL ES离屏 **20,551项**对比通过，检查全部动画的纹理、帧区域、时长、循环、锚点，以及人物／NPC／怪物待机和攻击像素一致。截图：忽略目录 `work/native-actors/native-parity-{idle,attack}.png`，左旧、右新。

## 阶段二：运行入口、换装和编辑器切换

- `OriginalArt.actor()`现在真正实例化目录内的PackedScene，静态人物／NPC／怪物不再在运行时解析JSON或拼建SpriteFrames；旧入口名称、外观编码和对战接口保持兼容。选角页也实例化对应人物场景，不再只向空节点拷贝帧。
- 部件区块、六职业／性别配方及四个扩展外观系列均迁移到 `client/assets/appearance_resources/`。共390份 `NativeAppearancePart.tres`、6份 `NativeAppearanceRecipe.tres`，以及系列与索引Resource；原生和扩展武器、衣服、头饰仍可自由混搭，组合图集按需生成并继续限额缓存，不预制数千组合场景。
- 已保存的像素修改使用 `overrides.tres`，保留内容摘要PNG、外部修改指纹、历史备份和临时文件原子替换，不覆盖原图片。
- 元数据索引保存轻量资源路径，枚举不加载所有纹理。战斗准备异步加载实际纹理和PackedScene，使用混合Resource类型检查；取消、失败和联机续战行为保留。
- 直接打开场景仍会自动播放待机；由游戏工厂创建时关闭场景自动启动，避免覆盖调用方在入树前设置的暂停，保证逐帧检测和触摸命中稳定。
- 数据浏览器「素材／动画」链接到实际`.tscn`，人物、NPC、怪物可直接预览原生动作。原版未接入素材的档案JSON仍是取证材料，不冒充新增玩法。
- 四个导出预设排除旧 `actors.json`、角色分片、`hero-parts.json`、外观系列JSON及旧修改清单；数值、任务、掉落和网络世界定义继续保留JSON。只调整导出规则和审计脚本，此次没有实际打包。

### 在Godot里编辑

1. 打开 `client/project.godot`，在 `scenes/actors/catalog/{hero,npc,monster}/` 找到外观场景。
2. 选择根AnimatedSprite2D，打开SpriteFrames资源编辑动画帧、速度和循环；调整场景offset可更改整套静态外观的位置。元数据中保留的战斗位移／命中步与帧数有关，更改动作结构时需同步检查。
3. 动态换装部件在 `assets/appearance_resources/parts/`，配方在 `recipes/`；在Inspector调整区域、图层、位置和变换。动态组合继承六套基础动作，因此不是每个组合一份场景。
4. 原生资源是运行时实际读取对象，日常编辑不需要回写旧JSON，也不要运行强制导入覆盖自己的修改。`--check`是迁移证据比对，故意修改表现后出现差异不代表游戏仍在读取旧JSON。

同一外观场景可由多个NPC／怪物出生点复用；地图位置、名称、数值依然属于世界／战斗定义。若只想修改其中一个居民，应建立新外观场景及元数据，在原生 `catalog.tres` 登记路径，再给该居民独立外观编码，避免影响所有共用者。

### 验证

- 7项Python专项通过：确定性转换、真实SpriteFrames／场景、纯原生加载边界、导出排除和用户修改保护。
- 完整原生资源专项 **21,187项**通过，包含全部235套逐帧旧算法对照、390份部件及6套配方、实际工厂场景实例、像素一致性；不是把迁移后入口与自己比较。
- 编辑器／数据浏览器专项 **274项**通过；像素编辑器56项、外观组合6159项、六基础人物逐帧525项、三套扩展系列各486项、破天斧92项通过。
- 真实OpenGL采样 **1516项／1344次渲染对照**通过，覆盖左右朝向、小数像素位置及动态换装。实际NPC浏览器、主城、无尽战斗及像素编辑器截图已检查。
- 原联机PVE界面71项、遇敌准备143项（帧采样数量随运行时变化）、原生战斗位移276项、战斗流程100项、怪物攻击153项、AI怪物3482项、恢复NPC403项、血条定位54项、脚底圈279项、组队完整回合54项、普通单人55项、AI地图2075项通过；选角12项、界面场景110项、本地多角色27项、无尽78项、ROLL52项、资源接口42项及Web接口13项通过。
- 旧 `data_browser_test.tscn` 全量脚本未通过，其固定目录数量、旧图标及旧动作说明断言已落后于现有内容。本次另用迁移前目录实现对比，所有类别数量及预览身份一致（素材235、人物1145、怪物577），并用上述原生编辑器专项覆盖迁移路径；未为了消除旧断言而删减现有内容。

```sh
python tools/build_godot_actors.py --check
python -m unittest discover -s tests -p test_native_actor_resources.py
godot --headless --editor --path client --import
SSJX_NATIVE_ACTOR_CAPTURE="$PWD/work/native-actors" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/native_actor_resources_test.tscn
```

截图和日志保留在忽略目录 `work/native-actors/` 及 `/tmp/opencode/native-actors-*`。未推送、打包或部署；已有安装包不会自动更新。
