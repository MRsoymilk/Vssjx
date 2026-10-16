# 游戏导出与开发工具隔离

`client/scenes/admin/`和`client/scripts/admin/`是独立开发工具，不是游戏页面。保留在同一源工程以复用只读数据和美术，但游戏不引用它们，导出也不得包含它们。运行工具时关闭Godot编辑器的Embed Game on Play；正常游戏的320×480布局和默认主场景不变。

## 导出规则

`client/export_presets.cfg`提供`Game (Linux)`和`Game (Windows)`预设，两者均：

- 排除`scenes/admin/*`、`scripts/admin/*`和`tests/*`。
- 包含`assets/data/*.json`，包括按角色动态读取的JSON分片；共享世界地图等仍是游戏资源，不因管理工具也使用它们而删除。
- 不包含客户端工程以外的`analysis/`、`tools/`或服务端目录。
- 可执行文件默认输出到Git忽略的`work/builds/`；目录需自行创建，且必须安装匹配引擎版本的导出模板。PCK资源包检查不需要模板，也不代表已验证目标平台可执行文件。

新建其他游戏导出预设时，应保留相同排除/包含规则。仅仅没有游戏入口并不足以保证资源不被`all_resources`打包，因此有明确的过滤与回归检查。

## 验证

```sh
python -m unittest discover -s tests -p 'test_*.py'
python tests/run_game_export.py --output /tmp/opencode/vssjx-game-export
```

脚本复制一份不含`.godot/`和导入缓存的客户端源码到测试输出目录，隔离编辑器配置、缓存、用户数据与测试存档，避免干扰正在打开的编辑器；在该副本中导出两个真实PCK，再用引擎从每个PCK启动检查，不通过源目录中的同名资源冒充打包结果。检查：

1. 运行的是包内`project.binary`，管理场景、专用脚本和测试目录均不存在。
2. 全部33份角色JSON分片及共享世界JSON保留。
3. 包内游戏主场景确实能实例化并到达封面，320×480视口不变。

静态单元测试还约束所有游戏预设的过滤规则，以及游戏运行脚本/场景不能反向引用开发工具目录。审计用的`tests/game_export_probe.gd`故意放在客户端工程之外，以绝对文件路径运行，避免为了检查而把探针重新加入游戏包。原始PCK和日志留在测试输出目录，不提交到仓库。

2026-10-16（Linux、Godot 4.7.2）：两个预设的真实PCK导出通过，各48项包内检查零失败；实际验证管理目录完全缺席、33份角色JSON全部保留，且包内游戏主场景能进入封面。Python回归55项通过。产物在`/tmp/opencode/vssjx-game-export/`；这是Linux引擎对两个预设资源包的验证，不冒充Windows可执行文件或跨平台原生运行验收。
