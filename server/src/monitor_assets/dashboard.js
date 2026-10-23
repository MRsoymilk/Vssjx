"use strict";
const $ = id => document.getElementById(id);
const number = (value, digits = 0) => Number(value || 0).toLocaleString("zh-CN", {maximumFractionDigits: digits});
const mib = value => `${number(value / 1048576, 2)} MiB`;
let previous = null, busy = false;
const history = [];
function node(tag, text) { const element = document.createElement(tag); element.textContent = text; return element; }
function pairs(target, values) { target.replaceChildren(); for (const [key, value] of values) target.append(node("dt", key), node("dd", String(value))); }
function row(target, cells) { const tr = node("tr", ""); for (const cell of cells) tr.append(node("td", String(cell))); target.append(tr); }
function p95(metric, limits) { const threshold = Math.ceil(metric.requests * .95); let count = 0; for (let i = 0; i < metric.latency_buckets.length; i++) { count += metric.latency_buckets[i]; if (count >= threshold) return limits[i] ?? ">5000"; } return "—"; }
async function refresh() {
    if (busy) return;
    busy = true; $("refresh").disabled = true;
    try {
        const response = await fetch("/api/status", {cache: "no-store", signal: AbortSignal.timeout(4000)});
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json(), w = data.world, db = data.database;
        if (previous && previous.boot_id !== data.boot_id) { history.length = 0; previous = null; }
        const dbStale = db.checked_at_ms && data.sample_time_ms - db.checked_at_ms > 15000;
        const tickStale = w && w.last_tick_age_ms > 1500;
        const degraded = db.status === "unavailable" || db.status === "pending" || dbStale || tickStale || data.logging.dropped_records || data.logging.file_io_errors;
        $("health").textContent = degraded ? "需要关注" : "运行中"; $("health").className = `badge ${degraded ? "bad" : "ok"}`;
        $("notice").textContent = `更新于 ${new Date(data.sample_time_ms).toLocaleTimeString()} · ${w ? "共享世界模式" : "仅连接模式"}${dbStale ? " · 数据库采样过期" : ""}${tickStale ? " · 世界 tick 采样过期" : ""}`;
        $("notice").className = "";
        const requests = Object.values(data.http.routes).reduce((sum, item) => sum + item.requests, 0);
        $("cards").replaceChildren();
        for (const [title, value] of [["在线角色 / 容量", w ? `${w.connected_players} / ${w.max_players}` : "未启用"], ["WebSocket 连接", number(data.websocket.active)], ["运行时间", `${number(data.uptime_seconds / 3600, 2)} 小时`], ["进程内存 RSS", data.process.rss_bytes == null ? "不可用" : mib(data.process.rss_bytes)]]) {
            const card = node("div", ""); card.className = "card"; card.append(node("span", title), node("strong", value)); $("cards").append(card);
        }
        pairs($("world"), [["保留角色（含离线宽限）", w ? w.retained_players : "—"], ["移动中角色", w ? w.moving_players : "—"], ["最后 tick 间隔 / 工作耗时", `${number(data.tick.last_interval_ms, 2)} / ${number(data.tick.last_work_ms, 2)} ms`], ["最大 tick 工作耗时", `${number(data.tick.max_work_ms, 2)} ms`], ["超 150ms tick 间隔", number(data.tick.late_intervals)], ["同步序号", w ? w.world_seq : "—"], ["发送失败", number(data.websocket.send_failures)], ["发送应用数据（累计）", mib(data.websocket.sent_application_bytes)], ["聊天队列 / 历史条目", w ? `${w.chat.pending} / ${w.chat.history}` : "—"]]);
        pairs($("database"), [["数据库", `${db.status}${dbStale ? "（采样过期）" : ""}`], ["健康探测耗时", db.probe_ms == null ? "—" : `${number(db.probe_ms, 2)} ms`], ["连接池 / 空闲 / 上限", db.pool_size == null ? "—" : `${db.pool_size} / ${db.pool_idle} / ${db.pool_limit}`], ["日志队列丢弃记录", number(data.logging.dropped_records)], ["日志文件写入失败", number(data.logging.file_io_errors)], ["HTTP 处理中", number(data.http.in_flight)], ["HTTP 请求累计", number(requests)], ["异常累计", number(Object.values(data.errors).reduce((a, b) => a + b, 0))]]);
        $("http").replaceChildren();
        for (const [path, metric] of Object.entries(data.http.routes)) row($("http"), [path, number(metric.requests), metric.responses_4xx, metric.responses_5xx, number(metric.latency_sum_ms / metric.requests, 2), p95(metric, data.http.latency_bucket_upper_bounds_ms), number(metric.latency_max_ms, 2)]);
        $("events").replaceChildren();
        for (const event of [...data.recent_events].reverse()) row($("events"), [new Date(event.time_ms).toLocaleTimeString(), event.kind, event.code, event.correlation_id]);
        if (!data.recent_events.length) row($("events"), ["暂无异常", "", "", ""]);
        history.push(w ? w.connected_players : 0); if (history.length > 60) history.shift();
        $("trend").replaceChildren(); const max = Math.max(1, ...history);
        for (const count of history) { const bar = node("span", ""); bar.style.height = `${Math.max(4, count / max * 100)}%`; bar.title = `在线 ${count}`; $("trend").append(bar); }
        const seconds = previous ? (data.sample_time_ms - previous.sample_time_ms) / 1000 : 0;
        $("rates").textContent = seconds > 0 ? `在线人数趋势 · 最近采样下行 ${number(Math.max(0, data.websocket.sent_application_bytes - previous.websocket.sent_application_bytes) / seconds / 1048576, 2)} MiB/s（应用数据，不含 TCP/TLS）` : "等待下一次采样计算下行速率";
        $("footer").textContent = `v${data.version} · PID ${data.process.pid} · boot ${data.boot_id} · 运行计数重启清零，操作审计持久保存；不展示密码、令牌或聊天正文。`;
        previous = data;
    } catch (error) {
        $("health").textContent = "连接中断"; $("health").className = "badge bad";
        $("notice").textContent = `状态刷新失败，当前展示的是旧数据：${error.message}`; $("notice").className = "bad";
    } finally { busy = false; $("refresh").disabled = false; }
}
$("refresh").addEventListener("click", refresh);
refresh(); setInterval(refresh, 5000);

let dailyVersion = 0, dailyHasData = false;
const coverage = {historical: "历史记录回填，可能不完整", partial: "当日累计／启用首日，非完整全天", complete: "全天统计"};
function svgNode(tag, attributes, text) {
    const element = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, String(value));
    if (text != null) element.textContent = text;
    return element;
}
function renderDaily(days) {
    const svg = svgNode("svg", {viewBox: "0 0 1000 280", role: "img", "aria-labelledby": "daily-chart-description"});
    svg.append(svgNode("title", {id: "daily-chart-description"}, "每日在线人数折线图，按北京时间去重账号；完整数据见下方明细，空缺日期不连线。"));
    const max = Math.max(1, ...days.map(day => day.users ?? 0));
    const top = Math.max(1, Math.ceil(max / 4)) * 4;
    const x = index => 64 + index * 910 / Math.max(1, days.length - 1);
    const y = count => 232 - count / top * 204;
    for (let i = 0; i <= 4; i++) {
        const value = top * i / 4;
        svg.append(svgNode("line", {x1:64, x2:974, y1:y(value), y2:y(value), class:"daily-grid"}));
        svg.append(svgNode("text", {x:54, y:y(value)+4, "text-anchor":"end", class:"daily-axis"}, number(value)));
    }
    let path = "", connected = false;
    days.forEach((day, index) => {
        if (day.users == null) { connected = false; return; }
        path += `${connected ? "L" : "M"}${x(index)},${y(day.users)} `;
        connected = true;
    });
    svg.append(svgNode("path", {d:path, class:"daily-line"}));
    days.forEach((day, index) => {
        if (day.users != null) {
            const point = svgNode("circle", {cx:x(index), cy:y(day.users), r:4, class:day.coverage==="complete"?"daily-point":"daily-point daily-partial"});
            point.append(svgNode("title", {}, `${day.date}：${number(day.users)} 人 · ${coverage[day.coverage]}`));
            svg.append(point);
        }
        if (index===0 || index===days.length-1 || index%Math.ceil((days.length-1)/6)===0)
            svg.append(svgNode("text", {x:x(index), y:260, "text-anchor":"middle", class:"daily-axis"}, day.date.slice(5)));
    });
    $("daily-online-chart").replaceChildren(svg);
    $("daily-online-rows").replaceChildren();
    for (const day of days) row($("daily-online-rows"), [day.date, day.users==null?"未采集":number(day.users), coverage[day.coverage]]);
}
async function refreshDaily() {
    const current = ++dailyVersion, days = $("daily-online-range").value;
    $("daily-online-status").textContent = dailyHasData ? "正在刷新每日统计，图表暂为上次数据…" : "正在获取每日在线统计…";
    try {
        const response = await fetch(`/api/online/daily?days=${days}`, {cache:"no-store", signal:AbortSignal.timeout(5000)});
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        if (current !== dailyVersion) return;
        renderDaily(data.days); dailyHasData = true;
        const today = data.days.at(-1);
        $("daily-online-status").textContent = `最近 ${days} 天 · 今日累计 ${number(today.users)} 人 · 北京时间（UTC+8） · 更新于 ${new Date().toLocaleTimeString()}${data.days.some(day=>day.users==null)?" · 部分日期未采集":""}`;
    } catch (error) {
        if (current !== dailyVersion) return;
        $("daily-online-status").textContent = `每日在线统计获取失败：${error.message}${dailyHasData?"；图表保留上次数据（可能属于上次选择的范围）":"；暂不显示人数"}`;
    }
}
$("daily-online-range").addEventListener("change", refreshDaily);
$("refresh").addEventListener("click", refreshDaily);
refreshDaily(); setInterval(refreshDaily, 60000);
