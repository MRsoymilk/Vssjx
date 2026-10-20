# 服务器地址与连接入口

[返回设计索引](README.md) · [账号](auth.md) · [网页部署](../deploy/WEB.md)

性质：**当前连接契约**。原生首次进入服务器栏默认为 `local`，有有效历史地址则回填；Web 也默认 `local`，可切换为构建控制的本站联机地址，不开放任意网络目标，见 [平台方案](platform_interface.md)。

Rust HTTP基础服务和Godot地址输入、独立持久化、服务发现已实现。账号认证已在后续增量接入，见[auth.md](auth.md)；不更改已确认产品策略，不把本地角色资产接入线上。

## 用户流程

```text
登录游戏 → 回填有效历史地址（首次为local）→ 进入本地游戏或输入联机地址
  → 查询服务信息 → 校验服务标识与协议版本 → 显示连接结果及当前开放范围
```

有效输入在失去焦点、点击保存并连接、返回或关闭页面时保存。非法草稿不覆盖上次有效地址；保存失败明确提示；网络失败不清空已保存地址。账号入口可注册/登录，现有离线入口不改变。

`local` 显示“进入游戏”，无需账号、密码或网络请求。Web 的服务器栏允许编辑模式选择，提示中提供本站联机地址；保存及发送请求时仍严格校验构建配置的同源地址与API前缀，不能改连外站，也不读写同步连接配置或保存密码。

## 地址格式

| 输入 | 规范化结果 |
|---|---|
| `127.0.0.1:8080` | `http://127.0.0.1:8080` |
| `192.168.1.10:9000/ssjx/` | `http://192.168.1.10:9000/ssjx` |
| `[::1]:8080` | `http://[::1]:8080` |
| `game.example.com` | `https://game.example.com` |
| `https://game.example.com/ssjx/` | `https://game.example.com/ssjx` |

- 接受HTTP/HTTPS，不接受文件路径、WS地址、内嵌账号密码、查询参数或片段。
- 清理首尾空白和末尾斜杠，协议与主机名规范为小写，保留路径大小写。
- 校验IP、域名标签、端口和路径前缀；国际化域名填写Punycode。
- 不自动降级HTTPS或关闭证书校验，不自动跟随重定向更换目标。
- HTTP用于当前本机/局域网连接检查；后续公网账号认证必须经HTTPS部署，不能将目前无密码的连接探测视为明文登录授权。

## 本地存储

`ServerConnectionSettings`将规范化地址写入`user://connection.cfg`的`connection.server_address`。先写临时文件再替换，保存内容不含密码、令牌或角色数据，与`shushan_save.json`隔离。启动或重新进入页面从磁盘读取，不依赖上一次页面对象仍在内存。

网络组件与地址存储分离。请求有超时和响应体大小上限；切换或关闭页面时取消请求，并通过请求代次拒绝迟到回调，不能在已关闭页面上更新状态。

## 当前服务发现契约

向规范化基地址追加`/api/v1/server-info`，只接受HTTP 200及JSON对象：

```json
{
  "service": "vssjx",
  "protocol_version": 1,
  "server_name": "蜀山剑侠 · 开发服务器",
  "version": "0.1.0",
  "stage": "connection_only",
  "capabilities": []
}
```

客户端核对服务标识、协议版本及名称类型/长度，拒绝普通网页、错误服务或不兼容协议。此接口是公开元数据，不发令牌、不创建会话、不加载角色。

未配置数据库时使用上述 `connection_only` 结果；启用数据库后 `stage=account_auth`，当前能力列表包含 `account_auth`、`character_creation`、`shared_world`、`public_chat`、`social_v1`。列表不是全部玩法能力清单，世界扩展仍经票据和握手协商。角色接口见 [characters.md](characters.md)，世界实现见 [shared_world.md](shared_world.md)。`/readyz` 在账号模式查询真实数据库，故障返回 503；发现成功不等于已经认证或进入世界。
