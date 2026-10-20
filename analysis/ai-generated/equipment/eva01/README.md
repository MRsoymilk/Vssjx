# EVA 初号机主题制作记录

参考来自用户文字：“参考 EVA”“EVA 的初号机”。不是官方图片包或授权资源，没有下载／复制官方插画和标志。

- 生成方法：AI 编写 `tools/build_eva01_equipment.py`，用 Pillow 在原生帧尺寸上执行确定性像素重配色与补绘；不使用外部 `image_gen` 服务。
- `generation-record.json` 保存特征、调色板、生成器 SHA256 与原包输入哈希。
- `runtime-import-report.json` 保存 30 张部件和 60 个图标的 SHA256。
- 后续仅力士武器改为原生 `ezs9` 双刃斧，图标和名称同步。`axe-change-record.json` 固定修改前基线，校验其他 86 张图片、完整玩法目录及非武器外观映射不变。
- 头部为新独角全覆面盔；身体／武器沿用原始帧的透明轮廓和握持结构，添加紫黑／荧绿装甲表达。头部第二帧是下发／护颈段，保留全部接缝像素。
- 原始部件、已有骨甲幽光／冥林异装图集不覆盖；动画仍使用原游戏配方。

正式资源：`client/assets/generated/equipment/eva01/`；设计见 [专题](../../../../design/eva01-equipment.md)，验证见 [离屏记录](../../../../tests/eva01_equipment.md)。截图在忽略目录 `work/eva01-production/`，不是正式图集或另一个高分辨率插画源。

EVA 参考作品与《蜀山剑侠Online》原包的权利分别核验。同人参考、AI 脚本或像素化不代表取得第三方再分发／运营授权。
