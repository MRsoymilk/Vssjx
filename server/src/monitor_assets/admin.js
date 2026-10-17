"use strict";
window.Admin = Object.freeze({
    el: id => document.getElementById(id),
    make(tag, text) { const n=document.createElement(tag); if(text!==undefined) n.textContent=String(text); return n; },
    async api(path, options) {
        const response=await fetch(path,{cache:'no-store',signal:AbortSignal.timeout(15000),...options});
        const data=await response.json();
        if(!response.ok) throw new Error(data.code || `HTTP ${response.status}`);
        return data;
    },
    time: value => value ? new Date(value).toLocaleString() : '—',
    uuid: value => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value),
    listQuery() {
        const source=new URLSearchParams(location.search), q=(source.get('q')||'').slice(0,64), raw=Number(source.get('offset')||0);
        const offset=Number.isInteger(raw) && raw>=0 && raw<=100000 ? raw:0;
        const params=new URLSearchParams();if(q)params.set('q',q);if(offset)params.set('offset',String(offset));
        return {q,offset,suffix:params.size?'?'+params:''};
    }
});
