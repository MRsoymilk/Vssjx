# 法杖动作与招式气泡

## 运行

仓库根目录执行：

```sh
godot --headless --path client --import
python tests/run_battle_casting.py
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_battle_casting.py --render
python -m unittest discover -s tests -p 'test_*.py'
```

离屏需要Xvfb，可通过`XVFB_BIN`指定路径；`GODOT_BIN`指定Godot。截图和逐帧轨迹默认输出到`/tmp/opencode/vssjx-battle-casting`，可用`--output`更换。测试使用独立带进程ID的临时存档，恢复原内存角色和路径，不使用玩家存档或账号数据库。

## 验证范围

- 男女法师分别使用原ANI第4序列的朝左挥杖及第6序列的浮动法杖施法，不再复用朝右的最后一条序列；原素材与原始动画记录不改写。
- `attack`与`cast`均仅播放一次后回到待机，不改行走序列、移动相位或伤害/耗蓝规则；施法等待按真实6拍/8fps的0.75秒计算。
- 头顶黄底描边气泡显示当前已实现技能名；技能名和战斗日志共用同一来源，不将截图中未实现的技能冒充已经接入。
- 无效技能不显示气泡、不推进回合；动作中锁定重复提交，播放结束清理气泡，气泡不拦截点击、不遮挡底部日志。
- 实际引擎采样男女法师的普通攻击/施法共120张帧；同时检查SpriteFrames序号和人物/法杖区域的像素变化，不能用只变更帧号的headless结果代替渲染验证。
- 女法师原始普通攻击前3个组合帧内容相同，属于原素材的持势，而非播放卡住；普通攻击至少验证3种真实像素姿态，浮杖施法至少4种。

该项仅优化当前离线战斗呈现，不涉及线上角色、联机战斗或经济规则。

## 本轮结果（2026-10-15）

Godot 4.7.2、Xvfb、Mesa llvmpipe/OpenGL ES 3.2：headless 53项检查通过；真实离屏173项检查通过，120张实际渲染帧的像素变化检查通过。已查看男女法师施法中段截图，可见法杖浮动及头顶“摄灵诀”气泡。现有玩法379项、Python回归13项通过。

首轮像素验收对女法师普通攻击误要求4种不同像素帧；核对原图集后确认前3帧确为相同持势，修正为普通攻击至少3种、浮杖施法至少4种，并保留引擎实际推进至少4个序号的独立检查。复验通过，没有通过改写原始图像来凑帧。

截图/轨迹位于`/tmp/opencode/vssjx-battle-casting/`；例如`0_skill_11.png`、`1_skill_07.png`及`casting_trace.json`。运行时可用`XVFB_BIN=/tmp/opencode/vssjx-xvfb/usr/bin/Xvfb`和相应`LD_LIBRARY_PATH`使用本机离屏依赖；X11键盘映射/输入法警告不影响渲染，无GDScript错误。

## 招式气泡跟随（2026-10-16）

气泡此前只在出招时记录原站位，普攻接近目标后仍留在原处。现在使用弱引用绑定行动人物，按画布坐标持续更新气泡和尾尖；命中时同步更新，兼容缩放、镜像及不同父节点，保留原有高度、边缘限制和持续时间。收招、切换页面或人物释放时清除，不重复开始倒计时。

Windows / Godot 4.7.1：`battle_casting_test.tscn` 61 项、`native_battle_flow_test.tscn` 100 项、`test_runner.tscn` 385 项，均为 0 失败。包含六个人物命中位置跟随、反击前清除、取消清除、不同站位坐标转换、镜像文字方向、屏幕边缘与对象释放检查。

实际 OpenGL 战斗流程 103 项通过，已查看 `work/battle-layering/follow-callout-impact.png`，气泡位于普攻命中时的人物上方。截图在忽略目录，可通过以下命令重新生成：

```sh
godot --path client res://tests/native_battle_flow_test.tscn -- --capture-native-flow=/absolute/path/follow-callout
```

## 原地施法与飞行特效（2026-10-27）

- 力士雷霆一击、斗转星移：使用原包 native sequence 8 的转武器、举武器姿势，在原站位施放；举起后在敌方播放对应技能特效。
- 侠客仙人指路、沧海明月、剑飞惊天、万剑归宗：同样使用已核对的原包抬手动作；抬手后从自身向每个目标发出特效，0.28秒后到达目标才显示命中、伤害和受击动作。群攻每目标一条轨迹，同次施法只播放一次音效。
- 隐者全部主动技能保持原地施法；普通攻击及未指定的其他近战攻击沿用原移动规则。未改变伤害、消耗、熟练度或冷却规则。
- 原包所有男女角色已有 source sequence 8，运行时为缺少 `cast` 的力士、侠客建立动作别名，保留完整原始帧、纹理和相对帧时长；兼容换武器、衣服、头饰和双方朝向。原地动作不套普通攻击的目标位移。
- 飞行期间用原图第一帧的可见中心对齐人物手部至目标的路径，避免原ANI首帧偏移数百像素；到达后恢复原ANI偏移并完整播放。场景离开、断线或取消动作会清除轨迹，不产生延迟特效或伤害回调。
- 本地单人阵型、旧单怪本地路径、联机单怪／组队、决斗自己和对手使用同一动作选择与发射流程；原有1～5级基础特效及6/10/15级阶段资源不变。

验证：`stationary_skill_test.tscn` 实际OpenGL渲染2417项通过，覆盖男女、默认及换装、双方朝向、所有隐者主动技能、全部阶段、动作取消、实际组队群攻逐目标伤害及决斗对手施法。相关动作／资源／特效／技能／HUD／飘字／组队／决斗回归25840项通过，Python资源映射7项通过。实际截图已核对：`work/stationary-skill-captures/knight-raised-projectiles.png`、`knight-target-impact.png`、`lishi-raised-target-lightning.png`；原包姿势接触表为 `work/stationary-cast-source.png`。

旧 `battle_casting_test` 的“普通攻击不恢复灵力”断言在HEAD基线同样失败2处（日志 `work/stationary-battle-casting-baseline.log`），本次按现行技能费用与普攻回灵配置更新预期后61项全过，没有为测试改变战斗规则。未打包、推送或部署。
