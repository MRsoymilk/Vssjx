# 原版角色死亡动画

使用管理页资源标识 `archive/ssjx.mrp/death.ani` 对应的原包成员 `analysis/unpacked/ssjx/death.ani`，SHA-256：`562282d1e248b01b7a894cce0188702ca893901491e7970fbdd0ec3fe65cc01a`。

资源原有 `txms` 墓碑与 `txy01` 烟雾，共 10 个合成帧、1 条序列。运行时新增 `main/death` 图集和独立元数据，不引用仅供管理页使用的资源。保留图层位移、镜像与停留 tick；遵循已验证的 ANI 反向帧表读取，按原版序列从烟雾播到墓碑。沿用项目 ANI 每 tick 0.1 秒的播放速率，总长 1 秒，结束后停在墓碑帧。

反编译证据：`analysis/disasm/gameonline_functions.asm` 的 `0x2814..0x281e` 加载 `death` 并存入 `SB+0xc0`；`0x494e..0x495a` 从该资源创建每角色实例并存入角色 `+0x2c`。帧表反向读取及序列解引用沿用 `tools/native_ani.py` 对 `0x22d74 / 0x22fc8` 的恢复结果。当前接入在敌方动作结束回位后播放死亡；这属于现有回合流程的呈现接入，不声称已完整恢复原客户端死亡状态机。

- 本地：致命受击先显示原有 hurt，敌方完成回位后隐藏角色、血条、灵力条、状态字和脚下环，播放完整死亡序列，再执行已有失败恢复、存档及结算页。动画不修改战斗数值。
- 联机：根据权威 battle HP=0 和 defeat 播放相同序列，完成前不能返回地图；重复快照不重播，断线取消后可按同一快照重建。角色账户已恢复的 HP 不覆盖死亡过程中的显示。
- 切场景、退出、返回地图或更换战斗时，清除墓碑并取消等待；不会继续结算已放弃的本地战斗。胜利、撤退和普通受击不触发死亡。
- 本地与联机遇敌资源准备均包含死亡资源。不改管理页，不改变服务器规则。

## 验证（Windows / Godot 4.7.1）

```powershell
godot --headless --path client res://tests/battle_death_test.tscn
godot --path client --rendering-driver opengl3 res://tests/battle_death_test.tscn -- --capture-death=F:/project/Vssjx/work/battle-death/death
python -m unittest discover -s tests -p test_actor_catalog.py
python -m unittest discover -s tests -p test_actor_import.py
```

死亡测试：无头 23 项，实际渲染 26 项通过；包含完整死亡、结算等待、最后一帧保留、角色站位、原版帧表顺序、隐藏光环、重复快照、断线重连及取消后不结算。实际渲染截图检查了本地烟雾、本地结算和联机烟雾。

相关回归：资源目录 51、四种怪物反应 102、原版战斗流程 100、角色脚下环 279、遇敌资源准备 131、联机 PVE 界面 59 项通过。素材 Python 测试同时保留旧资源完整性与新资源可重复生成检查；旧目录基线补入此前脚下环功能已增加的 walking anchor。

按用户要求，本次不导出、不打包、不更新网页部署。
