# 共享地图：当前实现

## 范围与所有权

线上角色大厅可进入青云山道 `qingyun_trail/main` 或恢复位于古剑遗迹 `ancient_ruins/main` 的角色。玩家互不阻挡，同一地图全图互见，不同地图独立同步。客户端仅发送目的格，服务器以72像素/秒沿四邻接路径移动，每100ms推进；客户端插值渲染并按实际位移播放行走动画。树木、河流和边界阻挡取自原Godot地图导出，双方校验原始JSON的SHA-256。灵门条件、持久化传送和验证见 [联机第二张地图](../tests/online_maps.md)。

一个服务进程内的 `WorldHub` 持有每个角色的 `CharacterActor` 记录，连接不持有独立可回写状态。当前使用短临界区互斥协调，尚非完整的持久化命令邮箱。不同登录会话第二次入场返回 `CHARACTER_BUSY`；同会话换连接保留game_session_id并增加connection_epoch，旧连接不能移动或保存新连接状态。

仅支持单服务进程部署；不能将多个进程接同一数据库作为世界集群运行。1000是可配置准入上限，不自动等于容量达标。当前同步已升级为共享发布/增量协议v2，容量记录见[测试报告](../tests/capacity.md)。

## 接口

- `POST /api/v1/world/ticket`：Bearer认证，提交character_id、protocol_version=1、config_hash。返回20秒有效单次票据；数据库只存摘要，每登录会话最多一张，重新申请使旧票据失效。
- `/api/v1/world/ws`：升级后5秒内提交 `auth.exchange`，包含票据、protocol_version=1、world_sync_version=2和地图摘要。旧世界同步版本明确拒绝，不让旧客户端误读二进制增量。票据不放URL或日志。客户端对HTTPS地址使用WSS；服务本体监听HTTP，由公网TLS反向代理提供HTTPS/WSS。回环测试使用WS。浏览器Origin默认拒绝，P2a可通过正式HTTPS/本机开发两组精确白名单显式开放；来源通过不替代认证，也不代表Godot Web客户端可用，见[来源安全前置](../tests/web_origins.md)。
- `auth.ready`：返回character_id、game_session_id、connection_epoch、world_epoch、stream_id、world_stream_id、world_sync_version和地图标识。
- `world.move_to`：上述会话/代次及递增input_seq，target为两个整数；`world.stop`结构相同但无target。修订、代次与序号都是十进制字符串。停步完成正在经过的一格，不额外前进；断线立即冻结至最后确认格。
- `ping`/`pong` 保活，`world.leave` 显式退出。持续校验登录会话，撤销、过期、封禁关闭游戏连接。

## 快照与恢复

仅入场/重连发送一次完整不可变地图快照：`snapshot.begin` → 多个 `snapshot.chunk` → `snapshot.end`，每块最多32角色。所有块共享stream_id、seq=1和snapshot_id；块序号连续。SHA-256覆盖每块原始UTF-8 JSON前缀四字节大端长度及其正文。客户端验证数量、摘要、唯一角色ID/网络ID、所有块和自身身份后一次安装，不展示半包状态。begin携带base_world_seq，表示完整状态包含的权威发布边界。

此后每100ms接收一个共享二进制`VWD2`发布，包含进入/离开和发生变化的移动记录；静态昵称、职业等不随每次移动重发。每个移动记录26字节（短网络ID、格子/下一格、进度、实体修订、输入序号）。空闲时仍有70字节的连续权威边界，客户端不删除未变化玩家。精确布局与跨语言固定样例见`shared/protocol/world-sync-v2.json`。

所有连接订阅同一完整地图，因此world_stream_id/连续world_seq属于同一个完整世界公共流，不混用个人聊天序列。每tick只生成、排序并编码一次公共状态，发布后不可变，连接仅共享引用。初始快照的记录JSON按发布版本懒缓存并复用；排序、编码和网络等待均不持有世界状态锁。

订阅和捕获基线有同一个线性化点；新入场等待含自身所有权修订的发布，快照块发送期间不夹入增量，之后从base_world_seq+1连续处理。客户端先验证整包长度、SHA-256、流代次、序号、网络ID、生命周期、位置/修订范围，再原子安装本次变化；同UUID离开并以新网络ID进入也在一个发布内原子处理。不丢已编号的进入/离开事件。

发布队列仅保留32个共享tick（约3.2秒），发送超过2秒或读游标落后时断开并要求新连接全量同步，不能跳过旧增量后继续假装完整。上限1000角色、1MiB/发布，每次重连重新取得基线，不承诺无限增量补发。公共状态仅含外观、昵称、移动及相关版本，不公开资产或账号信息。网络ID在进程内单调分配，角色保留期内重连可沿用；流代次/连续序号防止旧离开消息删除新实体。

默认10秒保存位置，正常离开/断线也保存。owner_epoch与position_revision防止旧所有者或乱序保存覆盖；进程异常退出最多回退尚未保存的行走，不改资产revision。断线默认保留所有权15秒，同会话可恢复；过期记录在后续入场时保存并回收。数据库保存失败不释放该记录后再覆盖旧坐标。

客户端最多三次退避重连，停用移动直到新快照完整。线上场景不调用离线世界、任务、战斗或存档结算。[公共聊天](chat.md)使用独立有界频道，不影响移动快照序号；后续个人任务/PVE、切图与部署验证记录见 `tests/online_pve.md`、`tests/online_maps.md` 和 `deploy/WEB.md`。

验证命令及结果见 [共享地图测试](../tests/shared_world.md)。
