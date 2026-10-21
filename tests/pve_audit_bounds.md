# PvE 审计超限导致断线循环（2026-10-22）

线上只读日志核对：用户报告的 `pve.refused / DATABASE_UNAVAILABLE` 实际对应
SQLSTATE `23514`，PostgreSQL 拒绝 `security_audit_details_check`，不是连接池超时或数据库宕机。
首次采样的48次数据库错误均为这一约束；同一时段有3个角色受到影响。
不提交生产账号、角色标识、原始日志或连接配置。

原因是每条 PvE 操作将完整战斗、阵列、属性模板和回放信息重复写入 before/after，
超过已有16,384字节限制，连带回滚角色、战斗与操作回执。
客户端保留未确认的原 UUID，重连后重试又触发同一限制，表现为战斗卡住。

修复保留可读的战斗编号、版本、回合、结果、角色资源和各敌人气血，
其余战斗内容用原始 JSON 的 SHA-256 与字节数标识。
写入入口再按 PostgreSQL 实际 `jsonb::text` 字节数判断，过大的细节存储有标记的摘要；
保留身份、操作编号、结果与原细节指纹，尽量保留角色资源变化。
正常大小的审计不改变，非对象审计仍被约束拒绝。

没有扩大数据库限制、忽略审计失败、清除客户端待确认队列或删除玩家的活动战斗。
真实数据库失败仍须回滚事务。已有客户端和存档可直接使用服务端修复，无需客户端协议升级。

验证只使用独立 PostgreSQL 与测试账号：

- 原服务端复现：大回放战斗执行逃跑返回 `DATABASE_UNAVAILABLE`，服务日志为 `23514`。
- 修复后专项21项通过；此次旧式双份战斗日志为29,149字节。
  覆盖现有战斗重启恢复、逃跑成功、原 UUID 重连确认、只结算一次、其他玩家继续操作，
  以及注入真正审计故障时战斗／资源／版本／回执全部回滚。
- 实际调用 Rust `append()` 的 PostgreSQL 边界测试通过：恰好16,384字节、超过1字节、
  JSON紧凑序列化未超限但 jsonb 空格扩展超限、UTF-8多字节以及非法非对象。
- Rust全量测试通过；数据库边界项在专项提供的临时库中单独执行通过。
- 原有安全审计联调94项、单人阵列联调23项通过。

```powershell
$env:CARGO_TARGET_DIR='F:\project\Vssjx\work\npc-map-cargo'
cargo test --offline --manifest-path server/Cargo.toml
cargo build --offline --manifest-path server/Cargo.toml
$env:SSJX_TEST_SERVER_BIN='F:\project\Vssjx\work\npc-map-cargo\debug\vssjx-server.exe'
python -X utf8 tests/run_pve_audit_bounds.py
python -X utf8 tests/run_security_admin.py
python -X utf8 tests/run_solo_encounters.py
```

本文件记录源码验证，不代表已经更新线上进程；部署状态另行确认。
