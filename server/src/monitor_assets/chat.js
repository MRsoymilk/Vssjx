"use strict";
(() => {
    const {el,make,api,time}=window.Admin;
    let csrf=null, epoch=null, busy=false, version=0, uncertain=null;
    const query=new URLSearchParams(location.search);
    let account=query.get('account_id') || '', search=query.get('q') || '';
    el('chat-query').value=search;
    const labels={delete:'删除发言',mute:'账号禁言',delete_and_mute:'删除并禁言',unmute:'解除禁言'};
    async function load() {
        if(busy)return;
        const current=++version, params=new URLSearchParams();
        if(account)params.set('account_id',account);if(search)params.set('q',search);
        try {
            const data=await api('/api/chat?'+params);
            if(current!==version || busy)return;
            csrf=data.csrf_token;epoch=data.channel_epoch;
            const accounts=[];
            for(const a of data.accounts) {
                const card=make('div'),button=make('button',a.muted?'解除禁言':'账号禁言');
                card.append(make('span',`${a.username} · ${a.display_name} · ${a.muted?'禁言至 '+time(Number(a.muted_until_ms)):'未禁言'}`));
                button.type='button';button.onclick=()=>act(a,a.muted?'unmute':'mute');card.append(button);accounts.push(card);
            }
            el('chat-admin-accounts').replaceChildren(...(accounts.length?accounts:[make('span','没有匹配账号；可输入用户名或角色名查询。')]));
            history.replaceState(null,'','/chat'+(params.size?'?'+params:''));
            const rows=[];
            for(const m of data.messages) {
                const tr=make('tr'),who=make('td'),body=make('td'),actions=make('td');
                tr.append(make('td',time(Number(m.server_time_ms))));
                who.append(make('strong',m.system?'系统':m.display_name));
                if(m.account_id) {
                    const link=make('a',m.username);link.href='/users/'+encodeURIComponent(m.account_id);who.append(link);
                    const filter=make('button','只看此账号');filter.type='button';filter.onclick=()=>{account=m.account_id;search='';el('chat-query').value='';load();};who.append(filter);
                    if(m.muted)who.append(make('small','禁言至 '+time(Number(m.muted_until_ms))));
                }
                body.className='chat-admin-body';body.textContent=m.deleted?'该发言已被管理员删除':m.text;
                if(m.deleted)body.classList.add('chat-admin-deleted');
                if(m.account_id && !m.system) {
                    for(const action of [...(!m.deleted?['delete','delete_and_mute']:[]),m.muted?'unmute':'mute']) {
                        const button=make('button',labels[action]);button.type='button';
                        button.addEventListener('click',()=>act(m,action));actions.append(button);
                    }
                }
                tr.append(who,body,actions);rows.push(tr);
            }
            el('chat-admin-list').replaceChildren(...rows);
            el('chat-admin-status').textContent=data.messages.length?`最近 ${data.messages.length} 条 · 每3秒刷新${account?' · 已按账号筛选':''}`:'当前筛选没有发言记录';
        } catch(error) {if(current===version)el('chat-admin-status').textContent='读取失败：'+error.message;}
    }
    async function act(message,action) {
        if(busy || !csrf)return;
        const reason=el('chat-reason').value.trim();
        if([...reason].length<2){el('chat-action-status').textContent='请填写至少两个字的公开处理原因。';return;}
        const intent={channel_epoch:epoch,account_id:message.account_id,message_id:message.deleted?null:message.message_id,action,reason,duration_seconds:action.includes('mute') && action!=='unmute'?Number(el('chat-duration').value):0};
        const key=JSON.stringify(intent),retry=uncertain?.key===key;
        const warning=uncertain&&!retry?`上一操作 ${uncertain.request.operation_id} 的结果未确认，请先核对聊天及审计记录。\n`:'';
        if(!window.confirm(`${warning}${labels[action]}：${message.display_name}（账号 ${message.username}）\n${intent.duration_seconds?'禁言 '+intent.duration_seconds/60+' 分钟，影响全部角色。\n':''}处理原因将显示在游戏聊天框：${reason}`))return;
        const request=retry?uncertain.request:{operation_id:crypto.randomUUID(),...intent};
        busy=true;for(const button of document.querySelectorAll('main button'))button.disabled=true;
        try {
            const result=await api('/api/chat/actions',{method:'POST',headers:{'Content-Type':'application/json','X-Operator-Token':csrf},body:JSON.stringify(request)});
            uncertain=null;el('chat-action-status').textContent='已处理：'+result.notice;el('chat-reason').value='';
        } catch(error) {uncertain={key,request};el('chat-action-status').textContent=`结果未确认：${error.message}。操作号 ${request.operation_id}；重试相同操作将沿用此操作号。`;}
        finally {busy=false;for(const button of document.querySelectorAll('main button'))button.disabled=false;load();}
    }
    el('chat-search').addEventListener('submit',event=>{event.preventDefault();search=el('chat-query').value.trim();load();});
    el('chat-clear').onclick=()=>{account='';search='';el('chat-query').value='';load();};
    el('refresh').addEventListener('click',load);
    setInterval(()=>{if(!document.hidden)load();},3000);load();
})();
