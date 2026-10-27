# 玄锋行装

[返回设计索引](README.md) · [商城规则](shop_catalog.md) · [装备美术规范](ai-equipment-style-spec.md) · [验收记录](../tests/xuanfeng_equipment.md)

性质：**已接入源码的新增六角色装备**。2026-10-27完成商城、独立换装、本地存档及联机接入。本轮未推送、打包或部署，已有安装包和线上服务不会自动获得这些资源。

## 成品与范围

采用黑银衣装、暗红束带、金属饰边与晶石法器。六角色保持原生人形比例，开面／半覆面硬盔保留脸部、眼睛和下发连接，不增加机械躯干、长硬颈或尖下巴。

| 人物 | 套装 | 武器 | 武器／衣服／头部编码 |
|---|---|---|---|
| 力士男 | 玄锋·破阵 | 玄锋阔刃 | 53 / 36 / 34 |
| 力士女 | 玄锋·斩月 | 玄锋钩刃 | 54 / 37 / 35 |
| 侠客男 | 玄锋·逐影 | 玄锋双刃 | 55 / 38 / 36 |
| 侠客女 | 玄锋·流萤 | 玄锋反握刃 | 56 / 39 / 37 |
| 隐者男 | 玄锋·观星 | 玄晶灵杖 | 57 / 40 / 38 |
| 隐者女 | 玄锋·照夜 | 照夜晶杖 | 58 / 41 / 39 |

30张原生部件图集与60张32×32独立图标覆盖三职业男女六套。六张80×80成品母版只登记最终设计，不是动画图集；生产按原生配方回投到头部、躯干、前后层和武器，复合姿势按原生躯干适配，不缩放整张人物图制作动作。待机、行走、攻击、受击及隐者施法复用完整原生时序、旋转、握持和战斗锚点；不为其他职业虚构原版没有的施法动作。

## 游戏入口与规则

- 菜单 → 商城 → 热卖／奇珍 → **玄锋行装 · 本角色**，每个角色显示对应十件装备。管理工具“装备外观”搜索 `ai/xuanfeng/`，支持单件／整套对照。
- 物品ID：`ai/xuanfeng/<mzs,wzs,mck,wck,mfs,wfs>/<slot>`；完整外观示例：`hero/mzs_w53_c36_h34`。
- 武器140铜钱、攻击+14；其余九件各70铜钱、防御+3。全套770铜钱，合计攻击+14／防御+27，一级可用，严格限制职业与性别，无额外套装技能。
- **仅武器、衣服、头部独立改变人物外观**，可与原版及其他系列混穿。衣服包含配套裤靴视觉，其余七槽只提供图标及属性，不宣称单独装备鞋子或戒指会改变人物样式。
- 本地购买与穿戴保存成功后生效，重读恢复；联机由服务端确认目录、价格、属性和穿戴限制，三段外观用于广播及重连。客户端不提交可信的自定义价格或外观编码。

## 资源与维护

| 路径 | 用途 |
|---|---|
| `tools/build_xuanfeng_equipment.py`、`tools/xuanfeng_native_style.py` | Pillow确定性部件生产、脸区保护、衣装姿势和握持适配，无新增运行时绘图依赖 |
| `analysis/ai-generated/equipment/xuanfeng/` | 最终母版、原生输入与产物摘要、生产说明 |
| `client/assets/data/xuanfeng-equipment.json` | 六套编码、职业／性别和30份部件映射 |
| `client/assets/generated/equipment/xuanfeng/` | 正式PNG部件和图标 |
| `client/assets/appearance_resources/families/xuanfeng.tres` | Godot原生系列入口，关联部件及单槽外观资源 |
| `server/migrations/0044_xuanfeng_equipment.sql` | 新增60物品白名单及十槽映射，保留旧库存和已有约束 |

```sh
python tools/build_xuanfeng_equipment.py --check
python tools/build_full_shop_catalog.py
python tools/build_godot_actors.py --check
python tools/build_xuanfeng_migration.py --check
```

原生资源转换只在需要导入时使用 `tools/build_godot_actors.py --force`，避免覆盖其他人工编辑。商城当前共519项；服务端二进制内嵌商城目录，需与客户端及完整数据库迁移集配套更新。不得重写历史迁移。

新增像素成品与原包底层素材的来源边界见[生产记录](../analysis/ai-generated/equipment/xuanfeng/README.md)及[资源来源说明](../docs/asset-provenance.md)，不将新增装备当作原版恢复或授权证明。实际验证、命令及未验收平台见[验收记录](../tests/xuanfeng_equipment.md)。
