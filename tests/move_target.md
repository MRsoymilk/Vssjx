# 行走落点提示

## 本地阶段

- `world_move_target.tscn`复用原游戏的`scene_target.png`及四个`select`贴图，组成蓝色悬浮指针与金色落点圈。轻微上下浮动由场景内AnimationPlayer保存。
- 点击可达地面显示目标格中心；交互寻路显示实际靠近的终点。提示固定在地图坐标，不跟随人物或镜头移动。到达、取消、暂停、战斗与键盘接管时清除；不可达位置不保留旧提示。
- 本地提示11项检查、真实渲染12项检查、移动控制35项及连续点击776项回归通过。
- 真实渲染设置`SSJX_MOVE_TARGET_CAPTURE_PATH`可保存`local_move_target.png`。
