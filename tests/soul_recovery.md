# 寻尸复活验收

- `tests/run_soul_recovery.py`：独占临时 PostgreSQL / Rust 服务 / WebSocket，18 项通过。实际战败、原地坟堆、同图 spawn、资产保留、灵魂操作限制、错误尸体／距离拒绝、真实进程重启、失败事务回滚、成功复活和回执重放。
- `client/tests/soul_recovery_test.tscn`：所有现有地图复活点／尸体格式验证、本地战败落盘与重读、恢复限制、寻路返回坟堆、保存失败回滚、复活去灰／删除坟堆、真实服务端快照验证。
- Xvfb + Mesa llvmpipe 实际 OpenGL ES 离屏渲染，464 项通过。截图及日志：`work/soul-recovery/`（忽略目录）。`soul-spawn.png`、`corpse-nearby.png`、`revived.png` 已人工检查；逐像素抽样验证灵魂全屏灰度及复活后恢复彩色。

```sh
cargo build --offline --manifest-path server/Cargo.toml
python tests/run_soul_recovery.py
XVFB_BIN=/tmp/opencode/vssjx-eva01-xvfb/run-xvfb \
SSJX_SOUL_CAPTURE="$PWD/work/soul-recovery" \
SSJX_SOUL_SERVER_FIXTURES="$PWD/work/soul-recovery/server-fixtures.json" \
LIBGL_ALWAYS_SOFTWARE=1 python tests/run_offscreen.py --path client \
  --rendering-method gl_compatibility --rendering-driver opengl3_es \
  res://tests/soul_recovery_test.tscn
```

仅使用新建临时存档／数据库，不连接生产服务器，不修改玩家数据；测试最后恢复原本地内存与存档路径。本轮无打包、部署或推送。
