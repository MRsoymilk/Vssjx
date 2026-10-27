# 项目文档导航

[返回项目首页](../README.md) · [设计索引](../design/README.md) · [测试索引](../tests/testing.md)

整理日期：2026-10-27。**源码实现、历史验收、线上部署和待实施方案分开记录**；文档日期、版本号或一次测试通过，都不能证明体验服与安装包已同步。

## 从这里开始

| 目的 | 文档 |
|---|---|
| 试玩、操作、地图传送、装备与交易入口 | [游玩指南](getting-started.md) |
| 账号、共享世界、玩法与协议边界 | [设计索引](../design/README.md) |
| 随机掉落、穿戴绑定、拍卖与当面交易 | [装备与经济规则](../design/equipment-economy.md) |
| 素材浏览、动画与世界总图工具 | [数据工具](data-tools.md) |
| 原包恢复范围和重建流程 | [资源恢复与重建](resource-recovery.md) |
| 原包、第三方及AI素材的许可边界 | [资源来源](asset-provenance.md) |
| 本机服务、配置、HTTP接口与管理监听 | [服务端说明](../server/README.md) |
| 网页／公网部署、备份及更新前检查 | [部署导航](../deploy/README.md) |
| 客户端自动更新和资源热更的建议 | [客户端升级方案](../design/client-updates.md)，尚未实现 |
| HTTP延迟的历史观测、解释和优化顺序 | [延迟分析](../tests/http_latency_optimization.md)，优化尚未实施 |
| 开发、贡献与提交要求 | [贡献指南](../CONTRIBUTING.md) |

## 近期源码能力与验证入口

下表是文档入口，不是新的测试报告，也不是上线清单。

| 主题 | 当前说明与已有验证 |
|---|---|
| 原生／AI装备随机掉落、旧装备兼容、穿戴绑定 | [规则](../design/equipment-economy.md)、[掉落养成](../tests/progression.md)、[装备实例](../tests/loot_instances.md) |
| 铜钱竞价／一口价、当面双向托管与二次确认 | [交易验收](../tests/economy.md)、[公共ROLL](../tests/team_loot.md) |
| 原版风格装备详情、对比与属性评分 | [详情与评分](../tests/equipment_details.md)；评分不等于战斗伤害或售价 |
| 技能熟练度、6／10／15级资源阶段、固定耗蓝与无冷却 | [技能规则](../design/skills.md)、[熟练度](../tests/skill_proficiency.md)、[固定消耗](../tests/fixed_skill_costs.md)、[效果调整](../tests/skill_rebalance.md) |
| 原地施法与逐目标飞行特效 | [战斗动作验证](../tests/battle_casting.md) |
| 无尽试炼、个人纪录、排行榜与公屏里程碑 | [无尽试炼](../tests/endless.md) |
| 采矿采药、独立材料袋与材料加工 | [采集验证](../tests/gathering.md) |
| 地图管理草稿／校验／发布／恢复 | [地图管理](../tests/map_management.md)；不是任意SQL或数值修改入口 |
| 人群显示、重叠目标及同图寻找NPC | [人群遮挡](../tests/crowd_display.md)、[寻找NPC与到达对白](../tests/npc_finder.md) |
| 总图地点文字、缩放、拖动与神行符确认 | [世界地图](../tests/world_map.md)、[神行符](../tests/travel_scroll.md) |
| 本机管理、每日在线与HTTP监控口径 | [服务端说明](../server/README.md)、[每日在线](../tests/monitor_online.md)、[监控验证](../tests/observability.md) |

## 如何判断状态

- **当前规则**以对应设计专题、共享数据和源码为准；发现旧规则时更新当前摘要，保留带日期的历史记录。
- **历史验收**在 `tests/` 中按日期、环境和入口记录。临时截图、快照与日志路径可能已不存在，应按命令重新生成，不能当作永久产物。
- **发布事实**引用具体发布记录、构建提交、产物摘要及迁移状态；当前源码新增能力不会自动更新已有网页、APK或服务进程。
- **待实施方案**明确标注未实现，不因被加入文档或路线图就视为已交付。
- 本次整理仅修改文档与静态文档检查，不运行迁移、修改玩家库、推送、打包或部署。
