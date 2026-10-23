//! Shared static shell. Untrusted account data is rendered using textContent.
use axum::response::Html;

pub(crate) fn render(page: &str) -> Html<String> {
    let (title, active, content, scripts, crumbs) = match page {
        "maps" => ("地图管理", "/maps", include_str!("monitor_assets/maps.html"), "/admin.js,/maps.js", "<li><a href=\"/\">管理中心</a></li><li aria-current=\"page\">地图管理</li>"),
        "chat" => (
            "聊天管理", "/chat", include_str!("monitor_assets/chat.html"), "/admin.js,/chat.js",
            "<li><a href=\"/\">管理中心</a></li><li aria-current=\"page\">聊天管理</li>",
        ),
        "users" => (
            "用户管理",
            "/users",
            include_str!("monitor_assets/users.html"),
            "/admin.js,/users.js",
            "<li><a href=\"/\">管理中心</a></li><li aria-current=\"page\">用户管理</li>",
        ),
        "user" => (
            "账号详情",
            "/users",
            include_str!("monitor_assets/user.html"),
            "/admin.js,/users.js",
            "<li><a href=\"/\">管理中心</a></li><li><a id=\"breadcrumb-users\" href=\"/users\">用户管理</a></li><li id=\"breadcrumb-account\" aria-current=\"page\">账号详情</li>",
        ),
        "audit" => (
            "操作审计",
            "/audit",
            include_str!("monitor_assets/audit.html"),
            "/admin.js,/audit.js",
            "<li><a href=\"/\">管理中心</a></li><li aria-current=\"page\">操作审计</li>",
        ),
        "announcements" => (
            "全局通知",
            "/announcements",
            include_str!("monitor_assets/announcements.html"),
            "/announcements.js",
            "<li><a href=\"/\">管理中心</a></li><li aria-current=\"page\">全局通知</li>",
        ),
        _ => (
            "服务概况",
            "/",
            include_str!("monitor_assets/overview.html"),
            "/dashboard.js",
            "<li aria-current=\"page\">管理中心</li>",
        ),
    };
    let nav = [
        ("/", "服务概况"),
        ("/users", "用户管理"),
        ("/audit", "操作审计"),
        ("/announcements", "全局通知"),
        ("/chat", "聊天管理"),
        ("/maps", "地图管理"),
    ]
    .into_iter()
    .map(|(href, label)| {
        format!(
            "<a href=\"{href}\"{}>{label}</a>",
            if href == active {
                " aria-current=\"page\""
            } else {
                ""
            }
        )
    })
    .collect::<String>();
    let scripts = scripts
        .split(',')
        .map(|src| format!("<script src=\"{src}\" defer></script>"))
        .collect::<String>();
    Html(
        include_str!("monitor_assets/index.html")
            .replace("{{TITLE}}", title)
            .replace("{{PAGE}}", page)
            .replace(
                "{{HEALTH}}",
                if active == "/" {
                    "<span id=\"health\" class=\"badge\">连接中</span>"
                } else {
                    ""
                },
            )
            .replace("{{NAV}}", &nav)
            .replace("{{BREADCRUMBS}}", crumbs)
            .replace("{{SCRIPTS}}", &scripts)
            .replace("{{CONTENT}}", content),
    )
}
