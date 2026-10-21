# 六个基础人物场景＋装备Resource

## 当前结构

`client/scenes/actors/catalog/hero/` 只保留六份人物场景：

```
mzs.tscn  wzs.tscn   # 男／女力士
mck.tscn  wck.tscn   # 男／女侠客
mfs.tscn  wfs.tscn   # 男／女隐者
```

删除了66份固定换装场景、6份独立创建预览场景以及它们72份重复SpriteFrames文件。删除前逐一比对它们仍是原生成文件，未覆盖或删除其他工作。NPC、怪物场景及PNG图像保持不变。

235个已有素材标识仍全部保留：旧的 `hero/mck_w0_c0`、显式 `_h0`、完整换装编码以及 `creation/mck` 等由兼容入口解析成基础人物场景和装备Resource，无需改写玩家存档、服务器外观编码或数值规则。原始轻量元数据仍可用于取证／对照，不再对应独立换装场景。

## Godot Inspector用法

1. 打开例如 `hero/mck.tscn`，选择根节点的 **Outfit**（`NativeHeroOutfit`）。
2. 如只修改这个实例，先对Outfit执行 **Make Unique**／另存为新的`.tres`，避免修改所有共用此预设的实例。
3. 三个字段分别选择 `NativeHeroEquipment.tres`：
   - `assets/appearance_resources/equipment/mck/weapon/0.tres`：空手；`1.tres`、`2.tres`等为武器样式。
   - `.../mck/clothing/0.tres`：默认衣服；其他编号切换身体及前后衣层。
   - `.../mck/head/0.tres`：默认头饰；其他编号切换头部及发尾。
4. 更换字段或修改嵌套部件Resource会发出`changed`并刷新当前人物，不需要创建新场景。完整Outfit可用ResourceSaver保存、重新载入。

日常游戏中仍以角色实际穿戴装备决定使用哪些样式Resource；Inspector设置的是独立场景／实例的外观预设，不能绕过联机装备权限或改变装备属性。要修改某个已装备样式的图像或区域，应编辑其对应的部件Resource，而不是随意更改用于兼容存档的`Visual Code`。

每种样式有独立性别／职业和槽位约束，不能把女隐者的武器Resource误塞给男侠客。基础动作配方仍取自原资源；创建页的男／女力士保留原本2号斧头预览，但现在以`outfits/creation_{mzs,wzs}.tres`表达，不再各占一份场景。

原始默认预设通过内容签名复用现有SpriteFrames；改动默认部件的Resource配置会使签名失效，自动重新组合，不会被旧图集遮住。现有样式共344份装备Resource，任意三部位组合仍按需解析。装备配置、组合图集和动态SpriteFrames继续限额缓存，避免为任意组合预制文件。导入工具已同步，不会重新生成被移除的组合场景；强制重新导入仍需显式`--force`，像素编辑器覆盖清单始终保留。

## 验证与边界

记录及截图位于忽略目录 `work/hero-base-scenes/`、`/tmp/opencode/hero-base-*`。专项覆盖Inspector资源字段、同一节点三部位切换、嵌套部件修改、`.tres`保存重读、旧编码、创建预览、非法跨职业资源、缓存限额，以及235个旧标识的全部动画与原像素／时长对比。

- Python9项通过，核实磁盘和生成器都只保留六份基础人物场景，旧组合文件不会被重建。
- 基础场景专项88项、完整原生资源对照21,265项通过。后者另验证78个旧人物／创建标识的战斗根位移、命中步和受击偏移一致，避免动态组合后重复叠加攻击偏移。
- 实际OpenGL采样1516项／1344次渲染对照通过；六个人物资源切换、原／新攻击对照截图已检查。
- 外观组合6159项、基础人物逐帧525项、三套扩展系列各486项、破天斧92项、像素编辑器52项、原生资源浏览器274项通过。
- 联机PVE界面71项、遇敌准备143项、战斗位移276项、完整流程100项、血条定位54项、脚底圈279项、恢复NPC403项、AI怪物3482项、选角12项、本地多角色27项、普通单人55项、组队回合54项、无尽75项通过。脚底圈测试的旧联机夹具补齐了缺失的`school`字段，消除原有脚本异常；未改玩法规则。部分原战斗测试退出时仍报告既有资源清理告警，断言无失败。
- 编辑器导入、实际以Godot编辑器打开`mck.tscn`、`git diff --check`及生成器`--check`通过。没有执行打包或服务部署。

```sh
python tools/build_godot_actors.py --check
python -m unittest discover -s tests -p test_native_actor_resources.py
godot --headless --editor --path client --import
SSJX_HERO_BASE_CAPTURE="$PWD/work/hero-base-scenes" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/hero_base_scene_test.tscn
```

没有修改服务端、数值、存档或世界NPC／怪物定义；未推送、打包或部署。
