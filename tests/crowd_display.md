# 人群显示与重叠目标选择

2026-10-27，当前客户端源码；不代表已发布网页／APK包含。

- 本地／联机“菜单 → 系统 → 其他玩家”依次切换正常、半透明、隐藏；默认正常。自己和本人队伍成员保留，别队旗标不赋予豁免，NPC／怪物不隐藏。
- 半透明同时作用于人物、名字及旗标；隐藏时不接收该玩家的地图点击，清除旧目标卡并暂停其动画、跳过外观合成。位置／外观同步数据保留，恢复显示时使用最新状态；在线人数及小地图人口信息不伪造。此项不是服务器容量优化或同步协议裁剪。
- NPC／怪物图像和名字高于普通玩家。多个可见目标重叠时，鼠标和触屏均先打开可搜索、可滚动列表，明确选择NPC对话、怪物挑战或玩家目标，不随机开战。单目标保留原交互，跟随队员仍不能独立寻路挑战。
- 设置独立保存在原生 `user://display.cfg` 或网页同源单一非敏感键 `vssjx.players.display.v1`；写入失败仅本次生效并提示，非法配置回退正常显示。不触碰角色存档、服务器资产或账号凭据。

## 验证

```sh
godot --headless --path client res://tests/crowd_display_test.tscn
godot --headless --path client res://tests/ground_click_test.tscn
godot --headless --path client res://tests/player_target_test.tscn
godot --headless --path client res://tests/population_test.tscn
python -m unittest discover -s tests -p test_display_preferences.py
python -m unittest discover -s tests -p test_platform_interface.py
```

新专项无头28项、Xvfb／Mesa OpenGL ES实际渲染33项通过，使用100名同图玩家的客户端夹具，不冒充100个真实并发连接。覆盖正常／半透明／隐藏、队友保留、别队不保留、名字图层、可见点击、实际设置按钮、保存失败及恢复、角色状态不变。

回归：地面／拥挤点击26项、玩家目标28项、人口27项、声音设置24项、UI场景110项通过；Python浏览器标记1项、平台边界15项通过。实际渲染可通过 `SSJX_CROWD_CAPTURE` 指定已创建的截图目录，并用 `tests/run_offscreen.py --path client --rendering-driver opengl3_es res://tests/crowd_display_test.tscn` 执行；本轮已查看 `/tmp/opencode/crowd-display/` 中隐藏与重叠选择截图。

未执行Web导出、浏览器／Android真机、真实多人压测或部署；不推送、打包或重启服务。旧NPC优先级记录见 [npc_priority.md](npc_priority.md)，当前多目标点击改为显式选择。
