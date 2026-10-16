// Real browser WebSocket Origin and first-packet auth only, not a Godot Web game.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [allowed, denied, websocket, output] = process.argv.slice(2);
const credentials = JSON.parse(fs.readFileSync(0, 'utf8')); // Memory-only ticket, never argv/URL/file storage.
(async () => {
    const browser = await chromium.launch({headless:true, executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    let checks = 0;
    const check = value => {assert.ok(value); checks++;};
    try {
        const page = await browser.newPage();
        await page.goto(allowed);
        check(await page.evaluate(() => location.origin) === allowed);
        const result = await page.evaluate(({url, ticket, hash}) => new Promise((resolve, reject) => {
            const socket = new WebSocket(url);
            let ready = null, snapshot = null, records = [], chunks = 0, synchronized = false;
            const timer = setTimeout(() => {socket.close(); reject(new Error('WebSocket fixture timed out'));}, 10000);
            socket.onopen = () => socket.send(JSON.stringify({type:'auth.exchange', ticket, protocol_version:1, config_hash:hash, world_sync_version:2}));
            socket.onerror = () => {clearTimeout(timer); reject(new Error('Allowed WebSocket failed'));};
            socket.onmessage = event => {
                if (typeof event.data !== 'string') return;
                const data = JSON.parse(event.data);
                if (data.type === 'error') {clearTimeout(timer); socket.close(); reject(new Error('World auth rejected fixture'));}
                if (data.type === 'auth.ready') ready = data;
                if (data.type === 'snapshot.begin') {snapshot = data; records = []; chunks = 0;}
                if (data.type === 'snapshot.chunk') {records.push(...data.records); chunks++;}
                if (data.type === 'snapshot.end' && ready && snapshot && data.snapshot_id === snapshot.snapshot_id && records.length === data.count && chunks === data.chunks) {
                    synchronized = true;
                    socket.send(JSON.stringify({type:'world.leave'}));
                }
            };
            socket.onclose = () => {
                clearTimeout(timer);
                resolve({ready:ready?.character_id, synchronized, self:records.some(row => row.id === ready?.character_id), url:socket.url});
            };
        }), {url:websocket, ...credentials});
        check(result.ready === credentials.character && result.synchronized && result.self);
        check(!new URL(result.url).search && !new URL(result.url).hash);
        check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0));
        await page.goto(denied);
        check(await page.evaluate(() => location.origin) !== allowed);
        const rejected = await page.evaluate(url => new Promise(resolve => {
            const socket = new WebSocket(url);
            const timer = setTimeout(() => {socket.close(); resolve(false);}, 8000);
            socket.onopen = () => {clearTimeout(timer); socket.close(); resolve(false);};
            socket.onerror = () => {clearTimeout(timer); resolve(true);};
            socket.onclose = () => {clearTimeout(timer); resolve(true);};
        }), websocket);
        check(rejected);
        fs.writeFileSync(`${output}/browser.json`, JSON.stringify({checks, failures:0, browser:browser.version(), scope:'Local browser WebSocket fixture only; not Godot Web or mobile acceptance'}, null, 2));
        console.log(`WEB ORIGIN BROWSER: ${checks} checks, 0 failures`);
    } finally {await browser.close();}
})().catch(() => {console.error('Web Origin browser fixture failed; no credentials are logged.');process.exit(1);});
