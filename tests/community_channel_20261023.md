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

## 服务器执行结果

2026-10-23已完成实际清理，并在删除后再次只读核验：

- 线上门户只替换三个 `href`，其余HTML字节不变；未整份覆盖源码模板，原网页与APK入口仍为 `/webgame/` 和 `/downloads/vssjx-arm64.apk`。
- 删除论坛代理块，原位写入配置以保留单文件bind挂载；`nginx -t` 通过后平滑reload。旧 `/flarum`、`/flarum/`、管理、API和数据库路径均返回404，不保留迁移页。
- 删除独立容器 `vssjx-forum-forum-1`、网络 `vssjx-forum_default` 和镜像 `vssjx-forum:2.0.2-20261020`；无论坛命名卷，未执行全局Docker清理。
- 永久删除整个 `/home/ssjx/services/vssjx-forum`，包括SQLite数据库、上传文件、备份、安装归档、SMTP配置和管理员凭据，不保留恢复副本。
- 移除一条论坛专属cron；其他cron内容逐字保持不变。
- 游戏、PostgreSQL和Nginx容器ID、启动时间、镜像及挂载均不变；除门户HTML外，104份静态文件的SHA256全部不变，含游戏包与下载文件。未修改游戏数据库或重启游戏服务。
- 本地 `work/flarum-20261020/`、`work/flarum-smtp-20261020/`、同一论坛镜像及7个专属Python缓存文件已删除；未清理其他任务产物。

门户更新后SHA256：`ec62a5ca18fecb902107adc843c0ccf60932937bc78bbfc81283919a7da30e8c`。代理配置SHA256：`82080568982456de7092afda28314975cd7d22b63ee36ba7b9625f07c212044e`。

## 公网最终核验

实际Chromium使用正常TLS证书校验访问公网，37项检查全部通过：

- 1440×1000、390×844、320×740、844×390四种窗口无横向溢出；三处腾讯频道链接完整保留 `?b=9`，茶馆名称、文案及原游戏／下载入口保留。
- 页面不自动请求游戏、API、旧论坛或腾讯频道，无浏览器脚本或CSP错误；不自动进入或加入真实频道。
- 旧论坛与数据库路径返回404；尚未部署的 `/go/webgame` 仍为404。
- 游戏信息API返回200，账号接口保持401认证保护；网页游戏HTML与原APK下载均返回200。
- 已人工查看桌面和手机截图。公网截图及请求记录在 `/tmp/opencode/vssjx-channel-public-captures/`，验证脚本为 `/tmp/opencode/vssjx_channel_public.cjs`；不提交浏览器依赖或截图。

执行证据保存在本机 `/tmp/opencode/vssjx-community-navigation-result.json`、`/tmp/opencode/vssjx-community-deletion-result.json` 和 `/tmp/opencode/vssjx-community-local-cleanup-result.json`，不包含论坛数据或恢复副本。本任务仅提交相关源码与本验证记录，不推送、不打包。
