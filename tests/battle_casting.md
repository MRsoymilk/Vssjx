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
