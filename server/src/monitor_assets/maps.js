"use strict";
(() => {
    const {el,make,api}=Admin;
    let maps=[], current=null, draft=null, token='', busy=false, selected=null, pending=null;
    const errors={STALE_MAP_DRAFT:'草稿已被其他窗口修改，请重新载入后编辑。',STALE_MAP_BASE:'生效版本已变化，请恢复到草稿后重新编辑。',MAP_VALIDATION_FAILED:'配置校验失败，请先校验并修正。',INVALID_OPERATOR_TOKEN:'管理凭证已失效，请刷新页面。'};
    function status(text){el('map-status').textContent=text;}
    function lock(){
        for(const node of document.querySelectorAll('#map-editor input,#map-editor select,#map-editor button,#map-select,#map-search,#map-reload'))node.disabled=busy||pending!==null;
        el('map-retry').disabled=busy;
    }
    function label(parent,text,node){const l=make('label',text);l.append(node);parent.append(l);return node;}
    function input(parent,text,value,set,type='number',min=0,max=31){const n=make('input');n.type=type;n.value=value;if(type==='number'){n.min=min;n.max=max;n.step=1;}n.addEventListener('input',()=>{set(type==='number'?Number(n.value):n.value);draw();});return label(parent,text,n);}
    function toggle(parent,text,value,set){const n=make('input');n.type='checkbox';n.checked=value;n.addEventListener('change',()=>{set(n.checked);draw();});return label(parent,text,n);}
    function coords(parent,text,value,set){const wrap=make('span');wrap.className='map-coordinate';const x=input(wrap,text+' X',value[0],v=>{value[0]=v;set([...value]);});const y=input(wrap,'Y',value[1],v=>{value[1]=v;set([...value]);});const b=make('button','定位');b.type='button';b.onclick=()=>{selected=c=>{value[0]=c[0];value[1]=c[1];x.value=c[0];y.value=c[1];set([...c]);};el('map-coordinate').textContent='请点击网格设置：'+text;};wrap.append(b);parent.append(wrap);}
    function draw(){if(!current||!draft)return;const c=el('map-grid'),ctx=c.getContext('2d'),s=c.width/32;ctx.clearRect(0,0,c.width,c.height);for(let i=0;i<1024;i++){ctx.fillStyle=current.terrain.blocked[i]?'#566273':'#e8edf0';ctx.fillRect(i%32*s,Math.floor(i/32)*s,s-1,s-1);}const dot=(p,color)=>{ctx.fillStyle=color;ctx.fillRect(p[0]*s+2,p[1]*s+2,s-4,s-4);};dot(draft.spawn,'#168441');for(const p of draft.residents)if(p.enabled)dot(p.cell,current.residents.find(r=>r.id===p.id)?.kind==='npc'?'#1673d1':'#c93737');for(const p of draft.portals)if(p.enabled)for(const cell of p.cells)dot(cell,'#8b3bcc');for(const n of draft.gathering)if(n.enabled)dot(n.cell,'#c08713');}
    function options(){const q=el('map-search').value.trim().toLowerCase(),id=el('map-select').value;el('map-select').replaceChildren();for(const m of maps.filter(m=>(m.id+' '+m.name).toLowerCase().includes(q))){const o=make('option',`${m.name} · ${m.id}${m.entry_enabled?'':' · 禁入'}`);o.value=m.id;el('map-select').append(o);}if([...el('map-select').options].some(o=>o.value===id))el('map-select').value=id;else if(current)el('map-select').selectedIndex=-1;}
    async function load(){if(busy||pending)return;const id=el('map-select').value;if(!id)return;busy=true;try{current=await api('/api/maps/'+encodeURIComponent(id));token=current.csrf_token;draft=structuredClone(current.document);render();status('草稿已载入；尚未发布的编辑不会影响游戏。');}catch(e){status(e.message);}finally{busy=false;}}
    function render(){selected=null;el('map-editor').hidden=false;el('map-title').textContent=current.name+' · '+current.id;el('map-version').textContent=`生效版本 ${current.active_revision} / 草稿 ${current.revision} / 草稿基于 ${current.base_revision}`;el('map-activation').textContent=current.activation;el('map-entry').checked=draft.entry_enabled;el('map-station-enabled').checked=draft.station_enabled;el('map-entry').onchange=e=>draft.entry_enabled=e.target.checked;el('map-station-enabled').onchange=e=>draft.station_enabled=e.target.checked;for(const id of ['map-spawn','map-station','map-residents','map-portals','map-gathering','map-errors'])el(id).replaceChildren();coords(el('map-spawn'),'出生',draft.spawn,v=>draft.spawn=v);coords(el('map-station'),'驿站',draft.station,v=>draft.station=v);
        for(const p of draft.residents){const source=current.residents.find(r=>r.id===p.id),tr=make('tr');tr.append(make('td',(source?.name||p.id)+' / '+p.id),make('td',source?.kind==='npc'?'NPC':'怪物'));let td=make('td');toggle(td,'',p.enabled,v=>p.enabled=v);tr.append(td);td=make('td');coords(td,'',p.cell,v=>p.cell=v);tr.append(td);td=make('td');if(source?.kind!=='npc')input(td,'',p.respawn_seconds,v=>p.respawn_seconds=v,'number',1,86400);tr.append(td);el('map-residents').append(tr);}
        for(const p of draft.portals){const f=make('fieldset');f.append(make('legend',p.id));toggle(f,'启用',p.enabled,v=>p.enabled=v);input(f,'名称',p.name,v=>p.name=v,'text');coords(f,'主格',p.cell,v=>{const old=p.cells[0];p.cell=v;if(p.cells.length===1&&old){p.cells=[v];cells.value=v.join(',');}});const cells=input(f,'触发格',p.cells.map(c=>c.join(',')).join('; '),v=>p.cells=v.split(';').map(c=>c.trim().split(',').map(Number)),'text');const target=make('select');for(const m of maps){const o=make('option',m.name+' / '+m.id);o.value=m.id;target.append(o);}target.value=p.target_map;target.onchange=()=>p.target_map=target.value;label(f,'目标地图',target);toggle(f,'指定到达坐标',p.arrival!==null,v=>{p.arrival=v?[...p.arrival||[5,16]]:null;render();});if(p.arrival)coords(f,'到达',p.arrival,v=>p.arrival=v);el('map-portals').append(f);}
        for(const n of draft.gathering){const f=make('fieldset');f.append(make('legend',n.id));toggle(f,'启用',n.enabled,v=>n.enabled=v);coords(f,'采集点',n.cell,v=>n.cell=v);const m=make('select');for(const [id,name] of Object.entries({iron:'铁矿',copper:'铜矿',gancao:'甘草',danggui:'当归'})){const o=make('option',name);o.value=id;m.append(o);}m.value=n.material;m.onchange=()=>n.material=m.value;label(f,'材料',m);input(f,'采集毫秒',n.duration_ms,v=>n.duration_ms=v,'number',1000,60000);input(f,'刷新毫秒',n.respawn_ms,v=>n.respawn_ms=v,'number',1000,86400000);input(f,'最少',n.min_quantity,v=>n.min_quantity=v,'number',1,10);input(f,'最多',n.max_quantity,v=>n.max_quantity=v,'number',1,10);el('map-gathering').append(f);}
        el('map-history').replaceChildren();const initial=make('option','0 · 初始配置');initial.value='0';el('map-history').append(initial);for(const h of current.history){const o=make('option',`${h.revision} · ${Admin.time(h.created_at)} · ${h.reason}`);o.value=h.revision;el('map-history').append(o);}draw();}
    async function request(action,document=null,release=null){const body={operation_id:crypto.randomUUID(),action,revision:current.revision,reason:el('map-reason').value.trim(),document:structuredClone(document),release};pending={id:current.id,body};return sendPending();}
    async function sendPending(){const p=pending;try{const result=await api('/api/maps/'+encodeURIComponent(p.id)+'/actions',{method:'POST',headers:{'Content-Type':'application/json','Origin':location.origin,'X-Operator-Token':token},body:JSON.stringify(p.body)});pending=null;el('map-retry').hidden=true;current.revision=result.revision;current.active_revision=result.active_revision;el('map-version').textContent=`生效版本 ${result.active_revision} / 草稿 ${result.revision}`;el('map-errors').replaceChildren(...result.errors.map(e=>make('li',e)));return result;}catch(e){if(/^[A-Z_]+$/.test(e.message)){pending=null;el('map-retry').hidden=true;}else{el('map-retry').hidden=false;}throw e;}}
    async function action(kind){
        if(busy||pending||!current)return;
        if(el('map-reason').value.trim().length<2){status('请填写至少2个字的操作原因。');return;}
        if(kind==='publish'&&!confirm('确认发布当前配置？将作用于后续交互和旅行，不改变已有战斗与玩家位置。'))return;
        busy=true;lock();
        try{
            if(kind==='restore')await request(kind,null,Number(el('map-history').value));
            else{
                await request('save',draft);
                if(kind!=='save'){
                    const result=await request('validate');
                    if(result.errors.length){status('校验未通过，请修正列出的错误。');return;}
                    if(kind==='publish')await request('publish');
                }
            }
            status(kind==='publish'?'已发布，世界将在下次刷新应用。':kind==='restore'?'历史版本已恢复为草稿，尚未生效。':kind==='validate'?'校验通过，尚未发布。':'草稿已保存，尚未生效。');
            if(kind==='publish'||kind==='restore'){
                current=await api('/api/maps/'+encodeURIComponent(current.id));draft=structuredClone(current.document);render();
                const item=maps.find(m=>m.id===current.id);item.entry_enabled=current.active.entry_enabled;
                options();el('map-select').value=current.id;
            }
        }catch(e){status(errors[e.message]||e.message);}
        finally{busy=false;lock();}
    }
    el('map-grid').onclick=e=>{if(busy||pending)return;const r=e.target.getBoundingClientRect(),c=[Math.floor((e.clientX-r.left)/r.width*32),Math.floor((e.clientY-r.top)/r.height*32)];if(selected){selected(c);selected=null;draw();}el('map-coordinate').textContent=`坐标 ${c.join(', ')} ${current.terrain.blocked[c[1]*32+c[0]]?'不可行走':'可行走'}`;};
    el('map-search').oninput=options;el('map-select').onchange=()=>{if(confirm('切换地图将丢弃未保存的页面编辑，继续？'))load();else el('map-select').value=current.id;};el('map-reload').onclick=()=>{if(confirm('重新载入会丢弃未保存的页面编辑，继续？'))load();};for(const a of ['save','validate','publish','restore'])el('map-'+a).onclick=()=>action(a);el('map-retry').onclick=async()=>{if(busy||!pending)return;busy=true;lock();try{await sendPending();status('未确认操作已取得回执，请重新载入查看。');}catch(e){status(errors[e.message]||e.message);}finally{busy=false;lock();}};
    api('/api/maps').then(data=>{maps=data.maps;token=data.csrf_token;options();return load();}).catch(e=>status(e.message));
})();
