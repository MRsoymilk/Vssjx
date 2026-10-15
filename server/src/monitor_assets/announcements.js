"use strict";
(() => {
    const get = id => document.getElementById(id);
    let token = "", current = null, saving = false, loading = false, pending = null, epoch = "", revision = -1n;
    function controls() {
        get("announcement-publish").disabled = saving || !token;
        get("announcement-cancel").disabled = saving || !token || !current;
        get("announcement-text").disabled = saving;
        get("announcement-minutes").disabled = saving;
    }
    function render(state) {
        if (state.epoch === epoch && BigInt(state.revision) < revision) return;
        epoch = state.epoch; revision = BigInt(state.revision);
        current = state.notice;
        get("announcement-current").textContent = current ? current.text : "暂无正在播放的通知";
        get("announcement-expiry").textContent = current ? `播放至 ${new Date(Number(current.expires_at_ms)).toLocaleString()} · 客户端循环滚动` : "可发布维护、活动及其他全服消息";
        get("announcement-publish").textContent = current ? "发布并替换" : "发布通知";
        controls();
    }
    async function refresh() {
        if (loading || saving) return;
        loading = true;
        try {
            const response = await fetch("/api/announcements", {cache:"no-store", signal:AbortSignal.timeout(4000)});
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const data = await response.json(); token = data.csrf_token; render(data.state);
        } catch (_) {
            token = ""; controls();
            get("announcement-result").textContent = "通知状态获取失败，请检查服务连接后刷新。";
        } finally { loading = false; }
    }
    async function write(method, payload) {
        saving = true; controls();
        get("announcement-result").textContent = method === "POST" ? "正在推送通知…" : "正在撤下通知…";
        try {
            const response = await fetch("/api/announcements", {method, headers:{"Content-Type":"application/json", "X-Announcement-Token":token}, body:JSON.stringify(payload), signal:AbortSignal.timeout(5000)});
            const data = await response.json();
            if (!response.ok) {
                const errors = {INVALID_OPERATOR_TOKEN:"页面已过期，请刷新后重试。", INVALID_ANNOUNCEMENT:"请输入1～240字通知，有效期1～1440分钟，不含特殊控制字符。", ANNOUNCEMENT_REPLACED:"通知已被其他页面替换，请刷新后再撤下。", ANNOUNCEMENT_ID_CONFLICT:"此次请求内容发生冲突，请重新编辑后发布。", ANNOUNCEMENT_SUPERSEDED:"该次通知已结束或被替换，请重新编辑后发布。"};
                throw new Error(errors[data.code] || `操作失败（HTTP ${response.status}）`);
            }
            render(data); pending = null;
            get("announcement-result").textContent = method === "POST" ? "已发布，正向所有在线角色推送；有效期内新上线可见。" : "已撤下，客户端将停止播放。";
        } catch (error) {
            get("announcement-result").textContent = `${error.message} 如连接中断，结果可能尚未确认，请刷新当前通知；重试相同内容会沿用原请求。`;
        } finally { saving = false; controls(); }
    }
    get("announcement-form").addEventListener("submit", event => {
        event.preventDefault(); if (saving || !token) return;
        const text = get("announcement-text").value, duration_seconds = Number(get("announcement-minutes").value) * 60;
        if (!pending || pending.text !== text || pending.duration_seconds !== duration_seconds) pending = {request_id:crypto.randomUUID(), text, duration_seconds};
        write("POST", pending);
    });
    get("announcement-cancel").addEventListener("click", () => { if (current && !saving) write("DELETE", {id:current.id}); });
    get("announcement-text").addEventListener("input", () => { get("announcement-count").textContent = `${Array.from(get("announcement-text").value).length} / 240`; });
    get("refresh").addEventListener("click", refresh);
    refresh(); setInterval(refresh, 5000);
})();
