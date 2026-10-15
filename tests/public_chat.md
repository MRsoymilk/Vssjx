# 公共聊天验收

内置表情及底部选择面板见[chat_emotes.md](chat_emotes.md)。当前客户端只将固定表情标记转换为贴图，其他标记保留原文；下方历史验证记录对应当时的客户端版本。

## 上线聊天范围修正

新上线角色从进入世界时的频道序号之后开始接收消息，不再收到上线前保留的公共聊天。世界快照同步期间的新消息仍会收到。短暂断线重连保留本次上线起点，显式离开后重新上线则重置起点；频道历史仍受原数量上限约束。

服务端聊天测试覆盖入场前历史隔离、同步期间消息、同会话重连、新会话重置与历史截断。客户端协议测试新增相同序号窗口的接受/拒绝检查；共享界面用已有40条消息的频道验证入场不添加旧聊天，后续新消息正常显示。`run_shared_world.py`补充后到角色与显式离开重新上线的真实连接断言。

本次验证：Rust 36项、Clippy全部target、Godot聊天协议48项、共享界面28项；Python 31项通过、1项跳过。当前机器缺少Docker/PostgreSQL工具，新增数据库集成断言未运行。服务端修改需要更新并重启服务后生效。

```sh
python tests/run_shared_world.py --render --output /tmp/opencode/vssjx-public-chat
godot --headless --path client res://tests/public_chat_test.tscn
cargo test --locked --manifest-path server/Cargo.toml
cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings
```

渲染依赖与本机Xvfb环境见 [共享地图测试](shared_world.md)。集成脚本创建临时PostgreSQL、Rust服务和两个独立Godot进程，不读私有.env，不保留账号凭据。`chat_checks.py`是协议/数据库断言，`client/tests/public_chat_test.gd`是客户端协议边界测试。

## 2026-10-15验证

- 双客户端真实OpenGL离屏：Alice 25项、Bob 28项，零失败。共8张640×960截图（入场、聊天、移动、重连），聊天面板标记按字面显示。
- 聊天双向发送；发送确认后清空；输入WASD不移动；聊天保持打开时远端继续移动；在线/离线存档哨兵隔离。
- 故障注入：Bob暂停网络接收，Alice先看见消息后Bob主动断线，重连原ID查询；两端只显示一次原消息，客户端无待确认残留。
- 真实服务器：身份由服务端决定、未认证聊天拒绝、去重/改内容冲突、控制符/超长/频道拒绝、账号禁言/到期恢复、个人限流；换连接仍能查询原消息；服务重启更换频道代次且历史为空。
- 客户端协议42项：严格字段、顺序/代次、无半批安装、重复消息拒绝、缓存上限、历史缺口恢复、未知消息原ID重试、重启/去重窗口过期不自动发送。
- Rust聊天测试覆盖FIFO公平队列、频道总预算、停顿不无限突发、历史上限、未过期回执不被逐出、回执过期回收及禁言后的原结果重放。
- Rust共22项测试通过，Clippy所有target以`-D warnings`通过。
- 账号UI回归18项、角色UI回归47项及对应PostgreSQL集成通过。

截图和进程日志：`/tmp/opencode/vssjx-public-chat/`。测试不承诺永久聊天历史、运营审计、管理UI、跨进程去重或1000人聊天容量。
