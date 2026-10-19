# 线上角色接口

[返回设计索引](README.md) · [账号与会话](auth.md) · [NPC 入派](school-membership.md)

性质：**当前实现契约**。角色槽位与昵称规则按当前迁移维护；已发布服务可能早于本仓库源码。

实现账号归属下的角色创建、读取和持久化回执。账号认证见[auth.md](auth.md)，进入游戏见[共享世界](shared_world.md)。创建完成后返回选角界面，必须明确选择角色再进入地图。

## 1. 角色身份与昵称

每账号最多五个线上角色，使用 `slot BETWEEN 0 AND 4` 与 `UNIQUE(account_id,slot)`。`0008_multiple_characters.sql` 将旧角色保留在零号槽位，移除旧 `UNIQUE(account_id)`，不删除角色或物品。全服昵称仍唯一，`UNIQUE(name_key COLLATE "C")`，不包含地图或实例。权限依赖不可变UUID，不依赖昵称。无在线改名、删除和名称释放接口，注销/禁用账号不释放昵称；离线存档不参与占名。

固定`nickname-v1`规则：仅去掉首尾U+0020普通空格；结果为2～12个Unicode标量，允许ASCII `A-Z a-z 0-9 _`及基本汉字U+4E00～U+9FFF。`display_name`保留英文大小写；`name_key`仅将ASCII大写转为小写，不进行系统locale转换、NFKC或扩展Unicode折叠。内部空格、制表/换行、零宽符、全角字母、组合重音、表情和扩展汉字均拒绝，不静默删除或改写。变更字符范围/归一化须新增版本并显式迁移及审计冲突。

客户端提示和服务端采用同一固定范围，共用正反样例位于[shared/protocol/nickname-v1.json](../shared/protocol/nickname-v1.json)。昵称比较本身不区分ASCII大小写，但同一操作ID修改显示大小写仍是请求内容变化。

## 2. HTTPS接口

全部要求`Authorization: Bearer <access_token>`，客户端仅允许HTTPS或本机回环HTTP；跟随账号刷新、过期和注销规则。响应`Cache-Control: no-store`，请求体上限4KiB。

### GET /api/v1/characters

返回`200`：`{"characters": [...], "rules_version":"creation-v1", "name_rules_version":"nickname-v1", "max_characters":5}`。数组为零至五个角色，按槽位、ID稳定排序；字段为角色基本行，不表示完整世界/库存/战斗快照。列表是当前读取，历史回执则保留创建当时结果。创建回执不能替换整个角色列表，也不能回滚已有角色的新修订。

### POST /api/v1/characters

请求schema：[character-create.schema.json](../shared/protocol/character-create.schema.json)。仅接受`operation_id`、`display_name`、`job`、`gender`、`school`、`rules_version`，拒绝未知字段和重复键；不接受账号归属、金币、HP、库存、name_key等权威字段。

`operation_id` 为带连字符的 UUIDv4。`job` 为 0 力士／1 侠客／2 隐者，`gender` 为 0 男／1 女，`rules_version` 固定为 `creation-v1`。兼容字段 `school` 接受 0～3，但新角色始终由服务端写为 3（闲云野鹤），不能通过请求直接入派；0／1／2 分别为峨眉／花涧／昆仑，正式入派见 [NPC 流程](school-membership.md)。结构层三个枚举为 u8、昵称至多 256 标量、版本至多 64 标量；新操作的业务校验在回执读取之后，避免新规则遮挡旧操作。

成功及重放均返回`201`：`{"operation_id":"<uuid>","character":{...},"replayed":false}`，重放仅将`replayed`改为`true`，保留原角色ID和创建时状态。角色字段包括ID、昵称、两种规则版本、职业/性别/门派、等级/经验/金币/HP/MP、任务阶段、地图ID/格子以及**十进制字符串**`state_revision`。不向客户端下发`account_id`或`name_key`。

| HTTP | code | 回执 |
|---|---|---|
| 409 | `NAME_TAKEN` | 终态，保留原输入，用户更换昵称后用新ID |
| 409 | `CHARACTER_LIMIT_REACHED` | 终态，刷新查看已有角色 |
| 409 | `IDEMPOTENCY_CONFLICT` | 原ID对应不同内容，不覆盖原回执 |
| 422 | `INVALID_NAME`、`INVALID_APPEARANCE`、`RULES_UNSUPPORTED` | 新操作的明确拒绝终态 |
| 400 | `INVALID_REQUEST` | 结构未受理，不生成回执 |
| 401 | `UNAUTHORIZED` | 未受理；重新认证后读取已有角色 |
| 429 | `RATE_LIMITED` | 未受理；稍后用原ID原内容重试 |
| 503 | `DATABASE_UNAVAILABLE` | 可能未提交或结果未知；查回执/原请求重试 |

终态拒绝响应包含`operation_id`和`replayed`；结构/认证/限流/数据库错误只包含`code`。摘要为紧凑UTF-8 JSON数组`["character.create:v1",去掉外层普通空格的显示昵称,职业,性别,门派,规则版本]`的SHA-256，不取原始JSON字段顺序或空白，不依赖JSON对象排序特性。

### GET /api/v1/character-operations/{operation_id}

只查询当前账号的操作，返回原终态的HTTP状态和结果并设`replayed=true`；未找到/其他账号回执统一`404 OPERATION_NOT_FOUND`。404只表示读取时无已提交回执，不保证其他在途请求已失败，仍可按原ID原内容重试。

## 3. 原子性与初始状态

新请求先做认证、结构和有界速率检查，事务内按账号行锁串行，再锁定并复核访问会话/禁用状态，然后读取原回执。命中原摘要先返回原结果；摘要不同则冲突。仅新操作检查角色数量、规则、枚举和昵称。不同账号抢名以唯一索引为最终防线，通过`ON CONFLICT DO NOTHING`稳定返回拒绝，不把数据库事务留在失败状态。

`creation-v1`固定沿用当前离线原型的初始规则：等级1、经验0、金币30、职业HP为120/95/85、MP为35/45/65、任务阶段0、青云山道`qingyun_trail`的(10,16)，修订`"1"`。同事务插入6份回春散和一把未装备青锋剑，再写账号回执，一次提交。后续玩法修改不允许通过重放创建回执再发初始资产。

明确业务拒绝也写紧凑终态回执。角色、物品、回执中任一步失败即全部回滚；确认提交后才返回成功。回执不做时间清理；未来归档仍需保留去重依据。速率沿用`.env`中的全局/IP窗口，创建额外按认证账号UUID使用`SSJX_AUTH_RATE_ACCOUNT`额度，不能换登录会话绕开账号窗口。

## 4. 客户端边界

账号面板登录后点击“线上角色”进入独立大厅，先读取角色再允许创建；昵称冲突保留输入，不自动加后缀。创建处理中锁定重复提交；结果未知时在`OnlineAccount.pending_creation`内存中保存原ID和原内容，锁定改名/选项，仅允许原请求重试。列表为空不能据此丢弃在途请求。

关闭页面不销毁账号或未决创建；重开页面读取已提交角色。重启或退出账号后只凭重新认证和服务端列表恢复，不持久化令牌、在线角色或本地操作日志。已有角色时仍可从菜单创建，五个槽位满后禁用创建；未决请求仍可按原ID重试。创建成功后重新读取完整列表并选中新角色，旧角色保持可选。左右切换及三人预览使用实际角色记录，五个指示点对应五个槽位；可通过独立按钮进入共享世界，不启动离线模拟。

在线角色不安装到`Game.player`，不读取/上传/覆盖本地存档。大厅中的角色状态与未来GameService/CharacterActor的世界快照尚不是同一层接口；后续接入需继续维持离线隔离和版本屏障。

内存会话清除会推进请求代次，旧角色/认证响应不能重新安装已清除身份的数据；注销结果仍可回报服务器是否确认撤销。
