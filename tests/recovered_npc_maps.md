# 截图人物应用到地图（2026-10-21）

## 职责匹配修订（2026-10-23）

`npc_revision=3`：一般AI人物先按职责进入16类已审阅外观池，地貌只能在该类候选中取舍。净水道童使用童子造型，采药苗女使用女性造型，老人使用长者造型；信使、守卫、统领使用站姿成人，匠人采用工匠／伙计造型，坐姿布袋人物用于茶摊客人。名字不用于猜测性别或年龄，明确姓名对应及既有人工适配仍优先。

本轮为1,079位AI人物记录职责依据，其中893位调整实际外观。20种现有图集继续使用，共1,100位截图外观NPC；生成器、双端地图、绑定审计和图集使用数量索引同步更新。与提交前目录逐字段比较，仅外观及其依据、NPC修订号变化。

验证：Python人物专项6项、地图／怪物生成与任务12项、Rust共享世界2项通过；Godot地图任务2,079项、实际OpenGL人物／协议／八地图渲染462项通过。八图截图在`/tmp/opencode/vssjx-npc-role-captures/`，重点审阅`ai_012`苗女、`ai_023`道童及`ai_213`营地职责。原始图集尺寸、脚底锚点、点击命中和任务标记均通过现有专项检查。

## 首次接入记录

20种截图修复外观通过既有 `OriginalArt` 单帧角色接口接入本地／联机共用地图。生成器更新后，两端JSON逐字节相同；213张地图中的1,100位NPC使用新外观。NPC ID、名字、格子、对白、服务、任务、地形、碰撞、传送和怪物数据与本轮修改前一致。

## 检查结果

| 检查 | 结果 |
| --- | --- |
| Python NPC图集／来源／锚点／映射专项 | 4项通过 |
| Python地图、可达性、NPC及642条任务回归 | 9项通过 |
| 基础图集元数据可重复重建 | 1项通过；单独商城流程发布的66个英雄穿戴变体按其资源类别排除，全部基础图集及新增NPC须一致 |
| Godot NPC本地／联机专项（无界面） | 403次检查，0失败 |
| Godot现有地图、任务及存档回归 | 2,074次检查，0失败 |
| Godot实际OpenGL渲染、五地图截图 | 408次检查，0失败 |
| Rust共用214地图／路径／NPC与任务回归 | 2项通过 |

Godot专项实例化全部20种图集，验证单静态帧、小尺寸、落地锚点、左右镜像下可见像素点击、透明外侧不抢地面点击；构造联机人口包验证共用外观被接受、擅自换回其他图集被拒绝，并检查联机姓名及服务文字。本地实例化天化村、花涧派、慈云寺北、昆仑派和八旗镇，检查NPC位置、外观键、任务标记。

渲染使用Godot `4.7.1.stable.official.a13da4feb`、OpenGL Compatibility、NVIDIA RTX 5060。实际截图位于 `work/npc-map-runtime/ai_007.png`、`ai_021.png`、`ai_028.png`、`ai_032.png`、`ai_041.png`；逐张查看了透明背景、角色比例、地面锚点及标签。测试使用独立存档路径，未写入玩家存档。

## 复现

```powershell
python -m unittest discover -s tests -p 'test_recovered_npc_maps.py'
python -m unittest discover -s tests -p 'test_ai_world.py'
& 'E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --headless --path client res://tests/recovered_npc_map_test.tscn
& 'E:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --headless --path client res://tests/ai_world_test.tscn
cargo test --manifest-path server/Cargo.toml --target-dir work/npc-map-cargo --test ai_world
```

实际截图需先创建输出目录，设置 `SSJX_NPC_CAPTURE_PATH`，再省略 `--headless` 运行NPC专项场景；Windows后台启动采用 `Start-Process -WindowStyle Hidden`。Rust使用独立构建目录，因为默认debug服务可执行文件正在使用；没有结束或替换运行中的服务进程。

以上为工作区资源和协议夹具验证，不代表公网客户端／服务端已经发布或重启，也没有执行导出打包。
