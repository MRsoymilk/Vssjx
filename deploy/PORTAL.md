# 导航首页与 `/webgame/` 兼容切换

[部署导航](README.md) · [设计说明](../design/portal-navigation.md) · [验证记录](../tests/portal_navigation.md)

本指南说明已有公网 HTTPS + Web Compose 部署的切换与回退。2026-10-19 已完成一次仅门户发布，事实与验收见 [发布记录](../tests/portal_release_20261019.md)；这不自动授权后续部署。独立本机／LAN 模板不自动启用这些路由。

## 1. 不改变的部分

- 不重建游戏，不重新导出已有网页或 APK，不重启 Rust，不修改数据库。
- `SSJX_PUBLIC_WEB_ROOT` 继续指向原发布目录，原只读容器挂载不变。
- `/api/v1/`、WSS、Origin 白名单、证书和 `/downloads/` 保持原有职责。
- 原 `index.html`、JS、WASM、PCK 及 `/assets/<版本>/` 不覆盖、不删除。

首次访问导航不请求游戏引擎、接口、论坛或第三方资源。原始模板的 Flarum 按钮默认禁用；2026-10-20 已在目标服务器完成独立论坛部署并开放链接，见 [论坛维护说明](FLARUM.md)。

## 2. 本地准备与预览

需要 Python 与 Pillow，在仓库根目录执行：

```sh
python tools/prepare_portal.py --output work/portal-preview
```

输出目录必须为空或不存在，包含 `index.html`、`portal.css`、`app-icon.webp`。图标是原图的 256×256 缩略图，未改游戏资源。每次使用新输出目录，不覆盖已有产物。

实际浏览器截图入口见 [导航测试](../tests/portal_navigation.md)。页面的 GitHub 文档链接需要相应提交已存在于所链接分支；本次本地提交不隐含推送授权。

页面以“游戏／论坛”组织，主按钮先定位到游戏卡片，卡片内再并列选择网页游玩与 Android 预览版，不以网页版作为门户默认入口。

仅查看布局时，也可另选一个新输出目录和空闲回环端口：

```sh
python tools/prepare_portal.py --output work/portal-site/navigation
python -m http.server 8001 --bind 127.0.0.1 --directory work/portal-site
```

打开 `http://127.0.0.1:8001/navigation/index.html`。此静态预览不提供游戏、APK 或 API，相关按钮需在实际反向代理环境验证；不要将此开发服务器公开到公网。

## 3. 远程切换前只读核对

先确认实际容器、静态目录和 Nginx 镜像版本，不根据历史记录猜测：

```sh
sh tools/public-compose.sh ps
sh tools/public-compose.sh exec -T nginx nginx -T
```

同时通过 Docker inspect 核对 `/etc/nginx/conf.d/default.conf` 与 `/usr/share/nginx/html` 的实际宿主挂载源。配置和网页可能来自不同发布目录，不能直接以当前仓库路径替代。

确认原 `index.html`、各版本资源和 APK 可访问，记录对应摘要与当前配置，备份放在静态根目录之外。核对当前浏览器／设备上的实际游戏启动、登录、WSS 与本地保存恢复；不以本仓库惯用路径替代远程包审计。

## 4. 先接入路由，保持原首页

候选为 `deploy/public.web.https.nginx.conf`。在尚未放入 `navigation/index.html` 时，它的 `/` 仍回到原游戏首页，`/webgame/` 读取同一份游戏文件。

1. 保存真实已挂载配置的完整备份，确认能够恢复。
2. 用候选内容更新容器实际可见的配置；单文件 bind mount 下，仅原子替换宿主文件名可能仍指向旧 inode，必须核对容器内内容。需要时将候选完整内容写回已挂载文件，而不是重新创建 Nginx 容器。
3. 运行语法检查，通过后才平滑加载：

```sh
sh tools/public-compose.sh exec -T nginx nginx -t
sh tools/public-compose.sh exec -T nginx nginx -s reload
```

检查失败时恢复已挂载配置并再次验证，不 reload。不要为路径变更执行 `up --force-recreate`、`restart game` 或任何数据卷清理。已打开的 WSS 通常由旧 worker 继续服务；仍需核对远程全局配置和实际连接，不能承诺所有环境绝对零中断。

确认 `/` 仍为原游戏、`/webgame` 临时跳转到 `/webgame/`、新路径能实际启动游戏，旧资源与下载仍有效。缺失 WASM 必须返回 404，不能返回导航 HTML。

## 5. 完整安装导航目录

在真实发布目录的相邻位置准备三个导航文件，**不要直接对已生效的 `navigation/` 逐文件生成**。同文件系统切换完整目录，可以避免首页出现时 CSS／图标尚未准备好。

例如经人工核实后设置 `WEB_ROOT` 为当前导出目录；以下命令会准备并启用导航，必须仅在获得部署授权后执行：

```sh
set -eu
WEB_ROOT=/opt/Vssjx/releases/已核实版本/public
CANDIDATE="${WEB_ROOT%/}/../navigation-candidate"
test -d "$WEB_ROOT"
test ! -e "$CANDIDATE"
test ! -e "$WEB_ROOT/navigation"
python tools/prepare_portal.py --output "$CANDIDATE"
# 核对三文件、读取权限和页面预览后，再执行这一步；Ubuntu/Debian 的 mv -T。
mv -T "$CANDIDATE" "$WEB_ROOT/navigation"
```

若已有导航目录，停止并另定更新／回退方案，不将新目录嵌入旧目录或覆盖未知文件。准备目录须与 `public` 同文件系统；跨文件系统移动不是原子切换。此例不读取、输出或 source 私有 `.env`。

完成后 `/` 显示导航，`/navigation.html` 可直接预览，`/index.html` 和 `/webgame/` 仍是原游戏。这个文件存在性开关无需再次重载 Nginx。不要把游戏 `index.html` 改成导航 HTML。

## 6. 验证与回退

分别检查：

- 导航桌面／手机布局、键盘操作、图标、APK 与已发布文档链接。
- 访问导航不触发游戏下载或自动登录；论坛链接只在独立服务已验证时启用。
- 新／旧游戏文件字节及 WASM MIME；两套版本路径的 gzip 与 immutable 缓存一致。
- `/api/v1/` 的登录与授权、WSS、未知 Origin 拒绝及正在游玩的连接。
- 本地旧存档可读写，线上角色与资产不变；不清理浏览器站点数据。
- `/.env`、管理页与源码不可公开，缺失资源没有 HTML 兜底。

首页回退：将完整 `navigation/` 移到静态根目录之外的未占用目录，`/` 即回到原 `index.html`；不要删除游戏文件或回退数据库。若路由配置本身需要回退，恢复原挂载配置、`nginx -t` 后平滑 reload。

后续更新游戏发布目录时，要显式带上已确认的导航目录，并保留仍在使用的旧版本静态资源；新导出不会自动包含导航，配置也不会自动聚合历史发布目录。

## 7. Flarum 独立接入

仅门户切换本身不创建 PHP 或论坛数据库。2026-10-20 独立接入了 Flarum，替换线上 404 预留并开放论坛按钮，详见 [部署与限制](FLARUM.md) 和 [发布验证](../tests/flarum_release_20261020.md)；后续另行授权接入 QQ SMTP 并[开放注册](../tests/flarum_registration_20261020.md)。论坛配置目录不得进入静态根目录。默认模板仍可用于没有论坛的部署，`--forum` 为显式选项；后续更新不得用默认模板覆盖已启用的真实配置。

同域不同路径不是安全隔离，论坛插件仍处于游戏同源；需要更强隔离时使用独立子域。游戏与论坛账号不会因共享域名而自动互通。
