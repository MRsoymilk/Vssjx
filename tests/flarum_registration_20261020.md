# QQ SMTP 与论坛注册开放（2026-10-20）

[论坛维护](../deploy/FLARUM.md) · [首次部署](flarum_release_20261020.md) · [测试导航](testing.md)

## 授权与结果

用户明确要求开放注册，并选择先配置 SMTP。用户在服务器受限文件中提供 QQ SMTP 配置；通过 Flarum 应用邮件服务向该邮箱发送“剑侠茶馆 SMTP 配置测试”后，用户确认“已收到，开放注册”，随后启用 `allow_sign_up=1`。

- 地址：`https://47.93.114.190/flarum/`，注册按钮和表单已开放。
- SMTP 为 `smtp.qq.com:465`、`ssl`，保持服务器证书校验，不关闭邮箱验证，不改用户／组权限。
- 未将邮箱、授权码或完整 SMTP 调试内容输出到聊天／提交仓库；配置仅在服务器内读取，通过标准输入传给维护进程，不放入命令行。
- 不创建生产测试账号、不发送测试帖子、不修改游戏、APK、玩家数据库或 Nginx，不重启任何现有容器，不推送。

## 核验

- SMTP 配置的文件属主、0600 权限、字段和 QQ TLS 参数检查通过。配置修改前已有独立论坛备份 `forum-20261020T063823Z.tar.gz`，保留于服务器私有备份目录。
- QQ SMTP 接受测试邮件，用户确认实际收到；不是仅以 TCP 连接成功代表投递。
- SMTP／注册维护工具单元测试 6 项通过，PHP 脚本语法验证通过；原论坛部署单元测试 5 项通过。
- 公网 HTTP 28 项通过，包含开放状态、资源、只读讨论 API、安全 Cookie 和敏感路径拒绝。
- 实际 Chromium 15 项通过，包含门户入口、桌面／手机、注册表单用户名／邮箱／密码字段、无异常或失败资源。没有提交表单创建账号。
- 论坛、代理、游戏和 PostgreSQL 的容器 ID、镜像、主进程 PID、启动时间、重启次数与本轮修改前一致，健康状态正常。
- 服务器侧检查确认公开论坛 HTML 不包含 SMTP 授权码或 `mail_password`。

验证命令：

```sh
python -m unittest discover -s tests -p test_flarum_smtp.py
python -m unittest discover -s tests -p test_flarum_deployment.py
python tests/check_flarum.py https://47.93.114.190/flarum --registration open
node tests/flarum_browser.cjs https://47.93.114.190/flarum work/flarum-registration-captures --registration=open
```

浏览器沿用 `PLAYWRIGHT_MODULE_PATH`／`PLAYWRIGHT_CHROMIUM_EXECUTABLE`，本地证据在忽略目录 `work/flarum-smtp-20261020/`。闭站部署的测试默认仍期望注册关闭，必须显式指定开放状态。

## 限制与维护

应用邮件服务真实发信与收信已核验；**未用真实账号完成注册激活或找回密码端到端测试**。保留 Flarum 内置验证，不以开放一个表单冒充上述完整验收。公开注册还需持续关注 QQ 发信配额、退信、垃圾注册与论坛资源使用。

SMTP 授权码会保存到独立论坛设置库，因此后续数据库备份也含秘密，应限制权限并在泄露时轮换。SMTP 维护工具要求注册先关闭，配置错误不应导致无邮件能力下自动开放。

文档局部的链接／片段／围栏回归通过；全量设计索引已有的 `audio.md`、`battle-hit-feedback.md` 缺口仍见首次发布记录，本轮不修改或掩盖无关文档问题。
