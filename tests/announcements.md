# Web 全局通知与游戏滚动公告

在已有监控页面`http://127.0.0.1:9090/`增加“全局通知”：输入1～240字，设置有效期（页面1～1440分钟，默认10分钟），发布、替换或撤下。当前仅保留一条有效通知，重启服务会清空；local模式不接收服务端公告。

## 推送与显示

入场票据响应声明`announcement_version:1`后，新客户端才在`auth.exchange`声明相同版本；旧服务器仍收到原有握手。服务端沿现有认证世界WebSocket，每100ms检查通知修订，只在初次连接、发布、替换、撤下、到期时发送`announcement.state`。旧客户端未声明版本时保持原行为。通知独立于聊天序列与上线聊天窗口，有效期内新上线/重连可收到当前通知；不重放已过期通知。

消息字段：`epoch`（进程UUID）、`revision`（十进制字符串）、`notice`（空值或包含`id`、`text`、`remaining_ms`、`expires_at_ms`的对象）。服务端使用单调时钟到期，客户端依据剩余毫秒设置本地截止时间，不依赖设备墙上时钟。重复修订不重新启动滚动，撤下、断线和离开游戏清除显示。

显示由`client/scenes/ui/announcement_banner.tscn`定义，使用游戏古铜底、金色边框与文字；在主场景独立CanvasLayer上显示，文字裁切后以36逻辑像素/秒从右向左循环，所有控件忽略鼠标，不阻断移动、聊天或菜单。

## 运维接口

- `GET /api/announcements`：本机页面读取当前通知与本进程操作令牌。
- `POST /api/announcements`：JSON包含`request_id`、`text`、`duration_seconds`（服务端10～86400秒），要求`X-Announcement-Token`。相同有效请求重试不延长截止时间，同ID不同内容拒绝；最近64个已结束/替换的ID不允许重试复活。
- `DELETE /api/announcements`：JSON包含目标通知`id`并携带操作令牌，旧页面无法撤下已被新通知替换的内容。

三个接口仅存在独立本机监听；游戏HTTP端口没有写入入口。继续校验真实回环对端、回环Host和Fetch Metadata；Origin仅允许与Host一致的本机HTTP来源。请求体有界，未知字段、特殊控制符、无效时长被拒绝；换行整理为单行。通知内容按普通文字显示，不解析HTML或富文本，也不写入日志正文。网页状态修订防止旧刷新响应覆盖新发布结果。

## 验证

```sh
cargo test --locked --manifest-path server/Cargo.toml
cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings
godot --headless --path client res://tests/announcements_test.tscn
python tests/run_announcements.py --render --output /path/to/artifacts
```

后一个脚本启动独立的真实Rust服务（临时端口、不配置数据库、不读取私有.env），用Playwright Chromium/Edge实际点击发布、替换与撤下，保存桌面/手机页面截图。将真实发布响应原样交给Godot网络分发和两个独立通知通道，检查主场景横条和截图。可通过`--server-bin`指定独立编译目录的程序，使用`GODOT_BIN`、`NODE_PATH`、`PLAYWRIGHT_CHROMIUM_EXECUTABLE`指定本机运行依赖；测试不会对当前服务发布示例消息。

本次通过：Rust39项、Clippy零警告；通知协议/界面22项（真实HTTP响应及渲染26项）；真实浏览器11项（含同源POST、撤下后刷新与HTML原文显示）；同屏界面28项、世界增量50项、移动控制35项、登录页48项、单人整流程383项；Python33项通过、1项跳过。当前环境未运行PostgreSQL认证下的真实双客户端世界联调，本测试不将两个独立协议消费者称作两条真实认证世界连接。
