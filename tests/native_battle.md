# 按原客户端恢复战斗动作

原始依据为SHA256固定的v48 `analysis/unpacked/ssjx/gameonline.ext`，仅读取与静态反汇编。
证据、地址、函数片段及限制保存在 `analysis/recovery/battle/native_action_evidence.json` 和 `.asm`。

## ANI解释阶段

- 22d74倒序存入帧表和序列表；22fc8通过原生索引取帧。
- 245c0分派共通战斗槽位：4待机、5普攻、6受击。
- 24636将目标逻辑位置复制到攻击者绘制位置；2ee00明确为r0源、r1目标的坐标复制。
- 22b78/27874/27850读取BE32命中位表；22aa8在对应序列步骤的首拍触发；39d0投递动作事件。
- 2c24与2ea4在结束时将逻辑原位复制回绘制位置并切回待机。
- 例如侠客普攻帧为80,79,78,77,76,75,74,73,72，命中位为步骤2；
  山狼咬击帧为11,10,9,8,7,6,5,10,11，命中位为步骤3，受击为4,3,2,1,0。
  原先把0～5号行走姿势当成部分角色普攻、把咬击星形当作受击的解释已纠正。

原始ANI解析JSON、原始图集不变。16项角色／预览／怪物元数据恢复原生槽位，
保留攻击身体中心轨迹与全部命中事件位；运行时原始序列、原包预览及特效也按正确帧表解释。
有明确战斗槽位的原包怪物显示待机／普攻／受击，其他用途继续标记未确认。

```text
python tools/recover_native_battle.py
python tools/recover_native_battle.py --capstone-path /path/to/capstone
python tools/audit_monster_animations.py
python -m unittest discover -s tests -p "test_native_battle_ani.py"
python -m unittest discover -s tests -p "test_actor*.py"
python -m unittest discover -s tests -p "test_monster*.py"
godot --headless --path client res://tests/actor_catalog_test.tscn
godot --headless --path client res://tests/data_browser_test.tscn
```

2026-10-16，Windows/Python3.11/Godot4.7.1：原生证据4项、角色15项、怪物8项通过；
演员分片50项、管理页10316项通过。原始归档层／序列哈希保持不变。

## 战斗播放阶段

`BattleActionPlayback`使用已恢复的目标基点、逐步身体中心及命中事件位，控制整段普攻；
不额外编造飞行轨迹或把原始动作拆成固定距离的缓动。结束／取消时精确恢复原位和待机。
镜像侧使用实际变换基向量的符号，避免Godot的global_scale分解把负X翻转为负Y，导致怪物再次向外退。

离线战斗在命中事件才结算伤害、受击和命中特效；先完成我方收招再开始敌方动作，
敌方归位后进入回合结算。联机显示同样按这些时刻应用服务端已有血量结果，不修改服务端数值。
致命反击、力士防御反震取胜仍播放敌方最后一击，之后才显示结果；主动逃跑不伪造攻击。
普攻期间按原绘制分支隐藏攻击者原位的头顶血条与选择圈，归位后恢复。
切换场景或断线会取消位移与待结算表现；离线等待通过UI epoch拒绝已放弃的命中回调。

```text
godot --headless --path client res://tests/native_battle_motion_test.tscn
godot --headless --path client res://tests/native_battle_flow_test.tscn
godot --headless --path client res://tests/wolf_reaction_test.tscn
godot --headless --path client res://tests/online_pve_test.tscn
godot --headless --path client res://tests/battle_casting_test.tscn
godot --headless --path client res://tests/test_runner.tscn
godot --path client res://tests/native_battle_flow_test.tscn -- --capture-native-flow=/absolute/path/native-combat
```

2026-10-16 Windows/Godot4.7.1：10种游戏演员、双侧方向的逐帧轨迹／命中／归位201项；
6个人物实际离线流程及取消57项；4组怪物联机时序／致命反击／反震70项；联网界面28项；
施法53项；完整玩法385项通过。实际OpenGL流程59项通过，已查看接近命中及归位截图。
完整玩法测试由硬编码0.8秒等待调整为实际动画时长，伤害断言改为等待原生命中事件；
另外检查潜在致命攻击在命中之前不能提前进入胜利结算。

## 原版队伍绘制顺序与受击偏移

原包中 `36fc..370e` 通过 `4914` 为两队写入 `actor+51` 的阵营标志；
`2f28..2f40` 将当前行动方选为全局绘制列表 `+48`，另一方为 `+4c`。
`3174..317e` 先绘制 `+4c`、后绘制 `+48`，`394a..3954` 的更新入口顺序相同。
因此当前行动方处于前景。`2c24/2ea4` 收招归位不会重置这两张列表，下一次行动才切换。
这些片段与逐段 SHA-256 已加入同一份 `native_action_evidence.json/.asm`，Python 用例另对关键机器字作独立断言。

运行时在双方共同父节点下只调整演员分支顺序，血条、伤害数字、招式与特效仍在其上方；
离线直接演员节点和联机站位节点都使用同一规则。取消未完成动作时回退被中断的绘制次序。

现有行走图集逐帧消除了头部／主身体中心的水平偏移，受击姿势也受此影响。
`native_battle.pose_x` 从原始 ANI 提取待机和受击中心，战斗演员按实际帧恢复到 `offset.x`，
保留逻辑站位，世界行走和管理页预览沿用稳定图集。女侠客原始受击中心为 `4,6,7,8,9`，
山狼为 `3,4,5,6,7`；不编造额外避让距离。原始 ANI、PNG 图集以及既有普攻逐帧轨迹不变。

新增截图参数：

```text
godot --path client res://tests/wolf_reaction_test.tscn -- --capture-battle-layers=/absolute/path/native
```

2026-10-16 Windows/Godot 4.7.1：原始证据 6 项、角色 15 项、怪物 8 项通过；
逐帧位移／原生受击偏移／双层节点与取消 276 项，实际离线流程 87 项、四种怪物联机反应 98 项，
联网界面 28 项、施法 53 项、完整玩法 385 项、演员分片 50 项通过。
实际 OpenGL 离线 90 项、联机 100 项通过，已查看双方命中截图。
本机截图在忽略目录 `work/battle-layering/native-*`，此前错误的受击方前置截图不作为验收依据。

## 原版人物脚环（2026-10-17）

原包 `2e544..2e56a` 加载 `dongtai%d` 并存入 `SB+a38`；`2bb54..2bb5e` 在地图角色坐标绘制，
`2d98..2db8` 在战斗角色前一层绘制，并在普攻等动作状态跳过。三段证据已加入同一份静态恢复记录。
蓝色脚环使用 `dongtai1.ani` 的 `dttx0.imgs`，30×16 像素、原点 `(-15,-10)`，
按原生帧表的 `[3,2,1,0]` 循环。直接恢复像素，替换自绘圆弧与 SVG；
原包另有橙色版本，但 `heroData+0d` 选择字段的游戏含义尚未确认，因此沿用用户提供的蓝色参考，不猜测门派或性别配色。

单机、联机地图均为自己的角色添加脚环；其位置随站立／移动更新，绘制在人物下方，
转向和人物缩放不改变圆环像素。战斗沿用当前原版普攻期间隐藏、归位后显示的规则。
移动目的地标记保持独立，其他玩家、NPC 和怪物不会获得自己的角色标记。

```text
python -c "from tools.import_assets import bake_player_ring; bake_player_ring()"
python -m unittest discover -s tests -p test_native_battle_ani.py
godot --headless --path client --editor --import --quit
godot --headless --path client res://tests/player_ring_test.tscn
godot --path client res://tests/player_ring_test.tscn -- --capture-rings=/absolute/path/screenshots
```

Windows/Godot 4.7.1：脚环专项 169 项、真实 OpenGL 172 项、行走回归 6018 项、原生战斗流程 100 项、
怪物反应 98 项、共享界面 28 项、完整玩法 385 项通过；原包证据与脚环逐像素检查 7 项、游戏导出策略 4 项通过。
已查看单机地图、战斗和联机地图截图，本机结果保存在忽略目录 `work/player-ring/`。

### 脚圈中心校正（2026-10-17）

地图图集为消除左右摇摆，按原 ANI 的头部中心减去了横向偏移；脚圈先前只跟随逻辑坐标，因此没有同步这层变换。现在从原始 ANI 导出站立 / 行走的 `pose_x`，脚圈在对应可见人物坐标系中减去同样的偏移，再转换为全局位置。女隐者站立为4像素、行走为2像素；其他五种角色各自读取对应原始数据，不能统一硬移几像素。

联机人物的朝向在容器内的 `AnimatedSprite2D` 上变化，因此脚圈绑定可见人物，包含其镜像变换，而不只跟随外层容器。脚圈自身保持正向和原像素大小。战斗人物已恢复原始 ANI 位移，明确跳过地图补偿，避免重复偏移。原始脚圈图片、帧序和 `(-15,-10)` 原点保持原样。

Windows / Godot 4.7.1：脚圈专项279项、真实 OpenGL 282项、六角色移动6018项、原生战斗流程100项、模式隔离1048项、角色目录50项、完整玩法386项通过；Python 原包 / 脚圈检查8项通过。已查看本地地图、联机地图与战斗截图，结果位于忽略目录 `work/player-ring-centering/`。

## 明确限制

原客户端定时器周期尚未确认，沿用当前10fps攻击时钟与原始每步拍数。
原生多段事件完整保存，当前重建／服务端每行动只给一个伤害结果，不编造额外伤害。
法师施法暂用已核对举杖姿势的原生槽位8，但并未恢复其与原版技能ID的对应关系。
本轮不把重建技能、数值、单人战斗顺序宣称为完整原版规则。
