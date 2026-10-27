# 玄锋行装生产资源

六角色黑银行装，采用开面／半覆面硬盔、原生人脸、暗红束带和晶石法器。新增内容为像素绘制与原生部件适配，不是原包恢复装备。

- `reference/`：用户确认的六张80×80透明成品母版，只登记最终像素，不包含提示词、外部参考或试稿过程。母版不是完整动画图集。
- `generation-record.json`：生产工具、原生输入、成品母版与代码摘要。
- `runtime-import-report.json`：30张分层图集、60张32×32独立图标的摘要。
- `tools/build_xuanfeng_equipment.py`、`tools/xuanfeng_native_style.py`：确定性生产入口。

生产按原生配方的可见部件回投母版，衣装沿用原始关节遮罩，复合姿势匹配原生躯干补绘；头盔随头部部件动作，脸区和下发接缝受保护。两种武器朝向分别适配原生握持坐标，不把单张母版缩放成动作帧。运行时仍使用头部、衣服、武器三项外观，其余七槽只有图标和属性。

```sh
python tools/build_xuanfeng_equipment.py
python tools/build_xuanfeng_equipment.py --check
python tests/test_xuanfeng_assets.py
```

原生人物与部件来自项目恢复资料，底层素材的许可边界继续遵循[资源来源说明](../../../../docs/asset-provenance.md)。本文不构成再分发授权。
