# 门户统计与 APK 管理

[项目首页](../README.md) · [设计与安全边界](../design/portal-management.md) · [操作说明](../deploy/PORTAL_STATS.md) · [验证入口](../tests/portal_stats.md)

独立的 Python 标准库管理工具，面向 Linux、Python 3.10+。不连接 Rust 游戏服务或 PostgreSQL，不需要第三方统计平台、前端埋点脚本或浏览器跟踪 Cookie。**当前仅本地实现，未部署。**

## 功能

- 白名单 Nginx 请求事件、请求 ID 去重、UTC+8 每日汇总。
- 门户访问、网页／Android 入口点击、游戏页面访问、APK 请求及发送字节。
- 今日／昨日／近 7 天／近 30 天、自定义日期、趋势、明细与 CSV。
- 采集心跳与异常状态；不把离线导入显示为实时采集。
- APK 上传、容器结构检查、SHA256、独立版本保存、显式设为当前下载、删除旧版。
- 当前版本不可删除，未知文件不覆盖，上传不会自动发布。

## 本地启动

从仓库根目录运行，数据留在 Git 忽略的工作目录：

```sh
python -m portal_stats init --database work/portal-admin/stats.sqlite3
python -m portal_stats serve --database work/portal-admin/stats.sqlite3 --apk-directory work/portal-admin/apks
```

打开 `http://127.0.0.1:9088/`。没有事件时显示零数据，采集状态提示未运行；上传仅保存在本机，不会改变公网 APK。仅统计模式可省略 `--apk-directory`。

若需在本地测试“设为当前”，另指定与私有目录分开的 `--apk-public-directory work/portal-apk-public`；这只是本地发布指针，不会修改现有网页目录或启动 Nginx。

## 两个独立进程

`collect` 通过宿主 Docker CLI 读取 Nginx 日志，或从标准输入离线导入。`serve` 仅读取汇总库并管理显式配置的 APK 目录，不调用 Docker，也不提供 HTTP 日志导入接口。生产部署应将权限分开，不给管理端 Docker socket 或游戏数据库凭据。

管理端拒绝非回环绑定，写操作需要同源 Origin、正确 Host 和随机进程令牌。它没有独立密码体系，安全边界是可信主机与 SSH 访问权限；同机有权限用户不是被隔离的租户。不要接入公网代理。

访问量是请求次数，不是独立访客；下载请求不是完成下载或安装。APK 仅做有界容器检查，不验签、不证明安装安全，不在服务端解包或执行。详见 [操作与限制](../deploy/PORTAL_STATS.md)。
