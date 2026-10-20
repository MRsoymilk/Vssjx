# Flarum 公网部署记录（2026-10-20）

[部署与维护](../deploy/FLARUM.md) · [门户设计](../design/portal-navigation.md) · [测试导航](testing.md)

## 范围和结果

用户明确授权“开始部署”后，在目标 `47.93.114.190` 新增独立 Flarum 2.0.2、PHP 8.3.35／Apache、SQLite 与简体中文 2.0.0。论坛地址为 `https://47.93.114.190/flarum/`，门户论坛按钮已开放。

本轮没有编译／替换游戏或 APK，没有访问玩家数据库，没有部署本地统计／APK 管理，没有推送。论坛数据库的首次安装和设置仅发生在独立 `state/forum.sqlite`。初始管理员使用随机密码，凭据留在服务器受限目录，不提交或输出。

公开注册关闭，邮件仅 log，占位管理员邮箱尚待交接；不是已完成 SMTP 和防滥用的全面开放运营。

## 安装与路由

- 部署基线源码：`87ccced`；后续检查／备份工具见 `d7cb01b`。
- 镜像 ID：`sha256:901df9daf6d20a5f4ca454094776a6df35ce189ffc659a1ad535f601adac79cf`。
- 独立 Compose 项目 `vssjx-forum`，应用容器 `vssjx-forum-forum-1`，仅监听宿主 `127.0.0.1:8082`。
- 上限 384 MiB 内存、512 MiB 内存加 Swap、0.75 CPU；首次资产准备后空闲约 95 MiB。
- 数据、凭据、原配置／门户／静态摘要及初始论坛备份位于 `/home/ssjx/services/vssjx-forum`，不在网页根目录。
- 现有 Nginx 先用已有镜像和证书卷在隔离容器解析候选，再原位写回绑定文件并平滑 reload，未重建代理。
- 已启用配置 SHA256：`401c5558f8057b8e64177a2a1b3b488dc8e268b43f60391f874190daca27111e`。
- 已启用门户 SHA256：`3e1c2bd57c84d2c09b022adb8d849de412d0eee1d02654e9e35f51a609f091c0`。

第一次代理切换在 reload 同一时刻立即请求，命中旧 worker 的 404 后按预设恢复原配置；补充有界就绪等待后重新切换成功。没有为通过验收重启游戏、清理数据库或放宽认证。

## 验证

| 项目 | 结果 |
|---|---|
| 首次安装、代理局部合并、门户链接、隔离和在线备份单元测试 | 5 项通过 |
| 既有门户／统计／APK 管理本地回归 | 39 项通过 |
| 本地真实 Chromium | 13 项通过，含临时管理员登录与管理页 |
| 公网 HTTP | 28 项通过：中文、canonical URL、资源／字体、只读讨论 API、关闭注册、安全 Cookie、私有路径拒绝 |
| 公网真实 Chromium | 14 项通过：门户链接及无预加载、中文 JS、桌面／手机、资源无失败、无未捕获异常、首次无第三方请求 |
| 论坛初始备份 | SQLite 在线快照完整性正常，初始一个管理员，注册关闭；配置与 assets 在归档内 |
| 游戏／Nginx／PostgreSQL | 原容器 ID、镜像 ID、PID、启动时间和重启计数完全相同；游戏／数据库保持 healthy |
| 原静态文件 | 原 92 个文件中仅 `navigation/index.html` 更新论坛链接，另外 91 个大小与 SHA256 一致，含游戏和 APK |
| 现有接口与 WSS | `/webgame/`、发现接口正常，未认证接口 401；合法 Origin 升级 101，未知来源 403，未交换玩家票据 |

`/go/webgame` 仍为 404，确认没有误发布未授权的统计入口。论坛会话 Cookie 保持 `/flarum`，未清理或读取玩家浏览器存档。

文档链接、图片、片段和代码围栏等 4 项检查通过。全量文档 6 项中另有 2 项测试失败（4 个子案例）：既有 `design/audio.md`、`design/battle-hit-feedback.md` 未登记设计索引、缺少返回导航和状态标注。已对照部署前的 `d27ebbf` 确认原有缺口，本轮未改动这些无关专题，也未放宽检查规则。

新增仅论坛的每分钟调度任务，保留原用户 crontab。已有一次手动备份，未配置自动／异机备份。后台管理登录未使用生产密码在本机自动化；未在生产论坛创建测试讨论、上传或虚构用户。

命令入口：

```sh
python -m unittest discover -s tests -p test_flarum_deployment.py
python tests/check_flarum.py https://47.93.114.190/flarum
node tests/flarum_browser.cjs https://47.93.114.190/flarum work/flarum-captures
```

浏览器依赖可通过 `PLAYWRIGHT_MODULE_PATH`、`PLAYWRIGHT_CHROMIUM_EXECUTABLE` 指定已有 Playwright／Chromium。只有回环临时论坛允许向脚本传入第三个凭据文件参数，公网模式保持游客只读。

本机证据与截图保留在 Git 忽略目录 `work/flarum-20261020/`，包括本地安装与构建记录、公网最终检查及截图。未用手机真机、真实用户发帖、邮件投递、并发和长稳测试替代上述局部结论。
