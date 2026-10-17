/* All user data goes through textContent, never HTML. The operator token stays in memory. */
(() => {
    const el = id => document.getElementById(id);
    const make = (tag, text) => { const n = document.createElement(tag); if (text !== undefined) n.textContent = String(text); return n; };
    let offset = 0, selected = null, csrf = null, nextAudit = null, scope = null;
    let usersVersion = 0, detailVersion = 0, auditVersion = 0, busy = false;
    let uncertain = null;
    const labels = {accepted:'已执行', rejected:'拒绝', replayed:'重复请求', observed:'观察记录'};
    const time = value => value ? new Date(value).toLocaleString() : '—';
    async function api(path, options) {
        const response = await fetch(path, {cache:'no-store', ...options});
        const data = await response.json();
        if (!response.ok) throw new Error(data.code || `HTTP ${response.status}`);
        return data;
    }
    function controls() {
        el('user-execute').disabled = busy || !selected || !csrf;
        el('user-action-kind').disabled = busy;
        el('user-reason').disabled = busy;
    }
    async function users() {
        const version = ++usersVersion;
        el('users-status').textContent = '正在获取用户…';
        try {
            const data = await api(`/api/users?q=${encodeURIComponent(el('users-q').value.trim())}&offset=${offset}`);
            if (version !== usersVersion) return;
            csrf = data.csrf_token;
            el('users-list').replaceChildren();
            for (const u of data.users) {
                const tr = make('tr');
                for (const text of [u.username, u.disabled?'已封禁':'正常',u.characters,u.sessions,time(u.created_at)]) tr.append(make('td',text));
                const td = make('td'), button = make('button','查看');
                button.type = 'button'; button.addEventListener('click',() => { if (!busy) detail(u.id); }); td.append(button); tr.append(td);
                el('users-list').append(tr);
            }
            el('users-prev').disabled = offset === 0;
            el('users-next').disabled = !data.more;
            el('users-page').textContent = `第 ${offset/50+1} 页`;
            el('users-status').textContent = data.users.length ? `本页 ${data.users.length} 个账号` : '没有匹配账号';
        } catch (e) { if (version === usersVersion) {csrf=null; el('users-status').textContent = `获取失败：${e.message}`;} }
        controls();
    }
    async function detail(id) {
        const version = ++detailVersion;
        selected = null; controls(); el('user-detail').hidden = true;
        try {
            const data = await api(`/api/users/${encodeURIComponent(id)}`);
            if (version !== detailVersion) return;
            selected = id; scope = id;
            const priorCharacter=el('audit-character').value;
            const allCharacters=make('option','全部角色 / 账号操作');allCharacters.value='';
            el('audit-character').replaceChildren(allCharacters);
            for(const c of data.characters) {const option=make('option',c.display_name);option.value=c.id;el('audit-character').append(option);}
            if(data.characters.some(c=>c.id===priorCharacter)) el('audit-character').value=priorCharacter;
            el('audit-character').disabled=false;
            el('user-detail').hidden = false;
            el('user-name').textContent = `${data.account.username} · ${data.account.disabled?'已封禁':'正常'}`;
            el('user-id').textContent = id;
            el('user-characters').replaceChildren();
            for (const c of data.characters) {
                const card = make('article'); card.className='user-character';
                card.append(make('h4',`${c.display_name} · Lv.${c.level}`));
                card.append(make('p',`铜钱 ${c.gold} · 修为 ${c.xp} · 气血 ${c.hp} · 灵力 ${c.mp} · 任务阶段 ${c.quest_stage}`));
                card.append(make('p',`地图 ${c.map_id} · 坐标 ${c.cell.join(', ')} · 状态版本 ${c.state_revision}`));
                const d = make('details'); d.append(make('summary','角色、属性与物品详情'),make('pre',JSON.stringify(c,null,2))); card.append(d);
                el('user-characters').append(card);
            }
            if (!data.characters.length) el('user-characters').append(make('p','尚未创建角色'));
            el('user-sessions').textContent = JSON.stringify(data.sessions,null,2);
            controls(); await audit(false);
        } catch(e) { if(version===detailVersion) el('users-status').textContent=`读取详情失败：${e.message}`; }
    }
    async function audit(append) {
        const version=++auditVersion;
        el('audit-more').disabled=true; el('audit-status').textContent='正在获取记录…';
        const query = new URLSearchParams();
        if(scope) query.set('account_id',scope);
        if(scope && el('audit-character').value) query.set('character_id',el('audit-character').value);
        if(el('audit-outcome').value) query.set('outcome',el('audit-outcome').value);
        if(append && nextAudit) query.set('before',nextAudit);
        el('audit-scope').textContent=scope?`当前账号：${scope}`:'全部账号';
        try {
            const data=await api(`/api/audit?${query}`);
            if(version!==auditVersion) return;
            if(!append) el('audit-list').replaceChildren();
            for(const e of data.events) {
                const tr=make('tr'), first=make('td');
                first.append(make('div',time(e.created_at)),make('small',e.account_id || '未归属账号'));
                const outcome=make('td',`${labels[e.outcome]||e.outcome} · ${e.code}`); if(e.outcome==='rejected') outcome.className='bad';
                const td=make('td'), d=make('details');
                d.append(make('summary',`记录 #${e.id} · 查看详情`),make('pre',JSON.stringify({operation_id:e.operation_id,character_id:e.character_id,session_id:e.session_id,...e.details},null,2))); td.append(d);
                tr.append(first,make('td',e.action),outcome,td); el('audit-list').append(tr);
            }
            nextAudit=data.next_before;
            el('audit-more').disabled=!nextAudit;
            el('audit-status').textContent=data.events.length?`已显示 ${el('audit-list').children.length} 条记录`:'暂无符合条件的记录';
        } catch(e) {if(version===auditVersion) el('audit-status').textContent=`读取失败：${e.message}`;}
    }
    el('users-search').addEventListener('submit',e=>{e.preventDefault();offset=0;users();});
    el('users-refresh').addEventListener('click',users);
    el('users-prev').addEventListener('click',()=>{offset=Math.max(0,offset-50);users();});
    el('users-next').addEventListener('click',()=>{offset+=50;users();});
    el('audit-more').addEventListener('click',()=>audit(true));
    el('audit-refresh').addEventListener('click',()=>audit(false));
    el('audit-outcome').addEventListener('change',()=>audit(false));
    el('audit-character').addEventListener('change',()=>audit(false));
    el('audit-all').addEventListener('click',()=>{scope=null;el('audit-character').value='';el('audit-character').disabled=true;audit(false);});
    el('user-action').addEventListener('submit',async e=>{
        e.preventDefault(); if(busy || !selected || !csrf) return;
        const action=el('user-action-kind').value, reason=el('user-reason').value.trim(), id=selected;
        if(reason.length<2) {el('user-action-status').textContent='请填写至少两个字的原因。';return;}
        const retry=uncertain && uncertain.id===id && uncertain.intent.action===action && uncertain.intent.reason===reason;
        const warning=uncertain && !retry ? `上次操作 ${uncertain.intent.operation_id} 的结果未确认，请先查看审计记录。\n` : '';
        if(!window.confirm(`${warning}${retry?'沿用上次操作号重试。\n':''}确定对账号 ${id} 执行“${el('user-action-kind').selectedOptions[0].textContent}”？`)) return;
        busy=true;controls();el('user-action-status').textContent='正在执行，请勿重复提交…';
        // Keep an ambiguous request retryable with the SAME id; never mint a new intent automatically.
        const intent=retry?uncertain.intent:{operation_id:crypto.randomUUID(),action,reason};
        try {
            const result=await api(`/api/users/${id}/actions`,{method:'POST',headers:{'Content-Type':'application/json','X-Operator-Token':csrf},body:JSON.stringify(intent)});
            uncertain=null;
            el('user-action-status').textContent=`已执行，撤销 ${result.revoked_sessions} 个会话。操作 ID：${intent.operation_id}`;
            el('user-reason').value=''; await users(); await detail(id);
        } catch(err) {uncertain={id,intent};el('user-action-status').textContent=`结果未确认：${err.message}。请先刷新账号与审计记录；相同账号、动作和原因的重试将沿用原操作号。操作 ID：${intent.operation_id}`;}
        finally {busy=false;controls();}
    });
    users(); audit(false);
})();
