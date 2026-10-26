# 装备实例B阶段验收

2026-10-21。只在源码及自建测试数据库／独立存档验证；未打包、部署或推送，不操作玩家数据库。

## 范围

- `loot-v1` 独立UUID、物等、白／蓝／黄品质、部位词缀与双端属性聚合。
- 固定装备镜像迁移、同底材多件、共享背包容量、领取暂存、装备／卸下、所有权及修订验证。
- 实际背包“菜单 → 装备实例”入口；背包图标、物等、人物预览、选角、世界与战斗使用同一实例外观。
- 一次确认保存后编号／词缀不变；持久化失败回滚；换装不回血，寻尸流程不受影响。
- 穿透、增伤、持续增伤、评级、暴伤和额外减伤实际进入计算；技能与PvP继续使用各自既有规则。
- 旧商城和原有装备图像不改，固定装备不重抽、双计或自动变为传奇。随机奖励、流派套装及打造仍待C/D。

## 证据

本轮结果：Rust全量145项、真实服务20项、实际OpenGL专项2200项、参数镜像契约5项均通过。相关客户端回归：异步持久化67项、本地角色27项、控制指令59项、寻尸461项、商城1638项、属性80项、战斗防卡322项、单人阵列55项、闪避呈现28项通过；先前“零失败”但含脚本错误的异步测试已修正并重跑，不计作通过证据。

`server/examples/loot_vectors.rs` 直接输出实际Rust结果：三职业×两性别×十部位×三个物等×三品质，共540组；Godot逐组检查抽取结果、完整属性、属性面板、伤害、持续伤害、暴伤、命中与承伤。此处的同种子是可复现开发验收，不是联机客户端能提交的抽取参数。

`tests/run_loot_instances.py` 使用独占临时PostgreSQL、真实Rust服务与WebSocket验证20项：旧库存一次迁移、同底材独立副本、只穿一件、角色修订过期拒绝、UUID跨角色拒绝、原UUID重放与变更请求冲突、事务失败回滚及重试、进程重启、选角／社交属性外观一致、真实单人阵列冻结数值、战斗中拒绝换装、共享满包及领取原暂存实例。真实回包交给Godot正式校验器与背包界面，界面仅提交UUID和修订。

新增专项还覆盖：本地真实文件重读、迁移写失败前不发布新编号、保存失败整笔回滚、魂态拒绝、满包拒绝、非法词缀／重复UUID拒绝、控制指令降级后存档仍可读取、有界大库存封包和正常原生背包入口。实际OpenGL画面已检查，截图位于忽略的 `work/loot-instances/panel.png`。

原有属性／异步存储测试中，旧推荐加点和旧NPC按钮／传送等待已落后于现有源码；本轮按实际版本更新固定断言与真实入口，不放宽失败回滚要求。闪避专项改用现有角色映射，而不是不存在的`_w1_c0`资源别名。独立命中测试仍覆盖闪避；持久化测试使用合法固定命中种子避免随机击空跳过结算。

## 复现

```sh
mkdir -p work/loot-instances
cargo test --offline --manifest-path server/Cargo.toml
cargo build --offline --manifest-path server/Cargo.toml
cargo run --offline --manifest-path server/Cargo.toml --example loot_vectors \
  > work/loot-instances/rust-vectors.json
SSJX_LOOT_VECTORS="$PWD/work/loot-instances/rust-vectors.json" \
python tests/run_loot_instances.py
SSJX_LOOT_VECTORS="$PWD/work/loot-instances/rust-vectors.json" \
SSJX_LOOT_FIXTURES="$PWD/work/loot-instances/server-fixtures.json" \
SSJX_LOOT_CAPTURE="$PWD/work/loot-instances/panel.png" \
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb LIBGL_ALWAYS_SOFTWARE=1 \
python tests/run_offscreen.py --path client --rendering-method gl_compatibility \
  --rendering-driver opengl3_es res://tests/loot_instances_test.tscn
```

截图和向量验证不证明终局平衡，也不等于六流派胜率或刷装经济已验收。迁移0026已在前阶段提交，本轮不改写历史迁移、不向线上运行库执行迁移。

## 2026-10-21 装备页主题整理

装备管理沿用 `OriginalUITheme.palette("bag")` 的青绿底、金色边框与像素边角。列表增加原物品图标、穿戴/暂存状态及品质色；长名称省略显示，悬停可见完整名称、品质、等级和编号。下方独立属性区域保留滚动和当前穿戴对比，底部操作区固定。流派说明使用完整内容区域，再点“装备”可回到列表；空列表显示获取提示并禁用装备、领取。

`loot_instances_test.tscn` 无头 20 项、实际 OpenGL 渲染 21 项通过；使用进程独立存档路径实机检查普通装备、暂存领取、流派说明、58 件长列表和空列表五种视图，未更改玩家存档。只调整界面，不修改装备属性、掉落、实例 UUID 或线上提交协议。

## 2026-10-23 背包菜单高亮可读性

- 背包弹出菜单此前只覆盖普通文字颜色，悬停／按下时继承浅色文字，导致浅黄纸底上难以辨认。所有菜单项补齐深棕色悬停、按下、悬停按下和焦点文字；悬停增加浅金底和棕色细边，按下时加深金色，禁用项使用灰棕文字。
- `godot --headless --path client res://tests/loot_instances_test.tscn`：20项、0失败。
- 实际OpenGL鼠标交互截图确认普通、悬停、按下及禁用状态，并点击“装备实例”成功打开装备管理。截图目录 `/tmp/opencode/inventory-menu-highlight/`，日志 `/tmp/opencode/inventory-menu-highlight.log` 和 `/tmp/opencode/inventory-menu-loot.log`。

## 2026-10-26 手机装备滚动条加宽

- 装备一览的列表和下方详情共用24个逻辑像素宽的滚动条（此前样式最小宽度6），可见条和实际命中区域一起加宽约4倍；滑块最小高度28。普通、焦点、悬停、按下样式保持相同宽度，不只增大视觉绘制。
- 属性文本为新宽度留出空间并自动换行，不增加横向滚动、不遮挡属性。流派说明展开时同样使用宽条，底部装备／卸下、领取暂存、返回背包位置不变。
- `loot_scrollbar_test.tscn` 无头47项、实际OpenGL48项通过，分别验证本地和联机装备界面、长列表／多词缀详情、条宽与滑块最小高度、从左／右边缘实际拖动、文本不遮挡、流派切换，以及不改变装备、玩家存档或联机发件箱。
- 装备实例20项、独立装备详情21项回归通过。实际截图：`/tmp/opencode/loot-scrollbar.png`；验证使用独立虚拟显示器，没有打包、部署或修改运行中的客户端。
