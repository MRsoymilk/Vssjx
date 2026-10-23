# 昼夜与场景时钟

规则与范围见 [共享地图：昼夜光照](../design/shared_world.md#昼夜光照)。只更新源码及本地隔离验证，未打包、部署或推送；联机效果需要更新服务端和客户端，旧服务缺少时间时保留白天原色。

## 昼夜与实际地图渲染

```sh
godot --headless --path client res://tests/day_night_test.tscn
mkdir -p /tmp/opencode/vssjx-day-night-captures
SSJX_DAY_NIGHT_CAPTURE_PATH=/tmp/opencode/vssjx-day-night-captures \
  LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py \
  --path client --rendering-driver opengl3_es res://tests/day_night_test.tscn
```

若 Xvfb 不在 PATH，可通过 `XVFB_BIN` 指定现有可执行文件。真实渲染检查不能由 `--headless` 替代，不向玩家桌面弹窗。

- 精确检查每段 3600 秒、最后 60 秒渐变、两小时周期、边界连续及渐变方向。
- 实例化正式本地和联机地图，验证视口隔离、服务器时钟、切洞穴后固定光照、返回室外恢复同一时相、切图不叠加 CanvasModulate、断连恢复及角色数据不变。
- OpenGL 读取真实地图像素，断言夜间明显变暗但仍可导航；逐字节比较白天／夜晚的顶部 HUD 和底部聊天／工具栏，确保不被调色。
- 2026-10-23，Godot `4.7.2.stable.gentoo.ed1daf0bf`：逻辑专项 **1119 项通过**；Xvfb + Mesa OpenGL ES 3.2 真实渲染 **1129 项通过**，包含 6 张白天／黄昏／夜晚／黎明／联机夜间／洞穴截图，输出至上述临时目录。没有声称完成手机、Safari 或原生 iOS 真机验收。
- 原生地图回归 **455194 项通过**，包含地图资源、导航及渲染数据边界。
- 本地模式 30 项、切图过渡 34 项、世界总图 44 项，以及 Python 原生地图 8 项、共享地图数据 2 项、文档本地链接／锚点 2 项通过。

## 联机场景时钟

```sh
godot --headless --path client res://tests/world_clock_test.tscn
godot --headless --path client res://tests/world_delta_test.tscn
cargo test --locked --manifest-path server/Cargo.toml
python tests/run_shared_world.py --output /tmp/opencode/vssjx-day-night-world
```

- `world_clock_test`：握手先校时再发出地图变更，单调时钟推进，心跳重新校时，断连／切图不重置，退出清空；拒绝未认证、负数、小数、溢出等时间，兼容缺少字段的旧服务。
- `run_shared_world.py`：自建临时 PostgreSQL 和隔离 Rust 服务，验证真实握手／心跳时间，并继续验证两位 Godot 玩家、移动、聊天及重连；不访问生产数据库。
- 2026-10-23：Godot 4.7.2 场景时钟 20 项、原世界增量协议 50 项检查通过；Rust 全套测试零失败（原有数据库专项测试 1 项按原规则忽略）。
- 同日真实隔离联调通过握手／心跳时间校验、公共聊天 53 项及两位独立 Godot 玩家 25／28 项检查，并覆盖接管、注销、位置持久化及服务重启。
- 光照接入后再次以 `run_shared_world.py --render` 完成两个独立 OpenGL 客户端检查：32／35 项通过，包括正式地图光照使用服务器时间、重连后保持原光照节点并重新校时。产物在 `/tmp/opencode/vssjx-day-night-world-render/`。

## 已知全量回归限制

本轮没有把下列旧测试报告为通过，也不扩大范围修改战斗、背包、素材或文档历史：

- Python 全量 282 项有 15 个失败、1 个错误、4 个跳过，涉及旧素材重建／摘要、文档索引、路径和技能资源预期。在不含本轮光照的 `a20ee9b` 隔离副本中重跑，结果同为 15 个失败、1 个错误、4 个跳过。
- 原有 `test_runner.tscn` 371 项存在大量战斗／UI／背包旧断言失败；当前两次运行分别为 111／110 个失败，未加入光照的隔离副本为 109 个失败。该入口结果不能作为本轮完整玩法通过的证据，失败数亦不稳定。
- 行走专项 6018 项中有 2 个点击路线失败，共享界面 28 项中有 2 个本地 HUD／任务预期失败；两者均在未加入光照的隔离副本中复现相同失败。
- 对照副本和日志仅位于 `/tmp/opencode/vssjx-day-night-baseline*`，未回退或覆盖工作区代码，未使用玩家存档或生产数据库。
