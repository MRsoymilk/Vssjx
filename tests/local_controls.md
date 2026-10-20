# 本地测试指令

在**本地游戏聊天框**输入并发送：

| 指令 | 行为 |
|---|---|
| `/control lv 50` | 等级设为50，清空经验，按新上限恢复气血与灵力 |
| `/control hp 1` | 当前气血**设为1**，不改变最大气血、灵力、经验或铜币 |
| `/control money 1` | 铜币在当前余额上**增加1**，不是设为1 |
| `/control help` | 显示帮助 |

血量范围1～当前气血上限；增加铜币必须为正整数，增加后的总额不超过10亿（存档格式上限）。灵魂状态拒绝这些指令，不可借此复活；仍须寻尸。

指令只作用于当前本地角色；保存成功后刷新HUD和提示，失败回滚，保存中不允许重复提交，旧角色保存结果不会覆盖新角色。联机聊天没有此执行入口。

验证入口：`client/tests/local_control_test.tscn`，59 项通过；覆盖新指令的精确语义、落盘重读、参数边界、保存失败回滚、在线隔离和灵魂限制；沿用原等级指令、普通聊天和角色切换回归。Xvfb + Mesa 实际离屏截图 `work/soul-recovery/local-controls-hp-money.png` 已人工检查。

实际离屏运行：

```sh
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb \
SSJX_LOCAL_CHAT_CAPTURE="$PWD/work/soul-recovery/local-controls.png" \
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py --path client \
  --rendering-method gl_compatibility --rendering-driver opengl3_es \
  res://tests/local_control_test.tscn
```

未打包、未部署、未推送。
