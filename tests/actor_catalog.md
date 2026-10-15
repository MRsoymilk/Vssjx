# 角色元数据分片与按需加载

```sh
python tools/import_assets.py --metadata-only
python -m unittest discover -s tests -p 'test_*.py'
python tests/run_actor_catalog.py
python tests/run_battle_casting.py --render --output /tmp/opencode/vssjx-sharded-casting
python tests/run_battle_transition.py --render --output /tmp/opencode/vssjx-sharded-transition
```

`--metadata-only`需要已有的静态解码PNG，只重新生成数据，不改任何贴图。完整版导入仍使用原命令。生成器不清理无关文件，非法路径在写入前拒绝。

## 2026-10-15布局与数据完整性

- 原`actors.json`：50,026字节、8032行；现为2036字节索引＋33份按分类/角色命名的JSON，单份最多201行，合计36,315字节。
- 原`original_animations.json`：1,830,575字节，原来就没有游戏运行时读取；移出客户端，拆为`analysis/animations/`下310份可读JSON与索引。可读格式总计约2.1MB，不声称整个仓库变小；客户端不再携带这一分析存档。
- 33份运行时记录、310份原始编排（包括每层坐标、变换、序列和opaque_tail_hex）的规范化SHA-256与拆分前完全一致；33张图集原始字节的整体SHA-256保持不变。
- 生成器保留创建页法师预览与战斗法师的不同动作映射，修正旧生成过程可能将战斗cast映射带进预览元数据的问题；此次没有改变已签入角色数据语义或PNG。

基线摘要位于`tests/fixtures/actor_catalog_v1.json`；精确旧版50KB文本仅作为压缩测试夹具保存，不在客户端目录。微基准使用原始文本，不以紧凑序列化的替代文件冒充旧版。

## 实测（Godot 4.7.2，本机元数据微基准）

首次查询`hero/mfs`只读索引与该角色两份JSON，共3751字节，而不是50026字节；不加载其他角色元数据，也不构造SpriteFrames或加载纹理。重复1000次查询没有额外文件IO。原有SpriteFrames共享缓存和source_N、攻击/施法单次播放规则保持。

31次同进程交替采样，OS文件缓存已热、应用元数据缓存冷；不包含纹理/GPU、整个游戏启动或FPS：

| 读取方式 | p50 | p95 |
|---|---:|---:|
| 旧版整包元数据 | 938μs | 1712μs |
| 分片索引＋单角色 | 263μs | 684μs |

这只是元数据读取/解析/校验的改善，不能将移出1.83MB分析存档说成运行时少解析了1.83MB，也不保证磁盘冷缓存时每个平台都更快。

Godot缓存/模式测试81项零失败（含微基准夹具断言），输出`/tmp/opencode/vssjx-actor-catalog/catalog.json`。法师攻击/施法120帧真实离屏渲染与遇敌准备过渡离屏回归均通过，原有资源缺失恢复路径保持有效。截图/日志分别位于`/tmp/opencode/vssjx-sharded-casting/`、`/tmp/opencode/vssjx-sharded-transition/`。
