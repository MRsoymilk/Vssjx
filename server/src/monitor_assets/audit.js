/* Read-only audit page; URL filters and breadcrumbs survive reload and sharing. */
(() => {
    const {el,make,api,time,uuid}=window.Admin;
    const labels={accepted:'已执行',rejected:'拒绝',replayed:'重复请求',observed:'观察记录'};
    const initial=new URLSearchParams(location.search);
    let account=(initial.get('account_id')||'').toLowerCase(),character=(initial.get('character_id')||'').toLowerCase(),next=null,version=0,filterVersion=0,accountName='',roles=[];
    el('audit-account').value=account;
    el('audit-outcome').value=initial.get('outcome')||'';
    function breadcrumbs(name,roleName) {
        const ol=el('breadcrumbs');ol.replaceChildren();
        function item(text,href){const li=make('li');if(href){const a=make('a',text);a.href=href;li.append(a);}else{li.textContent=text;li.setAttribute('aria-current','page');}ol.append(li);}
        item('管理中心','/');
        if(account){item('用户管理','/users');item(name||'账号详情','/users/'+encodeURIComponent(account));}
        if(account && character && roleName)item(roleName,'/users/'+encodeURIComponent(account)+'?character_id='+encodeURIComponent(character));
        item('操作审计');
    }
    async function audit(append=false) {
        const current=++version,query=new URLSearchParams();
        breadcrumbs(accountName,roles.find(c=>c.id===character)?.display_name);
        if(account)query.set('account_id',account);
        if(character)query.set('character_id',character);
        if(el('audit-outcome').value)query.set('outcome',el('audit-outcome').value);
        history.replaceState(null,'','/audit'+(query.size?'?'+query:''));
        if(append && next)query.set('before',next);
        if(!append)el('audit-list').replaceChildren();
        el('audit-more').disabled=true;el('audit-status').textContent='正在获取记录…';
        el('audit-scope').textContent=account?`当前账号：${account}`:'全部账号';
        try {
            const data=await api('/api/audit?'+query);
            if(current!==version)return;
            for(const e of data.events) {
                const tr=make('tr'),first=make('td');first.append(make('div',time(e.created_at)));
                if(e.account_id){const link=make('a',e.account_id);link.href='/users/'+encodeURIComponent(e.account_id);first.append(link);}else first.append(make('small','未归属账号'));
                const outcome=make('td',`${labels[e.outcome]||e.outcome} · ${e.code}`);if(e.outcome==='rejected')outcome.className='bad';
                const td=make('td'),d=make('details');d.append(make('summary',`记录 #${e.id} · 查看详情`),make('pre',JSON.stringify({operation_id:e.operation_id,character_id:e.character_id,session_id:e.session_id,...e.details},null,2)));td.append(d);
                tr.append(first,make('td',e.action),outcome,td);el('audit-list').append(tr);
            }
            next=data.next_before;el('audit-more').disabled=!next;
            el('audit-status').textContent=data.events.length?`已显示 ${el('audit-list').children.length} 条记录`:'暂无符合条件的记录';
        } catch(e){if(current===version){el('audit-status').textContent=`读取失败：${e.message}`;el('audit-more').disabled=!append || !next;}}
    }
    async function scope() {
        const current=++filterVersion;
        accountName='';roles=[];
        const all=make('option','全部角色 / 账号操作');all.value='';el('audit-character').replaceChildren(all);el('audit-character').disabled=true;
        breadcrumbs();
        if(account) {
            try {
                const data=await api('/api/users/'+account);
                if(current!==filterVersion)return;
                accountName=data.account.username;roles=data.characters;
                breadcrumbs(accountName,roles.find(c=>c.id===character)?.display_name);
                for(const c of data.characters){const option=make('option',c.display_name);option.value=c.id;el('audit-character').append(option);}
                if(character && !data.characters.some(c=>c.id===character)){character='';await audit();}
                el('audit-character').value=character;el('audit-character').disabled=false;
            } catch(e){if(current===filterVersion)el('audit-scope').textContent=`账号详情不可用：${e.message} · ${account}`;}
        }
    }
    function applyAccount(){
        const value=el('audit-account').value.trim();
        if(value && !uuid(value)){el('audit-status').textContent='请填写完整账号 UUID，或留空查看全部账号。';return;}
        account=value.toLowerCase();character='';scope();audit();
    }
    el('audit-filter').addEventListener('submit',e=>{e.preventDefault();applyAccount();});
    el('audit-all').addEventListener('click',()=>{el('audit-account').value='';applyAccount();});
    el('audit-outcome').addEventListener('change',()=>audit());
    el('audit-character').addEventListener('change',()=>{character=el('audit-character').value;audit();});
    el('audit-more').addEventListener('click',()=>audit(true));
    for(const name of ['audit-refresh','refresh'])el(name).addEventListener('click',()=>{scope();audit();});
    if((account && !uuid(account)) || (character && (!account || !uuid(character)))){el('audit-status').textContent='链接中的账号或角色 ID 无效。';return;}
    scope();audit();
})();
