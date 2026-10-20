# 初号机装备美化参考

按用户要求，以原版七阶衣装、原生脸型和发型为基础优化初号机主题。内置 image_gen 生成的 `design-reference.png` 只提供紫甲、玉绿镶边和冠饰方向；它不是原始像素尺寸，也不是可直接使用的动画图集。

生产阶段由 `tools/build_eva01_equipment.py` 和 `tools/eva01_native_style.py` 沿用原包部件轮廓、帧区域、肤色及握持点，保留原生发型，增加贴在发丝上的小型玉冠。六套衣装改用各自的七阶原生三层部件；九个非武器图标参考原版紫霄系列，武器继续使用各自原生模板。

完整生成提示词见 `prompt.json`。正式运行时文件位于 `client/assets/generated/equipment/eva01/`；这张参考立绘不会代替游戏内动画验证。
