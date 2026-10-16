# Web 主游戏与本地战斗、刷新功能合并验证

2026-10-16，在共享 `dev` 的本地提交 `7d31619` 上合入已拉取的 `0704df4`，保留双方历史，以普通 merge commit 完成用户已经发起的 `git pull`。本次不推送、不变基或重写远程分支。

冲突位于 `client/scripts/main.gd` 与 `client/scripts/world.gd` 的 `_process`：先检查 Web 是否失焦/挂起，再执行本地战斗动画推进或怪物刷新。两方逻辑均保留，Web 中文字体回退和入口改动继续保留。

远程新增的导出策略检查有两个 Windows 兼容问题：Python 默认编码无法读取中文 HTML，Git 的 CRLF 转换使字体许可证字节摘要与来源记录不同。检查显式使用 UTF-8，并为该许可证固定 LF；字体和许可证的来源摘要保持原值。补齐新引入 GDScript 的 Godot UID 元数据。

Windows / Godot 4.7.1 验证：

| 检查 | 结果 |
| --- | --- |
| 编辑器重新导入项目 | 成功，无脚本解析错误 |
| `test_runner.tscn` | 385 项，0 失败 |
| `offline_respawn_test.tscn -- --realtime` | 91 项，0 失败，实际等待 30 秒刷新 |
| `native_battle_flow_test.tscn` | 57 项，0 失败 |
| `online_pve_test.tscn` | 28 项，0 失败 |
| `resource_loader_test.tscn` | 42 项，0 失败 |
| `web_resource_loader_test.tscn` | 13 项，0 失败 |
| `platform_storage_async_test.tscn` | 64 项，0 失败 |
| `platform_interface_test.tscn` | 56 项，0 失败 |
| Python `test_platform_interface.py` | 15 项通过 |
| Python `test_game_export_policy.py` | 4 项通过 |

Godot 用例运行格式：`godot --headless --path client res://tests/<场景名>`。Python 使用 `python -m unittest discover -s tests -p <测试文件名>`。

本次验证范围为合并后原生运行、Web 队列与导出策略；未重新导出 WASM 或执行完整浏览器游玩验收。
