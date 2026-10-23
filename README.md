<p align="center">
  <img src="client/assets/ui/app_icon.png" width="144" height="144" alt="蜀山剑侠 · 归来：AI 绘制的女性 Q 版剑侠图标">
</p>

<h1 align="center">蜀山剑侠 · 归来</h1>

<p align="center">以经典像素剑侠世界为起点，用 Godot 与 Rust 重新构建的回合制 RPG。</p>

<p align="center">
  <a href="https://47.93.114.190/">项目门户</a> ·
  <a href="https://47.93.114.190/webgame/">网页体验</a> ·
  <a href="https://47.93.114.190/downloads/vssjx-arm64.apk">Android 预览版</a> ·
  <a href="https://pd.qq.com/s/a6q695iaf?b=9">剑侠茶馆</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="design/README.md">设计文档</a> ·
  <a href="CONTRIBUTING.md">参与贡献</a>
</p>

## 关于项目

**Vssjx** 基于《蜀山剑侠Online》320×480 客户端的静态资源分析，重新编写游戏客户端与联机服务。项目保留像素美术和竖屏交互，支持本地独立存档与服务器权威的多人玩法。

这不是原版客户端运行器，也不是原服务器复原：不执行原始 MR 字节码或 ARM 扩展，不连接原服务器。地图布局、任务、数值和战斗规则包含重新设计的内容；AI 扩展与原版恢复资料分别标注。

## 项目特色

- **像素剑侠**：320×480 逻辑画布、原包组合动画，力士／侠客／隐者三职业及男女形象。
- **回合战斗**：攻击、职业技能、道具、自动战斗与状态效果，支持联机组队多目标战斗和邀请制切磋。
- **双模式体验**：本地游玩无需服务端；联机支持账号、每账号最多五个角色、共享地图与公共聊天，线上线下资产隔离。
- **角色与社交**：十个装备槽、商城与换装、NPC 入派、公开资料、好友和基础帮派管理。
- **世界扩展**：原有试炼地图之外，提供明确标注来源的 AI 生成地图、NPC 和一次性支线任务；另有三系列主题装备，含[初号机参考套装](design/eva01-equipment.md)，不作为原版地图或装备恢复成果。
- **开发工具**：独立桌面数据浏览器、世界总图和可重复执行的素材转换工具。

以上为当前源码能力，不保证体验服已部署所有最新功能。网页与 ARM64 APK 的发布基线见 [2026-10-18 发布说明](tests/release_20261018.md)，后续网页聊天更新见 [聊天管理发布记录](tests/chat_moderation.md)。手机真机兼容、完整混合负载与公网长稳仍需分别验证，不将短时连接测试表述为千人完整玩法验收。

2026-10-19 仅更新了门户和网页入口：游戏移至 `/webgame/`，原游戏包、APK、后端和数据库保持不变，见 [门户发布记录](tests/portal_release_20261019.md)。

社区入口改为腾讯频道【蜀山剑侠归来】，门户保留“剑侠茶馆”原有展示，仅更换跳转链接；自建论坛组件已移除。服务器停用与数据清理结果见 [社区入口调整记录](tests/community_channel_20261023.md)。

## 快速开始

### 本地游玩

安装 **Godot 4.7 系列**，打开 `client/project.godot`，按 **F5** 运行；也可以在仓库根目录执行：

```sh
godot --path client
```

项目使用 Compatibility 渲染器。已转换素材随仓库提供，首次启动由 Godot 导入；普通试玩不需要 Python、数据库或重新解包原始资源。封面选择本地入口创建角色即可开始。

### 联机开发

需要 Rust 稳定工具链（支持 Edition 2024）和 PostgreSQL。首次配置参考 [.env.sample.txt](.env.sample.txt) 创建私有 `.env`，填写数据库参数后运行：

```sh
docker compose --env-file .env -f deploy/compose.yaml up -d
cargo run --locked --manifest-path server/Cargo.toml
```

已有 PostgreSQL 时可跳过 Compose。服务默认监听 `127.0.0.1:8080`，配置数据库后启动时自动执行迁移；数据库 URL 为空时仅提供连接检查，不能注册或游玩联机。

原生客户端选择“登录游戏”，连接 `127.0.0.1:8080`，注册／登录后创建或选择线上角色。非回环账号连接必须使用 HTTPS；网页使用构建配置的同源入口。完整配置与安全边界见 [服务端说明](server/README.md)。

## 文档导航

| 想了解什么 | 从这里开始 |
|---|---|
| 操作、试玩流程与存档 | [游玩指南](docs/getting-started.md) |
| 架构、协议与玩法规则 | [设计文档索引](design/README.md) |
| 浏览项目定义、动画与世界总图 | [数据工具](docs/data-tools.md) |
| 恢复范围、导入与资源重建 | [资源恢复与重建](docs/resource-recovery.md) |
| 素材来源、AI 标识与许可边界 | [资源来源说明](docs/asset-provenance.md) |
| 本机联机服务与配置 | [服务端说明](server/README.md) |
| 自行部署网页或公网服务 | [部署导航](deploy/README.md) |
| 私有门户统计与 APK 上传／版本管理 | [管理工具说明](portal_stats/README.md)，当前仅本地实现 |
| 开发与提交贡献 | [贡献指南](CONTRIBUTING.md) |
| 回归入口与历史验收记录 | [测试说明](tests/testing.md) |

## 工程结构

```text
client/    Godot 客户端、游戏素材与独立桌面工具
server/    Rust 联机服务、数据库迁移与规则测试
shared/    版本化协议、共享配置与固定样例
design/    架构、玩法、平台与美术设计
docs/      使用指南与资源说明
deploy/    Docker Compose、代理与部署说明
tools/     资源转换、内容生成与导出工具
portal_stats/ 独立门户统计与 APK 管理，不连接游戏数据库
tests/     仓库级回归、集成脚本与验收记录
analysis/  原包静态分析、恢复证据与资料归档
```

管理工具和分析归档不随游戏导出。引擎导出模板仅在自行构建发布产物时需要，详见 [平台方案](design/platform_interface.md)。

## 贡献与许可

欢迎通过 Issue 提交问题、补充恢复证据，或通过 Pull Request 改进代码、文档与工具。开始前请阅读 [贡献指南](CONTRIBUTING.md)。不要提交密码、令牌、玩家数据、证书或签名私钥。

本仓库包含 [GNU AGPL v3 许可证](LICENSE)。原包素材、名称、第三方资料与参考图不因代码开源而自动获得同等授权；AI 图标也不代表原作官方标识。使用、再分发或运营前请阅读 [资源来源与许可边界](docs/asset-provenance.md)，核验相应权利。项目按现状提供，不承诺还原完整原作或提供生产运营保障。
