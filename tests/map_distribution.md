# 截图地图与怪物分布优化

布局版本 5、怪物分布版本 2、出口版本 4。执行 `python tools/build_ai_world.py` 可同时重建客户端、服务端共用配置和来源记录。

`tools/screenshot_map_profiles.py` 使用 ssjx_pic 局部截图调整 11 张地图，花涧派另对照 95.jpg 校验草地、棕榈和水岸。能通过同名 NPC 对应的有天化村、慈云寺北、昆仑派和花涧派；其他镇街、湿地、沙地属于同类地貌或相邻区域适配，来源记录明确标注不确定性。截图没有提供原始地形文件或精确怪物刷新点。

- 天化村保留临水草地、疏林与边缘住宅，减少大面积铺砖。
- 慈云寺一带和昆仑派采用原图集黄土、青瓦屋、门楼、岩阶，昆仑派服务庭院不再铺冰雪悬崖。
- 八旗镇采用草地与铺砖街巷；沙丘、沙漠荒野、流沙平原采用沙土、岩阶和少量秋树。
- 213 张非教程地图重新选择现有怪物的刷新点。服务 NPC 与怪物种子至少相隔 7 格，入口与出口至少 9 格，怪物种子间至少 5 格，均为曼哈顿距离。保留原有两格巡游半径。
- 把所有怪物的 5×5 巡游范围视为禁行区后，出生点仍能抵达每个 NPC 和所有出口。敌人种类较多的墓室扩大深处战斗厅，避免巡游封住甬道。
- 保留全部居民 ID、名字、外观、怪物种类/数量/等级/属性，以及 642 个任务及目标；灵空台教程坐标保留。

来源与怪物位置：`analysis/recovery/ssjx-pic/map-optimization.json`，包含截图 SHA-256、适配范围、不确定性和 213 张地图的刷新点。完整地形、碰撞与坐标仍为设计补全，非原版恢复。

## 自动检查

```powershell
python -m unittest discover -s tests -p 'test_map_distribution.py'
python -m unittest discover -s tests -p 'test_ai_world*.py'
python -m unittest discover -s tests -p 'test_recovered_npc_maps.py'
cargo test --manifest-path server/Cargo.toml --target-dir work/npc-map-cargo --test ai_world
& 'E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --headless --path client res://tests/map_distribution_test.tscn
```

地图场景检查在真实客户端创建 13 张地图，核对地形碰撞、NPC/怪物外观与出生点，并用 Godot AStar 验证避开巡游区的办事路线。

设置 `SSJX_MAP_CAPTURE_PATH` 为已存在的绝对目录，以 `gl_compatibility` 运行同一场景可输出 13 张真实地图截图；Windows 自动截图应使用 `Start-Process -WindowStyle Hidden`。无渲染检查 433 项；真实渲染加截图检查 446 项。

客户端须重新启动以加载更新后的地图目录；服务端使用嵌入式地图数据，现有服务进程需要在后续明确部署时重建并重启。本轮不改动正在运行的服务。
