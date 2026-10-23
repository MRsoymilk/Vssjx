# 茶馆社区入口调整与自建论坛移除（2026-10-23）

## 授权与范围

- 用户明确要求完全移除 Flarum，并永久删除论坛数据库、上传文件和备份，不保留恢复副本。
- 保留线上现有“剑侠茶馆”名称、文案、样式和布局，仅将三个社区链接换为 `https://pd.qq.com/s/a6q695iaf?b=9`（腾讯频道【蜀山剑侠归来】）。不把游戏入口或下载改成尚未部署的统计跳转。
- 移除论坛专用部署、安装、代理、邮件、注册、备份、浏览器测试及相关旧维护说明；通用导航生成器不再带论坛开关。旧论坛地址通过通用缺失路径处理，不保留上游或迁移页。
- 不改变游戏包、APK、Rust 游戏服务、游戏 PostgreSQL、TLS 证书、游戏日志或玩家浏览器存档；不推送 Git。

## 本地验证入口

```sh
python -m unittest discover -s tests -p 'test_portal_page.py'
python -m unittest discover -s tests -p 'test_portal_routes.py'
python -m unittest discover -s tests -p 'test_documentation.py' -k test_local
python tools/prepare_portal.py --output /tmp/opencode/vssjx-channel-preview
node tests/portal_browser.cjs /tmp/opencode/vssjx-channel-preview /tmp/opencode/vssjx-channel-captures
```

浏览器只验证布局、原有展示、链接与请求边界，不自动进入或加入真实腾讯频道。Nginx 路由使用独立容器、临时证书和惰性游戏字节，验证404、游戏资源、下载、API及平滑 reload 下的既有 WSS 连接。

2026-10-23本地结果：门户静态6项、隔离Nginx／TLS路由9项、文档本地链接及锚点2项通过；真实Chromium四种窗口尺寸、显式游戏导航及隔离IndexedDB检查37项通过。截图在 `/tmp/opencode/vssjx-channel-captures/`，未构建或发布游戏包。

## 服务器执行状态

只读核对已确认：论坛为独立 `vssjx-forum-forum-1` 容器，数据库、上传、备份和凭据均位于 `/home/ssjx/services/vssjx-forum`，没有论坛命名卷；有一条专属调度任务和独立网络。现有门户三个论坛链接已确认，实际游戏／下载地址与仓库模板不同，因此远端只做链接替换及代理删除。

本条记录将在实际停用和清理验证后补充结果；截至本阶段提交，不将只读核对表述为已完成删除。
