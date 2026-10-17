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
