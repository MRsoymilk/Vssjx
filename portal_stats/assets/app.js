'use strict';
(() => {
  const $ = id => document.getElementById(id);
  let token = '', busy = false, statisticsEpoch = 0;
  const messages = {
    APK_IS_CURRENT: '当前下载不能删除，请先切换到其他版本。', APK_TOO_LARGE: 'APK 超过上传大小限制。', BODY_TOO_LARGE: '上传内容超过限制。',
    APK_QUOTA_EXCEEDED: '文件存储配额不足，请先删除不再使用的旧版。', INVALID_APK_STRUCTURE: '文件未通过 APK 容器检查。', INVALID_APK_NAME: '文件名不合法，请选择 .apk 文件。',
    APK_PUBLISH_DISABLED: '尚未配置独立发布目录，当前只保存文件。', APK_MANAGEMENT_DISABLED: '尚未启用 APK 管理。', APK_BUSY: '另一个文件操作正在进行，请稍后重试。',
    UNMANAGED_CURRENT: '发布目录包含未知文件或指针，已停止操作，请由运维核对。', UNMANAGED_RELEASE: '版本目录存在未知或被修改的文件，已停止操作。',
    APK_FILE_CHANGED: '已存文件与登记摘要不符，操作被拒绝。', MANAGEMENT_TOKEN_REQUIRED: '管理令牌已过期，请刷新页面。', INVALID_QUERY: '日期范围无效，最多查询 366 天且不能查询未来。',
    LOCAL_DATA_UNAVAILABLE: '本地统计数据库暂不可读。', LOCAL_FILE_OPERATION_FAILED: '本地文件操作失败，请刷新列表核对结果。',
  };
  const number = value => Number(value).toLocaleString('zh-CN');
  function bytes(value) { const unit = ['B', 'KiB', 'MiB', 'GiB', 'TiB']; let index = 0; while (value >= 1024 && index < unit.length - 1) {value /= 1024; index++;} return value.toFixed(index ? 1 : 0) + ' ' + unit[index]; }
  function notice(text, error = false) {$('notice').textContent = text; $('notice').classList.toggle('error', error);}
  async function api(path, options) {
    const response = await fetch(path, {cache: 'no-store', ...options});
    const value = await response.json();
    if (!response.ok) throw new Error(messages[value.code] || value.code || '请求失败');
    return value;
  }
  function day(value) {return new Date(value + 8 * 3600000).toISOString().slice(0, 10);}
  function preset(value) {
    const today = Date.now();
    $('start').value = day(today - (value === 'yesterday' ? 1 : value === 'today' ? 0 : Number(value) - 1) * 86400000);
    $('end').value = day(today - (value === 'yesterday' ? 1 : 0) * 86400000);
    document.querySelectorAll('[data-days]').forEach(button => button.classList.toggle('selected', button.dataset.days === value));
  }
  function cell(row, value, className) {const node = document.createElement('td'); node.textContent = value; if (className) node.className = className; row.append(node); return node;}
  function chart(days) {
    const namespace = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(namespace, 'svg'); svg.setAttribute('viewBox', '0 0 1000 190'); svg.setAttribute('role', 'img');
    const maximum = Math.max(1, ...days.flatMap(row => [row.portal_views, row.web_clicks, row.apk_requests]));
    for (const [key, css] of [['portal_views', 'portal'], ['web_clicks', 'web'], ['apk_requests', 'apk']]) {
      const line = document.createElementNS(namespace, 'polyline');
      line.setAttribute('points', days.map((row, index) => `${days.length === 1 ? 500 : 10 + index / (days.length - 1) * 980},${175 - row[key] / maximum * 160}`).join(' '));
      line.setAttribute('fill', 'none'); line.setAttribute('stroke-width', '3'); line.setAttribute('class', css);
      if (days.length === 1) {const dot = document.createElementNS(namespace, 'circle'); dot.setAttribute('cx', '500'); dot.setAttribute('cy', String(175 - days[0][key] / maximum * 160)); dot.setAttribute('r', '4'); dot.setAttribute('class', css); svg.append(dot);}
      svg.append(line);
    }
    $('chart').replaceChildren(svg);
  }
  async function statistics() {
    const epoch = ++statisticsEpoch;
    const query = new URLSearchParams({start: $('start').value, end: $('end').value});
    const data = await api('/api/summary?' + query);
    if (epoch !== statisticsEpoch) return;
    $('csv').href = '/api/export.csv?' + query;
    const cards = [ ['门户访问量', 'portal_views', '包含刷新，不是独立人数'], ['网页入口点击', 'web_clicks', '固定跳转请求次数'], ['游戏页面访问', 'game_views', '包含直达与刷新'], ['Android 入口点击', 'android_clicks', '点击不等于下载完成'], ['APK 下载请求', 'apk_requests', '200 / 206 响应次数'], ['APK 分段请求', 'apk_range_requests', '断点续传可能产生多次'], ['缓存复用 / 异常', null, '304 / 4xx、5xx'], ['APK 已发送流量', 'apk_bytes', '不代表设备已保存文件'] ];
    $('cards').replaceChildren(...cards.map(([label, key, hint]) => {const card = document.createElement('article'); card.className = 'card'; const title = document.createElement('span'); title.textContent = label; const value = document.createElement('strong'); value.textContent = key === 'apk_bytes' ? bytes(data.totals[key]) : key ? number(data.totals[key]) : number(data.totals.apk_cached_requests) + ' / ' + number(data.totals.apk_failed_requests); const note = document.createElement('small'); note.textContent = hint; card.append(title, value, note); return card;}));
    $('daily').replaceChildren(...data.days.map(value => {const row = document.createElement('tr'); for (const key of ['day', 'portal_views', 'web_clicks', 'game_views', 'android_clicks', 'apk_requests', 'apk_range_requests', 'apk_cached_requests', 'apk_failed_requests', 'apk_bytes']) cell(row, key === 'day' ? value[key] : key === 'apk_bytes' ? bytes(value[key]) : number(value[key])); return row;}));
    chart(data.days);
    const status = data.collector;
    const paragraphs = [status.live ? '采集运行中' : '采集未运行或心跳已过期（离线导入也显示此状态）', '最后采集心跳：' + (status.heartbeat || '尚无'), '最近事件：' + (status.last_event || '尚无'), '累计有效事件：' + (status.count_applied || '0') + '；忽略无效事件：' + (status.count_invalid || '0') + '；冲突：' + (status.count_conflict || '0') + (status.collector_error ? '；采集错误：' + status.collector_error : '')];
    $('collector').replaceChildren(...paragraphs.map(value => {const p = document.createElement('p'); p.textContent = value; return p;}));
  }
  async function packages() {
    const data = await api('/api/apks');
    $('upload').disabled = busy || !data.enabled;
    $('apk-capacity').textContent = data.enabled ? `私有文件 ${bytes(data.used_bytes)} / ${bytes(data.quota)}，单文件上限 ${bytes(data.max_upload)}。发布副本另占空间。` : 'APK 管理未启用：启动时配置 --apk-directory。';
    $('apk-publish-note').textContent = data.publish_enabled ? '可设为当前下载。只有未来配置了对应 Nginx 挂载时才影响下载入口；当前版本受删除保护。' : '未配置 --apk-public-directory：上传仅保存，不会改动任何现有下载。';
    if (data.warning) notice(messages[data.warning] || data.warning, true);
    $('apk-list').replaceChildren(...data.files.map(file => {
      const row = document.createElement('tr'); cell(row, file.name, 'filename'); cell(row, bytes(file.bytes)); cell(row, new Date(file.uploaded).toLocaleString('zh-CN')); cell(row, file.sha256, 'hash'); cell(row, file.current ? '当前下载' : file.state === 'deleting' ? '删除未完成，可重试' : '已保存 / 未验签');
      const actions = cell(row, '', 'row-actions');
      for (const [label, action, disabled] of [['设为当前', 'publish', file.current || !data.publish_enabled || file.state !== 'ready'], ['删除旧版', 'delete', file.current]]) {
        const button = document.createElement('button'); button.textContent = label; button.disabled = busy || disabled || Boolean(data.warning); if (action === 'delete') button.className = 'danger';
        button.addEventListener('click', () => mutate(async () => {
          if (!window.confirm((action === 'delete' ? '永久删除该旧版本及其发布副本？此操作不可撤销。\n' : '将此版本设为当前下载？\n') + file.name + '\nSHA256: ' + file.sha256)) return;
          await api('/api/apks/' + file.id + (action === 'publish' ? '/publish' : ''), {method: action === 'delete' ? 'DELETE' : 'POST', headers: {'Content-Type': 'application/json', 'X-Portal-Token': token}, body: JSON.stringify({confirm: file.id})});
          notice(action === 'delete' ? '旧版本已删除。' : '当前下载已切换。');
        })); actions.append(button);
      }
      return row;
    }));
  }
  async function mutate(action) {
    if (busy) return;
    busy = true;
    try {await packages(); await action();} catch (error) {notice(error.message, true);} finally {busy = false; await packages().catch(error => notice(error.message, true));}
  }
  $('upload').addEventListener('click', () => mutate(async () => {
    const file = $('apk-file').files[0];
    if (!file) {notice('请先选择 APK 文件。', true); return;}
    notice('上传和检查中，请勿关闭页面……');
    const result = await api('/api/apks/upload?' + new URLSearchParams({name: file.name}), {method: 'POST', headers: {'Content-Type': 'application/octet-stream', 'X-Portal-Token': token}, body: file});
    $('apk-file').value = ''; notice(result.duplicate ? '相同 SHA256 的 APK 已存在，未重复保存。' : 'APK 已保存，未自动发布。');
  }));
  $('tab-stats').addEventListener('click', () => {$('stats-panel').hidden = false; $('apks-panel').hidden = true; $('tab-stats').setAttribute('aria-selected', 'true'); $('tab-apks').setAttribute('aria-selected', 'false');});
  $('tab-apks').addEventListener('click', () => {$('stats-panel').hidden = true; $('apks-panel').hidden = false; $('tab-stats').setAttribute('aria-selected', 'false'); $('tab-apks').setAttribute('aria-selected', 'true'); packages().catch(error => notice(error.message, true));});
  $('presets').addEventListener('click', event => {if (event.target.dataset.days) {preset(event.target.dataset.days); statistics().catch(error => notice(error.message, true));}});
  $('query').addEventListener('click', () => {document.querySelectorAll('[data-days]').forEach(button => button.classList.remove('selected')); statistics().catch(error => notice(error.message, true));});
  preset('today');
  api('/api/bootstrap').then(data => {token = data.token; return statistics();}).catch(error => notice(error.message, true));
  setInterval(() => {if (!document.hidden && !$('stats-panel').hidden) statistics().catch(error => notice(error.message, true));}, 15000);
})();
