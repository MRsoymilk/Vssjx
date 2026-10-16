// Real persistent Chromium profile + real Godot single-threaded Web fixture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base, output] = process.argv.slice(2);
const source = fs.readFileSync(path.join(__dirname, '../client/scripts/interface/adapters/web/indexeddb_storage.js'), 'utf8');
let context;
let checks = 0;
const logs = [];
const engines = new Set();
const check = (value, description) => {assert.ok(value, description); checks++;};
async function launch() {
    const context = await chromium.launchPersistentContext(path.join(output, 'browser-profile'), {
        headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
        args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
    });
    await context.addInitScript({path:path.join(__dirname, 'fixtures/web_storage/faults.js')});
    return context;
}

async function coreTests(page) {
    await page.goto(base + '/core.html');
    return page.evaluate(async source => {
        const factory = (0, eval)(source);
        let checks = 0, next = 0;
        const check = (value, description) => {if (!value) throw new Error(description); checks++;};
        const slot = 'offline://save-v1';
        const original = '原始离线记录\n不会在事务请求成功时提前确认';
        const env = () => ({indexedDB, navigator, isSecureContext, setTimeout: setTimeout.bind(globalThis), clearTimeout: clearTimeout.bind(globalThis)});
        const request = (port, kind, text = '', maximum = 1048576, target = slot) => new Promise(resolve => port.submit(++next, kind, target, text, maximum, data => resolve(JSON.parse(data))));
        const remove = () => new Promise((resolve, reject) => {
            const deletion = indexedDB.deleteDatabase('vssjx-offline-v1');
            deletion.onsuccess = resolve;
            deletion.onerror = () => reject(new Error('Owned test database deletion failed'));
            deletion.onblocked = () => reject(new Error('A fixture connection leaked'));
        });
        const ports = [];
        const create = (environment = env(), timeout) => {const port = factory.create(environment, timeout); ports.push(port); return port;};
        function wrappedEnvironment(mode, evidence) {
            const environment = env();
            const cache = new WeakMap();
            environment.indexedDB = {open(...args) {
                const opened = indexedDB.open(...args);
                return new Proxy(opened, {
                    get(target, key) {
                        if (key === 'result') {
                            const database = target.result;
                            if (!cache.has(database)) cache.set(database, new Proxy(database, {
                                get(db, field) {
                                    if (field === 'transaction') return (...parts) => {
                                        if (mode === 'timeout' && evidence.hang) {
                                            const fake = {error: null, abort() {evidence.aborted = true;}, objectStore() {return {put() {return {};}};}};
                                            evidence.transaction = fake;
                                            return fake;
                                        }
                                        const transaction = db.transaction(...parts);
                                        return new Proxy(transaction, {
                                            get(tx, property) {
                                                if (property === 'objectStore') return (...storeArgs) => {
                                                    const store = tx.objectStore(...storeArgs);
                                                    return new Proxy(store, {get(objectStore, name) {
                                                        if (name === 'put') return (...putArgs) => {
                                                            if (mode === 'quota') throw new DOMException('do-not-log-sensitive', 'QuotaExceededError');
                                                            const write = objectStore.put(...putArgs);
                                                            if (mode === 'abort-after-put') write.addEventListener('success', () => {evidence.putSucceeded = true; tx.abort();});
                                                            return write;
                                                        };
                                                        const value = Reflect.get(objectStore, name, objectStore);
                                                        return typeof value === 'function' ? value.bind(objectStore) : value;
                                                    }});
                                                };
                                                const value = Reflect.get(tx, property, tx);
                                                return typeof value === 'function' ? value.bind(tx) : value;
                                            },
                                            set(tx, property, value) {return Reflect.set(tx, property, value, tx);},
                                        });
                                    };
                                    const value = Reflect.get(db, field, db);
                                    return typeof value === 'function' ? value.bind(db) : value;
                                },
                                set(db, field, value) {return Reflect.set(db, field, value, db);},
                            }));
                            return cache.get(database);
                        }
                        const value = Reflect.get(target, key, target);
                        return typeof value === 'function' ? value.bind(target) : value;
                    },
                    set(target, key, value) {return Reflect.set(target, key, value, target);},
                });
            }};
            return environment;
        }
        await remove();
        try {
            const port = create();
            check((await request(port, 'read')).code === 'STORAGE_NOT_READY', 'No read before initialization');
            check((await request(port, 'initialize')).ok, 'Real IndexedDB opens');
            check((await request(port, 'probe')).value === false, 'Missing slot is explicit false');
            check((await request(port, 'read')).code === 'NOT_FOUND', 'Missing read is not corruption');
            const saved = await request(port, 'write', original);
            check(saved.ok && saved.value.written && saved.value.durability === 'browser_sync', 'Transaction completion creates receipt');
            check(saved.value.bytes === new TextEncoder().encode(original).byteLength, 'UTF8 byte count');
            check((await request(port, 'read')).value === original, 'Exact Unicode round trip');
            check((await request(port, 'probe')).value === true, 'Existing slot');
            check((await request(port, 'read', '', 4)).code === 'TOO_LARGE', 'Bounded read');
            check((await request(port, 'read', '', 0)).code === 'INVALID_LIMIT', 'Invalid read limit');
            check((await request(port, 'write', 'not a credential', 1048576, 'user://connection.cfg.login')).code === 'INVALID_PATH', 'No arbitrary files or credential slots');
            check((await request(port, 'write', '界'.repeat(400000))).code === 'TOO_LARGE', 'Byte cap before write');
            check((await request(port, 'read')).value === original, 'Rejected operations preserve original record');
            const other = create();
            check((await request(other, 'initialize')).ok && (await request(other, 'read')).value === original, 'Independent connection reads committed transaction');
            const abortEvidence = {};
            const aborted = create(wrappedEnvironment('abort-after-put', abortEvidence));
            check((await request(aborted, 'initialize')).ok, 'Fault port opens real DB');
            const abortResult = await request(aborted, 'write', 'must-roll-back');
            check(abortEvidence.putSucceeded === true && !abortResult.ok, 'Put success followed by transaction abort is failure, never a receipt');
            check((await request(port, 'read')).value === original, 'Aborted transaction preserves last good record');
            const quota = create(wrappedEnvironment('quota', {}));
            await request(quota, 'initialize');
            check((await request(quota, 'write', 'too-much')).code === 'QUOTA_EXCEEDED', 'Quota code does not echo raw error');
            check((await request(port, 'read')).value === original, 'Quota failure preserves old save');
            const timedEvidence = {hang: true};
            const timed = create(wrappedEnvironment('timeout', timedEvidence), 100);
            await request(timed, 'initialize');
            const timeout = await request(timed, 'write', 'unknown-result');
            check(timeout.code === 'STORAGE_TIMEOUT' && timeout.uncertain === true && timedEvidence.aborted, 'Bounded uncertain timeout attempts abort');
            timedEvidence.transaction.oncomplete();
            check(JSON.parse(timed.status_json()).state === 'failed', 'Late completion cannot restore readiness or claim success');
            check((await request(timed, 'read')).code === 'STORAGE_NOT_READY', 'Timed out port requires explicit recovery');
            timedEvidence.hang = false;
            check((await request(timed, 'initialize')).ok && (await request(timed, 'read')).value === original, 'Recovery reopens and checks actual stored state');
            let lateRequest, lateClosed = 0;
            const lateEnv = env();
            lateEnv.indexedDB = {open() {return lateRequest = {result: {close() {lateClosed++;}}};}};
            const late = create(lateEnv, 20);
            check((await request(late, 'initialize')).code === 'STORAGE_TIMEOUT', 'Open timeout');
            lateRequest.onsuccess();
            check(lateClosed === 1 && JSON.parse(late.status_json()).state === 'failed', 'Late open is closed, not installed');
            const blockedEnv = env();
            let blockedRequest, blockedClosed = 0;
            blockedEnv.indexedDB = {open() {
                blockedRequest = {result: {close() {blockedClosed++;}}};
                setTimeout(() => blockedRequest.onblocked(), 1);
                return blockedRequest;
            }};
            const blocked = create(blockedEnv);
            check((await request(blocked, 'initialize')).code === 'STORAGE_BLOCKED', 'Blocked open is explicit');
            blockedRequest.onsuccess();
            check(blockedClosed === 1, 'Blocked late connection drained');
            const unsupported = create({...env(), indexedDB: null});
            check((await request(unsupported, 'initialize')).code === 'STORAGE_UNSUPPORTED', 'Missing API fails closed');
            const insecure = create({...env(), isSecureContext: false});
            check((await request(insecure, 'initialize')).code === 'STORAGE_DENIED', 'Untrusted HTTP context is not accepted for storage');
            const denied = create({...env(), indexedDB: {open() {throw new DOMException('do-not-log-sensitive', 'SecurityError');}}});
            check((await request(denied, 'initialize')).code === 'STORAGE_DENIED', 'Denied storage is not absence');
            const pendingEvidence = {hang: true};
            const disposed = create(wrappedEnvironment('timeout', pendingEvidence), 100);
            await request(disposed, 'initialize');
            let callbacks = 0;
            disposed.submit(++next, 'write', slot, 'x', 1048576, () => callbacks++);
            disposed.dispose();
            await new Promise(resolve => setTimeout(resolve, 40));
            check(callbacks === 0 && pendingEvidence.aborted, 'Disposal releases JS callbacks and aborts owned work');
            check((await request(disposed, 'read')).code === 'STORAGE_CLOSED', 'Closed port cannot be reused');
            await new Promise((resolve, reject) => {
                const opened = indexedDB.open('vssjx-offline-v1', 1);
                opened.onerror = reject;
                opened.onsuccess = () => {
                    const db = opened.result, tx = db.transaction('saves', 'readwrite');
                    tx.objectStore('saves').put(undefined, 'save-v1');
                    tx.oncomplete = () => {db.close(); resolve();};
                    tx.onabort = reject;
                };
            });
            check((await request(port, 'probe')).code === 'INVALID_STORED_DATA' && (await request(port, 'read')).code === 'INVALID_STORED_DATA', 'An existing undefined record is corruption, never an absent slot');
            for (const connection of ports) connection.dispose();
            check(ports.every(connection => JSON.parse(connection.status_json()).state === 'closed'), 'All owned connections closed');
        } finally {
            for (const connection of ports) connection.dispose();
            await remove();
        }
        return checks;
    }, source);
}

async function newGamePage() {
    const page = await context.newPage();
    page.on('console', message => {if (message.type() === 'error') logs.push(message.text());});
    page.on('pageerror', error => logs.push(error.message));
    await page.goto(base + '/index.html?server=https://ignored.invalid&save_path=forbidden#ignored');
    await ready(page);
    return page;
}
async function ready(page) {
    await page.waitForFunction(() => globalThis.__vssjxStorageTest?.results.some(row => row.action === 'ready'), undefined, {timeout: 60000});
    const result = await page.evaluate(() => __vssjxStorageTest.results.find(row => row.action === 'ready'));
    engines.add(result.engine);
    check(result.ok && result.extra.web && result.extra.slot === 'offline://save-v1', 'Actual Godot Web, not native policy injection');
    check(result.extra.status.state === 'ready', 'Actual JSBridge initialization completes');
    return result;
}
async function command(page, action) {
    const count = await page.evaluate(() => __vssjxStorageTest.results.length);
    await page.evaluate(action => __vssjxStorageTest.command(action), action);
    await page.waitForFunction(count => __vssjxStorageTest.results.length > count, count, {timeout: 30000});
    const result = await page.evaluate(() => __vssjxStorageTest.results.at(-1));
    check(result.action === action, 'Callback matched command');
    return result;
}
async function restored(page) {
    const result = await command(page, 'read');
    check(result.ok && result.extra.name === '网页存档' && result.extra.gold === 147 && result.extra.gender === 1 && result.extra.version === 1 && result.extra.signature === '刷新后验证原样恢复', 'Persisted unwrapped v1 player restored after page/process boundary');
}

async function replaceRecord(page, value) {
    await page.evaluate(value => new Promise((resolve, reject) => {
        const open = indexedDB.open('vssjx-offline-v1', 1);
        open.onerror = reject;
        open.onsuccess = () => {
            const db = open.result, tx = db.transaction('saves', 'readwrite');
            tx.objectStore('saves').put(value, 'save-v1');
            tx.oncomplete = () => {db.close(); resolve();};
            tx.onabort = reject;
        };
    }), value);
}

(async () => {
    context = await launch();
    try {
        const core = await context.newPage();
        checks += await coreTests(core);
        await core.close();
        let page = await newGamePage();
        check((await command(page, 'probe')).value === false, 'Cold Godot slot absent');
        const saved = await command(page, 'write');
        check(saved.ok && saved.value.durability === 'browser_sync' && saved.value.written, 'Real Godot Game receives only the IndexedDB completion receipt');
        check((await command(page, 'small-read')).code === 'TOO_LARGE', 'GDScript bounded read');
        check((await command(page, 'wrong-path')).code === 'INVALID_PATH', 'GDScript cannot choose credential path');
        check((await command(page, 'oversize')).code === 'TOO_LARGE', 'GDScript UTF8 cap');
        const credentials = await command(page, 'credentials');
        check(credentials.extra.native_policy && !credentials.extra.supported && !credentials.extra.path && Object.keys(credentials.extra.read).length === 0 && !credentials.extra.write && !credentials.extra.forget, 'Real OS web feature blocks all remembered credential operations even with an injected native policy');
        check(!credentials.extra.files.some(name => /\.login|\.key$|\.tmp$/.test(name)), 'No credential or temporary files in Godot user filesystem');
        const record = await page.evaluate(() => new Promise((resolve, reject) => {
            const open = indexedDB.open('vssjx-offline-v1', 1);
            open.onerror = reject;
            open.onsuccess = () => {
                const db = open.result, tx = db.transaction('saves', 'readonly'), store = tx.objectStore('saves');
                const value = store.get('save-v1'), keys = store.getAllKeys();
                tx.oncomplete = () => {db.close(); resolve({text:value.result, keys:keys.result});};
                tx.onabort = reject;
            };
        }));
        check(record.keys.length === 1 && record.keys[0] === 'save-v1', 'Only named offline slot, not generic configuration or secret store');
        const data = JSON.parse(record.text);
        check(data.version === 1 && data.name === '网页存档' && !/password|access_token|refresh_token/.test(record.text), 'Raw v1 save schema without storage envelope or credentials');
        await page.reload();
        await ready(page);
        await restored(page);
        await page.close();
        page = await newGamePage();
        await restored(page);
        check((await command(page, 'cancel-read')).code === 'STORAGE_CLOSED', 'Disposed GDScript port completes owned pending request as cancelled');
        await page.close();
        page = await newGamePage();
        check((await command(page, 'release-read')).code === 'STORAGE_CLOSED', 'Dropping the RefCounted port drains pending consumers without self-calls or callback leaks');
        await page.close();
        await context.close();
        context = await launch();
        page = await newGamePage();
        await restored(page);
        const status = await command(page, 'status');
        check(['unknown', 'best_effort', 'persistent'].includes(status.value.retention), 'Retention state is reported separately, not promised forever');
        for (const [mode, code] of [['quota', 'QUOTA_EXCEEDED'], ['abort', 'SYNC_FAILED']]) {
            await page.evaluate(mode => {globalThis.__vssjxFixtureFault = mode;}, mode);
            const rejected = await command(page, 'write-alternate');
            check(!rejected.ok && rejected.code === code && Object.keys(rejected.extra.receipt).length === 0, 'Real Godot failure path cannot publish a save receipt');
            check(rejected.extra.name === '未确认新角色' && rejected.extra.gold === 299, 'Unconfirmed progress remains in Game memory');
            await page.evaluate(() => {globalThis.__vssjxFixtureFault = 'none';});
            await restored(page);
        }
        await page.evaluate(() => {globalThis.__vssjxFixtureFault = 'suppress-completion';});
        const timed = await command(page, 'write-alternate');
        check(!timed.ok && timed.code === 'STORAGE_TIMEOUT' && timed.value.uncertain && Object.keys(timed.extra.receipt).length === 0, 'Real 15-second bridge timeout remains an uncertain failure even if transaction committed');
        await page.evaluate(() => {globalThis.__vssjxFixtureFault = 'none';});
        check((await command(page, 'probe')).code === 'STORAGE_NOT_READY', 'Timed-out Game port requires recovery instead of accepting stale state');
        check((await command(page, 'recover')).ok, 'Actual GDScript/JSBridge port can explicitly recover after timeout');
        const recovered = await command(page, 'read');
        check(recovered.ok && recovered.extra.name === '未确认新角色' && recovered.extra.gold === 299, 'Recovery reads the real committed state rather than guessing rollback');
        await replaceRecord(page, record.text);
        await restored(page);
        await replaceRecord(page, '{broken');
        const corrupt = await command(page, 'read');
        check(corrupt.code === 'INVALID_SAVE' && corrupt.extra.name === '读取前内存角色', 'Corrupt persisted JSON cannot replace the active player');
        await replaceRecord(page, {bad: true});
        check((await command(page, 'probe')).code === 'INVALID_STORED_DATA', 'Corrupt record type is not an absent slot');
        await replaceRecord(page, record.text);
        await restored(page);
        const isolated = await context.newPage();
        await isolated.goto(base.replace('127.0.0.1', 'localhost') + '/core.html');
        const otherOrigin = await isolated.evaluate(async source => {
            const port = (0, eval)(source).create();
            let id = 0;
            const request = kind => new Promise(resolve => port.submit(++id, kind, 'offline://save-v1', '', 1048576, value => resolve(JSON.parse(value))));
            try {await request('initialize'); return await request('probe');}
            finally {port.dispose();}
        }, source);
        check(otherOrigin.ok && otherOrigin.value === false, 'Same database name on another origin cannot read the save');
        await isolated.close();
        await restored(page);
        await page.evaluate(() => new Promise((resolve, reject) => {
            const request = indexedDB.deleteDatabase('vssjx-offline-v1');
            request.onsuccess = resolve;
            request.onerror = reject;
            request.onblocked = () => reject(new Error('Versionchange connection not released'));
        }));
        check((await command(page, 'probe')).code === 'STORAGE_NOT_READY', 'Site data deletion closes the old connection, not a stale memory success');
        await page.reload();
        await ready(page);
        check((await command(page, 'probe')).value === false, 'Data cleared by user remains absent after reload');
        check((await command(page, 'close')).code === 'STORAGE_CLOSED', 'Explicit close cannot perform further IO');
        check(logs.length === 0, 'No Godot/JS errors or sensitive diagnostics');
        check([...engines].every(version => version.startsWith('4.7.2')), 'Matching real Web engine version');
        fs.writeFileSync(path.join(output, 'browser-report.json'), JSON.stringify({checks, failures:0, browser:await context.browser().version(), engines:[...engines],
            scope:'Chromium core fault tests + real Godot Web reload/reopen/browser-process restart; not full game or mobile acceptance'}, null, 2));
        console.log(`WEB STORAGE BROWSER: ${checks} checks, 0 failures`);
    } finally {if (context) await context.close();}
})().catch(error => {console.error(error.stack);process.exitCode = 1;});
