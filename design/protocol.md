# 联机协议：设计原则与目标契约

[返回设计索引](README.md) · [架构](architecture.md) · [共享地图实现](shared_world.md)

性质：**目标契约，不是可直接调用的完整 API 清单**。基础设计于 2026-10-15，状态说明于 2026-10-19 整理。账号、角色、世界、PVE、社交、队伍和决斗已有实现，但下文通用 `battle.command`、`operation.get` 等示例不代表实际已公开消息。当前 PVE 使用 `pve.command`／`pve.result`；世界 v2 使用二进制共享发布，而非完全采用本稿的订阅增量模型。

实际契约见 [账号](auth.md)、[角色](characters.md)、[共享地图](shared_world.md)、[聊天](chat.md)、[社交](social.md)、[队伍](teams.md)和[决斗](player-duels.md)，并核对 `shared/protocol/`、源码与对应测试。昵称规则已冻结为 `nickname-v1`，不再是待设计项。D 编号的历史差异见 [设计索引](README.md)。

## 1. 传输、认证与连接接管

HTTPS处理注册、登录、刷新/撤销登录会话、角色列表/创建和连接票据；WSS处理角色进入世界后的移动、聊天及业务操作。账号、控制及初始快照使用UTF-8 JSON；当前世界增量v2使用同一WSS连接的紧凑二进制发布，见[shared_world.md](shared_world.md)与`shared/protocol/world-sync-v2.json`，旧世界版本明确拒绝。路由前缀使用`/api/v1`。

客户端经已认证HTTPS接口取得短时、单次、绑定登录会话和角色的票据，在WSS首条`auth.exchange`消息中交换。票据不可放URL查询参数，消费必须原子；认证失败的票据是否已消费以服务器结果为准，客户端直接申请新票据而非盲目复用。认证超时关闭，未认证连接不得加载世界、订阅聊天或执行昂贵业务。

握手携带协议版本、配置清单版本/摘要及目标角色ID。服务器检查登录会话有效性、角色归属、封禁、协议兼容、配置兼容和在线占用。返回`auth.ready`时给出`game_session_id`、`connection_epoch`、服务端时间及限额；随后先同步，不直接开放业务操作。

同一有效登录会话的网络重连可以接管同一角色的原连接，`connection_epoch`递增，旧连接失去输入资格。当前不同登录会话占用同一角色返回 `CHARACTER_BUSY`，不自动顶号；每账号最多五个角色，不能由此推导账号级唯一游戏连接已实现。独立于连接的完整业务执行器仍为架构目标。进程重启后的 `game_session_id` 不能与旧连接混用，任何断连或接管都不能撤销已提交资产。

刷新令牌轮换、注销、过期及封禁同步到活动WSS；业务受理前检查当前权限。客户端不无限重试被封禁、无角色归属、重复登录或不兼容版本。浏览器Origin规则、原生连接的认证和代理信任边界见架构安全章节。

### 1.1 角色创建与昵称占用

HTTPS角色创建提交operation_id及昵称、职业等类型化创建字段；账号身份取自认证，不接受客户端指定归属或初始金币/属性。D08已确认线上角色昵称全服唯一，不按地图或实例分别占名。昵称校验及name_key规则见[架构7.4节](architecture.md#74-昵称全服唯一与创建角色)，具体请求schema与规范化正反样例在M0/M1固化。

账号级幂等顺序同第3节：先查原创建回执，再对新操作校验五槽容量、昵称和初始规则。创建角色、初始状态与回执同事务提交，槽位和 name_key 受数据库约束。成功提供原 character_id 与 display_name；同 operation_id 同内容重试返回原角色，不因昵称已占用报 NAME_TAKEN。

新操作重名返回 HTTP 409 及 `NAME_TAKEN`；五个角色槽位已满返回 HTTP 409 及 `CHARACTER_LIMIT_REACHED`；非法昵称返回 `INVALID_NAME`。重名保留输入，不自动加后缀或随机创建。用户更换昵称后用新 operation_id；同 ID 改内容返回 `IDEMPOTENCY_CONFLICT`。未知结果只能查原回执或原 ID 原内容重试。

首版不增加在线改名、删除或名称释放操作，客户端可用性检查不代表占名保证。不同登录会话断开/封禁/注销均不释放昵称；离线重名不参与线上唯一索引。

## 2. 消息、标识与版本（目标示例）

客户端持久化操作示例：

```json
{
  "protocol_version": 1,
  "type": "battle.command",
  "request_id": "request-001",
  "operation_id": "operation-001",
  "game_session_id": "game-session-001",
  "connection_epoch": "12",
  "payload": {
    "battle_id": "battle-001",
    "expected_revision": "3",
    "command": "attack"
  }
}
```

响应示例：

```json
{
  "protocol_version": 1,
  "type": "response",
  "request_id": "request-001",
  "operation_id": "operation-001",
  "game_session_id": "game-session-001",
  "connection_epoch": "12",
  "ok": true,
  "payload": {
    "battle_id": "battle-001",
    "revision": "4",
    "state_revision": "20",
    "replayed": false,
    "events": []
  }
}
```

样例ID只用于展示结构；实现使用足够随机、不会重复的ID（如UUID），不得以固定样例ID发起真实修改。

| 字段 | 契约 |
|---|---|
| `request_id` | 单次请求关联；重试可以变化，响应关联当前请求 |
| `operation_id` | 同一业务操作的稳定身份；不因超时/断线/重试改变 |
| `game_session_id`、`connection_epoch` | 当前接入会话及连接隔离；服务器认定，不接受客户端选择有效代次 |
| `world_epoch` | 本人世界归属/可移动阶段代次；世界操作携带期望值，切图/进出战斗后旧值失效 |
| `stream_id`、`seq` | 某订阅实际发送的实时事件流及顺序；不是全地图全局事件号 |
| `state_revision` | 同一次业务提交的组合结果编号/快照版本；不是所有命令的共同冲突键 |
| 各领域revision | 属性/货币、库存、任务、战斗各自的业务版本；只对相关领域检查 |
| `input_seq`、`route_revision` | 移动输入确认和路线替换，不是持久化幂等键 |

ID作为有长度上限的不透明字符串处理。epoch、seq、revision统一使用规范十进制字符串，范围`0..9223372036854775807`，拒绝前导正号、前导零（单个0除外）、小数、负数和溢出，不经浮点中转。接近上限时受控新建代次/流，禁止回绕。协议版本、坐标、数量、毫秒时间使用显式有界整数；JSON数值不得超出精确整数范围，业务限制优先于通用数值上限。

消息类型、枚举、必填字段、未知字段策略和最大递归深度由schema固定。持久化命令拒绝未知字段以避免被摘要忽略的隐藏语义；未来新增字段通过协商版本演进。拒绝NaN/Infinity、重复JSON键、超长字符串/数组、非法坐标和客户端提交的权威伤害/奖励值。

不同流没有全局顺序保证。客户端先检查当前会话/世界/stream_id，再应用事件；历史回执中的业务修订早于当前快照时，只展示“原操作已完成”，不能覆盖新状态或重播已消费动画。

## 3. 持久化命令与幂等处理

### 3.1 受理顺序

```text
鉴权、归属、当前连接与结构校验；入口资源限额
  → CharacterActor查询同operation_id回执或在途状态
  → 同键核对操作类型与规范化业务内容
  → 已有终态：返回原结果；在途：等待或返回PENDING
  → 只有新操作才校验expected_revision、世界阶段、目标、资源、节奏
  → 锁定角色行，复核owner_epoch、幂等键及业务状态
  → 原子写业务、领域版本、state_revision与回执
  → 确认提交后更新权威内存，再响应/推送
```

原操作从revision=3推进到4后，即使角色后来已到revision=5，用原ID和原payload重试仍返回该操作的原终态，不先报`STALE_REVISION`。新ID携带旧版本才报冲突。同ID但更改目标、数量、expected_revision或命令类型，返回`IDEMPOTENCY_CONFLICT`。

请求摘要由服务端对schema解析后的规范化业务数据计算，包含操作类型、角色作用域、目标/参数和业务前置版本；不包含request_id、票据、game_session_id、connection_epoch或JSON键排列顺序。缺省字段如何展开在schema中定义。世界操作payload中的world_epoch具有业务含义，属于摘要，不可重试时偷偷替换。字符串规范化遵循各字段规则，不擅自改写签名等用户内容。

幂等作用域是`(character_id, operation_id)`；账号级创建角色等HTTPS修改按账号作用域使用相同原则。角色/账号归属变化或无权访问时先拒绝，不允许通过operation_id查询别人数据。应用层预查与数据库唯一约束都要保留，不能先查不存在再无约束写入。

已经受理的有效命令，其成功或终态业务拒绝可写入稳定回执；格式错误、未认证、未受理的入口限流不产生无界持久化记录。被明确拒绝后改变业务意图需新ID；结果未知时绝不能用新ID“再试一次”。数据库死锁/可确认回滚可以有界重试同ID；提交结果未知时不得当作已回滚重算随机结果。

### 3.2 操作结果查询

`operation.get`提交原operation_id，服务端仅允许查本人作用域：

| 状态 | 含义与客户端动作 |
|---|---|
| `COMMITTED` | 已提交，返回原结果/版本；只应用不落后于当前快照的状态 |
| `REJECTED` | 该操作确定被业务拒绝；展示原因，不自动改成新操作 |
| `PENDING` | 已受理或正在查清结果；退避查询，不能重复扣款 |
| `NOT_FOUND` | 当前尚无可读回执；不能据此证明原事务失败，只允许同ID同内容重试 |
| `RESULT_ARCHIVED` | 保留明确COMMITTED/REJECTED终态和摘要，完整历史内容已归档；取当前快照，不重新执行 |

数据库不可读返回`SERVER_UNAVAILABLE`或`RECOVERING`，不能伪装成NOT_FOUND。在途操作无法确定结束时，服务端保持角色恢复屏障。服务端返回的短暂PENDING提示不是持久化成功承诺。

完整事件归档不删除紧凑去重终态；保留和未来代际退休规则见架构。查询结果和重放响应都与当前request_id、当前连接关联，业务结果仍是原操作的结果。

## 4. 业务操作清单

以下是拟议消息名，完整payload须在各阶段实现前冻结。只接受意图和目标身份，不接受客户端给出的金币增量、物品价格、伤害、击杀结果或奖励内容。

| 操作 | 消息 | 关键约束/返回 |
|---|---|---|
| 进入/恢复世界 | `world.enter`、`state.sync` | 组合本人快照、地图订阅、私有目标、活动战斗；完成同步后才允许操作 |
| 移动/停止 | `world.move_to`、`world.stop` | world_epoch、input_seq、目标格；返回确认序号、路线与权威位置 |
| 他人变化 | `entity.enter/update/leave`（服务端事件） | 按订阅生命周期与可见范围发送公开字段 |
| 查看交互选项 | `world.interact`，action=`inspect` | 只读、目标归属/距离校验；不推进回合或任务 |
| 开始个人战斗/传送 | `world.interact`，action=`challenge`/`portal` | operation_id、world_epoch、服务器目标ID；前置任务、预约和事务转换 |
| NPC恢复 | `world.interact`，action=`restore` | operation_id，NPC身份/距离；属性恢复和回执原子提交 |
| 接受/领取任务 | `quest.accept`、`quest.claim` | operation_id、任务实例/阶段/修订和NPC目标；服务端重查距离/资格及奖励来源唯一性 |
| 用药/装备/卸下 | `inventory.use/equip/unequip` | operation_id、物品/堆叠实例ID、相关revision；战斗中限制冲突操作 |
| 买药/丢弃 | `inventory.buy/discard` | operation_id、报价定义ID或库存实例ID、数量、相关revision；价格由配置，容量/数量/归属校验 |
| 调息 | `character.rest` | operation_id、相关revision；非战斗状态，服务器扣费并恢复 |
| 门派/签名 | `character.set_school`、`character.set_signature` | operation_id、角色revision、类型化值；不接受任意角色字段patch |
| 战斗指令 | `battle.command` | operation_id、battle_id、expected_revision、命令；同回合唯一，资源与随机状态原子提交 |
| 公共聊天 | `chat.send` | 客户端消息ID、public频道、纯文本；短期去重和全局限流 |
| 操作查询 | `operation.get` | 同一认证主体下的原操作状态，不改变业务 |
| 应用心跳 | `ping`/`pong` | 服务端时间、连接健康，不延长战斗闲置期限 |

`world.interact`中的action必须是闭合集合，不能由客户端指定函数名；inspect是只读，challenge/portal/restore是持久化操作。任务领取也要在提交前重新校验NPC交互资格，不能无限使用几分钟前弹窗留下的资格。目标证明过期的新操作返回拒绝；已经完成的原operation_id先按回执处理。

背包排序首版只是本地显示偏好，不改变实例ID或服务器容量。当前购药来自背包入口，不擅自增加必须到商店的距离门槛。现有未接任务不能挑战、任务前置不足不能传送、领奖恢复与战败回城均迁入服务端；不顺便更改现有数值。

## 5. 移动契约

服务端计算路线，客户端点击目标格，键盘按有界频率提交短目标。限速在寻路前执行，合并待处理旧目标不能带来额外位移。

权威状态至少包含map_id、instance_id、world_epoch、from_cell、to_cell、segment_progress、route_revision、server_tick和last_processed_input_seq。segment_progress采用有界定点值，例如`0..1000`；服务器内部精度可更高，不依赖客户端数值。停止/换路线要从当前合法段衔接，下一格必须四向相邻、未阻挡；不得因新目标而跳过中间格。

`input_seq`在当前连接内递增，拒绝重复或倒序输入。重连清除客户端未确认旧路线，获取新权威状态后开始新输入域。普通world.stop完成当前格后停止；关键转换/反作弊校正由服务端给出合法格中心，不能用反复停止重置移动计时获得加速。

10Hz是初始地图调度/同步建议，动画帧率与其分离。更新包含服务器时间/进度，客户端进行局部预测、确认后纠正，远端采用插值；不得按收到包的次数推进脚步。按已确认D01、D02，以全服1000人混合游玩为目标，单实例热点另测；首版不自动分线、不按人数隐藏本应可见的玩家。

## 6. 分批快照、增量和一致恢复

### 6.1 流与实体生命周期

每个订阅有独立stream_id；实时消息的seq在可合并位置整理完、最终进入有序发送队列时分配。同地图其他玩家收到了什么，不影响本订阅的seq连续性。切图、重连、重新同步创建新流，旧流立即停用。

位置更新使用带entity_revision的完整可替代公开状态，不发送依赖每一条旧位置的差分。只允许在同一实体、同一可见生命周期、尚未分配seq的区间内合并；不能跨越enter/leave合并。已经编号的可靠消息若无法发送，关闭流并重同步，而不是悄悄跳号。

每个实体引用包括`entity_id`和本订阅的`visibility_generation`。离开再进入可见范围递增generation，enter带完整公开快照；旧generation的update/leave不能作用于新进入的实体。不要把任务、背包、随机状态、账号标识混入公开玩家DTO。

### 6.2 快照消息

| 消息 | 必需信息 |
|---|---|
| `snapshot.begin` | sync_id、snapshot_id、domain、stream_id、map_id/instance_id（地图域）、world_epoch、config_hash、base_seq、总块数、总实体数 |
| `snapshot.chunk` | sync_id、snapshot_id、stream_id、chunk_index（从0开始）、有界records |
| `snapshot.end` | 对应身份、总块数、总实体数、快照摘要 |
| 后续实时事件 | stream_id、递增seq、实体生命周期/业务revision及payload |
| `sync.ready` | sync_id、已完成领域、本人state_revision和world_epoch；客户端完成安装后才恢复交互 |

快照摘要固定为SHA-256：按chunk_index顺序，将每条完整snapshot.chunk应用消息的原始UTF-8 JSON字节前加4字节无符号大端长度，再依次输入哈希。snapshot.begin/end不参与，摘要以64个小写十六进制字符表示。服务端对实际将发送的消息字节计算，客户端对WebSocket重组后的原始消息字节计算，不重新序列化Dictionary、不提取JSON子树、不包含WebSocket帧头。重复块只校验字节相同而不再次计数；M0提供固定字节与摘要样例。摘要用于完整性检查，不代替TLS或权限校验。

新建流的base_seq从0开始。MapActor在一次有界串行步骤中取得不可变可见快照，并登记该边界之后的事件；编码/分块可以异步，但不能在不断变化的实体字典上边遍历边拼接不同时间点的数据。快照完成前缓存该订阅后续事件，允许按上述规则合并位置，不允许遗失实体生命周期。

客户端先构建临时世界，校验块号唯一/齐全、数量、摘要、配置和世界代次。收到end且校验通过才原子替换显示状态，再应用base_seq之后的增量。收到leave后不能再把旧snapshot.chunk叠回当前世界；已废弃snapshot_id的分块一律忽略。

每个快照限制单块字节、总字节、总块数、构建/发送时长及尾部事件积压。超过预算、漏块、重复块内容不同、实时seq缺口或版本冲突时废弃本次同步，申请新快照；重试也有退避和次数保护。不能通过悄悄少发实体来满足预算，预算与D01/D02的承诺不匹配时应明确报容量不足。

### 6.3 本人与地图同步屏障

完整重连流程由CharacterActor先查清前一写入，暂不接受本人新修改/跨图转换；MapActor按当前world_epoch确认本人合法状态并建立地图快照边界。属性、库存、任务、活动战斗组成同一state_revision的个人快照，世界快照是其当前归属；其他玩家继续运行，不为同步一个人暂停整个地图。

个人业务推送在快照读取边界同时登记并缓冲，和地图流一样从对应base_seq衔接；不能在读完快照后才订阅，留下丢更新窗口。读取屏障只覆盖捕获一致状态，不跨越慢网络长期持有数据库事务。被同步的连接在sync.ready之前不接受普通修改，重复同步有资源预算。

切图/进出战斗导致world_epoch变化时，中止未完成的旧世界同步并重新开始，不能安装“一半旧图、一半新业务”。state.sync的单领域查询只更新该领域版本，不把多次独立查询拼成新的组合快照。不保证地图里所有其他人的业务也处于同一数据库时间点，公开实体按各自流边界一致。

## 7. 战斗事件与播放

battle.command先执行第3节幂等流程，再计算玩家行动、敌方行动和回合结算。每个成功改变状态的回合提交后，返回新battle_revision、相关领域修订及有序事件。最终回合同时提交胜败、资源、个人遭遇、任务、奖励、世界状态和回执。

事件包含稳定event_id（例如battle_id+revision+事件序号）、行动者、目标、动作类型和必要结果。伤害、恢复、消耗及奖励由服务端确定；客户端不重抽随机数，不靠动画结束调用本地奖励函数。

battle快照包含battle_id、rules_version、revision、回合、双方公开状态、可接受指令、最早下一指令时间、当前截止时间和结算状态，不包含内部随机状态。客户端动画状态与业务快照分离：快照可以已经是本回合终态，画面仍按事件分段播放，不能随后用旧动画血量覆盖新快照。

有效指令限定现有attack、skill、potion、guard、flee；查看是只读，不推进回合。自动战斗只是按相同节奏提交同类指令，断线时不能在客户端缓存一串随后突发提交。重连默认恢复最新快照，旧动画可跳过；历史回执相同event_id不再次消费。

已确认D04：断线冻结60秒并停止自动下指令，超时或在线连续5分钟无有效指令按主动逃跑结束，保留已提交消耗且不发胜利奖励，不套用战败回城处罚。相应deadline写入战斗的版本化状态，客户端不得自行延长。timeout由服务端稳定操作ID提交，与玩家命令争用同一角色串行与战斗修订：谁先有效提交谁生效，另一方看到已结束/旧版本，不重复结算。无效指令、查看、心跳、换连接不能无限延长deadline。维护/服务器恢复中的计时按架构规则区分处理。

## 8. 公共聊天

当前 `chat-v1` 已实现，使用 `chat.ready` / `chat.batch` / `chat.result` 和独立channel_epoch/seq；批次每次最多16条。下述 `chat.message` 字段对应批内消息记录，具体格式、短期回执/重启边界见 [chat.md](chat.md)。

chat.send只提交client_message_id、channel=`public`和纯文本。身份、名称、消息ID和时间来自服务器，未认证连接不能订阅或读历史。

先验证字符/字节上限、控制字符、禁言、个人限额，再进入公平的频道总预算。限额建议值见架构，可通过握手公开给客户端；服务器限制始终是权威。短期去重以角色和client_message_id为作用域；同ID不同文本拒绝。队列已满时不能先确认接纳再静默丢弃。

chat.message包含message_id、sender_character_id、display_name、server_time_ms、channel和text。聊天使用独立订阅流，不能要求客户端接收全世界所有内部消息序号。慢连接超过队列预算断开，有限历史可能出现chat.gap提示；不承诺完整补发或永久历史。客户端节点、字符串和通知队列均限制条数/字节数，按纯文本渲染。

## 9. 重连、错误与限额

连接状态按`CONNECTING → AUTHENTICATING → SYNCING → READY`推进；断开后停止新业务意图提交，使用退避与随机抖动，经HTTPS申请新票据。再次登录/换账号时清空旧会话订阅与缓存；线上缓存按服务器和角色隔离，不混入离线存档。

重连先绑定原角色执行器、隔离旧连接，再查询结果未知的operation_id并同步权威状态。原操作确认前不自动新建相同业务意图。服务端接受新连接不代表旧事务已经失败或旧战斗已经结束。

错误对象包含稳定code、用于显示的message、retry_mode（none/backoff/sync/query_same_operation）及可选retry_after_ms；修改请求还明确outcome（not_accepted/rejected/unknown）。客户端不得按中文提示匹配业务分支；传输断开或无错误对象的超时一律视为可能未知。

| 错误码 | 含义/动作 |
|---|---|
| `UNAUTHENTICATED`、`FORBIDDEN`、`SESSION_REVOKED` | 重新认证或终止，不能自动继续经济请求 |
| `PROTOCOL_MISMATCH`、`CONFIG_MISMATCH` | 更新兼容版本，拒绝错误地图运行 |
| `CHARACTER_BUSY` | 重复上线按D03处理；角色在同步/事务阶段则按明确retry_mode处理 |
| `STALE_REVISION`、`STALE_WORLD` | 只用于未执行的新操作；同步相关状态，再由用户意图决定是否新建操作 |
| `IDEMPOTENCY_CONFLICT` | 同ID业务内容不一致，拒绝，不自动换ID绕过 |
| `NAME_TAKEN` | 新创建操作的昵称全服已占用；提示用户更换，不自动加后缀/改名创建 |
| `CHARACTER_LIMIT_REACHED` | 新创建操作超出每账号五个角色槽位；先同步既有角色，不自动删除或覆盖 |
| `INVALID_NAME` | 昵称不符合服务端统一校验规则；提示修正，不将格式错误伪装成重名 |
| `INVALID_TARGET`、`INSUFFICIENT_RESOURCE` | 业务拒绝，展示原因 |
| `RATE_LIMITED`、`SERVER_BUSY` | 入口/队列保护；依据outcome和retry_mode使用原ID退避 |
| `RECOVERING`、`SERVER_UNAVAILABLE` | 不把未知业务当失败；query_same_operation，禁止新ID重复购买 |
| `RESYNC_REQUIRED`、`SNAPSHOT_LIMIT` | 流不连续/同步超过预算；有限重同步，不静默漏发可见实体 |

实施时冻结并配置以下上限：认证期限和未认证消息量、完整WebSocket消息字节数（含碎片重组/解压后）、JSON深度和数组长度、快照块/总大小、入出队列消息数/字节/最长滞留、寻路输入频率、在途事务与数据库等待时间、聊天个人/全局配额和重连预算。解析前检查消息长度，超限后不继续分配大对象。限额变化必须进入测试环境记录，不用无限放宽消息或队列掩盖设计问题。
