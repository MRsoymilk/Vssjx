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

## 明确限制

原客户端定时器周期尚未确认，沿用当前10fps攻击时钟与原始每步拍数。
原生多段事件完整保存，当前重建／服务端每行动只给一个伤害结果，不编造额外伤害。
法师施法暂用已核对举杖姿势的原生槽位8，但并未恢复其与原版技能ID的对应关系。
本轮不把重建技能、数值、单人战斗顺序宣称为完整原版规则。
