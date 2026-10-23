/* Separate list/detail pages. All account data is rendered as text. */
(() => {
    const {el,make,api,time,listQuery,uuid}=window.Admin;
    if(document.body.dataset.page==='users') {
        let {q,offset}=listQuery(),version=0;
        el('users-q').value=q;
        async function users() {
            const current=++version,query=new URLSearchParams();
            if(q)query.set('q',q);if(offset)query.set('offset',String(offset));
            const suffix=query.size?'?'+query:'';
            history.replaceState(null,'','/users'+suffix);
            el('users-status').textContent='正在获取用户…';
            el('users-prev').disabled=true;el('users-next').disabled=true;
            try {
                const data=await api(`/api/users?q=${encodeURIComponent(q)}&offset=${offset}`);
                if(current!==version)return;
                el('users-list').replaceChildren();
                for(const u of data.users) {
                    const tr=make('tr');
                    for(const text of [u.username,u.disabled?'已封禁':'正常'])tr.append(make('td',text));
                    const roles=make('td');roles.className='character-links';
                    for(const c of u.character_summaries) {
                        const roleLink=make('a',`${c.display_name} · Lv.${c.level}`);
                        if(q && (c.display_name.toLowerCase().includes(q.toLowerCase()) || c.id===q.toLowerCase()))roleLink.className='role-match';
                        roleLink.href='/users/'+encodeURIComponent(u.id)+(suffix?suffix+'&':'?')+'character_id='+encodeURIComponent(c.id);roles.append(roleLink);
                    }
                    if(!u.character_summaries.length)roles.textContent='尚未创建角色';
                    tr.append(roles,make('td',u.sessions),make('td',time(u.created_at)));
                    const td=make('td'),link=make('a','查看详情');link.className='button-link';
                    link.href='/users/'+encodeURIComponent(u.id)+suffix;td.append(link);tr.append(td);el('users-list').append(tr);
                }
                el('users-prev').disabled=offset===0;el('users-next').disabled=!data.more;
                el('users-page').textContent=`第 ${Math.floor(offset/50)+1} / ${Math.max(1,Math.ceil(data.matched/50))} 页`;
                el('users-status').textContent=`总用户 ${data.total.toLocaleString('zh-CN')} 个账号 · 匹配 ${data.matched.toLocaleString('zh-CN')} 个 · 本页 ${data.users.length} 个${data.users.length?'':' · 本页没有匹配账号'} · 有效会话数量不等于在线人数`;
            } catch(e) {if(current===version)el('users-status').textContent=`获取失败：${e.message}`;}
        }
        el('users-search').addEventListener('submit',e=>{e.preventDefault();q=el('users-q').value.trim();offset=0;users();});
        for(const name of ['users-refresh','refresh'])el(name).addEventListener('click',users);
        el('users-prev').addEventListener('click',()=>{offset=Math.max(0,offset-50);users();});
        el('users-next').addEventListener('click',()=>{offset+=50;users();});
        users();return;
    }
    const id=location.pathname.split('/')[2];
    const selectedRole=new URLSearchParams(location.search).get('character_id')?.toLowerCase();
    if(!uuid(id)){el('user-status').textContent='账号 ID 无效';return;}
    if(selectedRole && !uuid(selectedRole)){el('user-status').textContent='角色 ID 无效';return;}
    el('breadcrumb-users').href='/users'+listQuery().suffix;
    el('user-audit').href='/audit?account_id='+encodeURIComponent(id);
    let csrf=null,busy=false,version=0,uncertain=null,accountName='',roleName='';
    function controls() {
        el('user-execute').disabled=busy || !csrf;
        el('user-action-kind').disabled=busy;el('user-reason').disabled=busy;
        el('refresh').disabled=busy;
    }
    async function detail() {
        const current=++version;csrf=null;controls();
        el('user-status').textContent='正在获取账号详情…';
        try {
            const [data,access]=await Promise.all([api('/api/users/'+id),api('/api/users?q='+id)]);
            if(current!==version)return;
            const role=data.characters.find(c=>c.id===selectedRole);
            if(selectedRole && !role)throw new Error('角色不属于当前账号或已不存在');
            accountName=data.account.username;roleName=role?.display_name || '';
            csrf=access.csrf_token;
            el('user-detail').hidden=false;
            el('breadcrumb-account').textContent=data.account.username;
            el('breadcrumb-character')?.remove();
            if(role) {
                const accountLink=make('a',data.account.username);accountLink.href='/users/'+id+listQuery().suffix;
                el('breadcrumb-account').replaceChildren(accountLink);el('breadcrumb-account').removeAttribute('aria-current');
                const crumb=make('li',roleName);crumb.id='breadcrumb-character';crumb.setAttribute('aria-current','page');el('breadcrumbs').append(crumb);
                el('user-audit').href='/audit?account_id='+id+'&character_id='+encodeURIComponent(selectedRole);
                el('user-audit').textContent='查看此角色的操作审计';
                el('user-selected-character').textContent=`当前角色：${roleName} · 所属账号：${accountName}`;
                document.querySelector('h1').textContent='角色详情';
            }
            document.title=`${data.account.username} · 用户管理 · Vssjx`;
            el('user-name').textContent=`${data.account.username} · ${data.account.disabled?'已封禁':'正常'}`;
            el('user-id').textContent=id;
            el('user-characters').replaceChildren();
            for(const c of data.characters) {
                const card=make('article');card.className='user-character';
                if(c.id===selectedRole)card.classList.add('selected-character');
                card.append(make('h4',`${c.display_name} · Lv.${c.level}`));
                card.append(make('p',`铜钱 ${c.gold} · 修为 ${c.xp} · 气血 ${c.hp} · 灵力 ${c.mp} · 任务阶段 ${c.quest_stage}`));
                card.append(make('p',`地图 ${c.map_id} · 坐标 ${c.cell.join(', ')} · 状态版本 ${c.state_revision}`));
                const d=make('details');d.append(make('summary','角色、属性与物品详情'),make('pre',JSON.stringify(c,null,2)));card.append(d);
                const auditLink=make('a','查看角色操作记录');auditLink.href='/audit?account_id='+id+'&character_id='+encodeURIComponent(c.id);card.append(auditLink);
                el('user-characters').append(card);
            }
            if(!data.characters.length)el('user-characters').append(make('p','尚未创建角色'));
            el('user-sessions').textContent=JSON.stringify(data.sessions,null,2);
            el('user-status').textContent='账号详情已更新';
        } catch(e) {if(current===version){el('user-detail').hidden=true;el('user-status').textContent=`读取详情失败：${e.message}`;}}
        controls();
    }
    el('refresh').addEventListener('click',detail);
    el('user-action').addEventListener('submit',async e=>{
        e.preventDefault();if(busy || !csrf)return;
        const action=el('user-action-kind').value,reason=el('user-reason').value.trim();
        if(reason.length<2){el('user-action-status').textContent='请填写至少两个字的原因。';return;}
        const retry=uncertain && uncertain.action===action && uncertain.reason===reason;
        const warning=uncertain && !retry?`上次操作 ${uncertain.operation_id} 的结果未确认，请先查看审计记录。\n`:'';
        if(!window.confirm(`${warning}${retry?'沿用上次操作号重试。\n':''}${roleName?'当前角色：'+roleName+'\n':''}确定对账号 ${accountName}（${id}）执行“${el('user-action-kind').selectedOptions[0].textContent}”？\n此操作影响该账号的全部角色。`))return;
        busy=true;controls();el('user-action-status').textContent='正在执行，请勿重复提交…';
        const intent=retry?uncertain:{operation_id:crypto.randomUUID(),action,reason};
        if(selectedRole)intent.character_id=selectedRole;
        try {
            const result=await api(`/api/users/${id}/actions`,{method:'POST',headers:{'Content-Type':'application/json','X-Operator-Token':csrf},body:JSON.stringify(intent)});
            uncertain=null;el('user-action-status').textContent=`已执行，撤销 ${result.revoked_sessions} 个会话。操作 ID：${intent.operation_id}`;
            el('user-reason').value='';await detail();
        } catch(err) {uncertain=intent;el('user-action-status').textContent=`结果未确认：${err.message}。请先刷新账号与审计记录；相同动作和原因的重试将沿用原操作号。操作 ID：${intent.operation_id}`;}
        finally {busy=false;controls();}
    });
    detail();
})();
