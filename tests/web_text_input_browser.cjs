// Chromium touch emulation plus real WASM/Rust chat; not physical Android/iOS keyboard acceptance.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base, output] = process.argv.slice(2);
const credentials = JSON.parse(fs.readFileSync(0, 'utf8'));
(async () => {
    const browser = await chromium.launch({headless: true,
        executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
        args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader']});
    const page = await browser.newPage({viewport: {width: 390, height: 844}, hasTouch: true, isMobile: true});
    const errors = [], sent = [], received = [];
    let checks = 0;
    const check = (ok, label) => {assert.ok(ok, label); checks++; console.log('PASS: ' + label);};
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text());});
    page.on('websocket', ws => {
        ws.on('framesent', frame => {try {const data = JSON.parse(frame.payload); if(data.type === 'chat.send') sent.push(data);} catch {}});
        ws.on('framereceived', frame => {try {const data = JSON.parse(frame.payload); if(data.type.startsWith('chat.')) received.push(data);} catch {}});
    });
    async function tap(x, y) {
        const bounds = await page.locator('#canvas').boundingBox();
        await page.touchscreen.tap(bounds.x + x / 320 * bounds.width, bounds.y + y / 480 * bounds.height);
        await page.waitForTimeout(300);
    }
    const field = name => page.locator(`[data-field-name="${name}"]`);
    try {
        await page.addInitScript(() => {
            window.engineImeFocusCount = 0;
            window.addEventListener('focus', e => {
                if (e.target.isContentEditable && document.getElementById('frame')?.contains(e.target)) window.engineImeFocusCount++;
            }, true);
        });
        await page.goto(base);
        await page.locator('#start').tap();
        await page.waitForFunction(() => document.getElementById('loading').style.display === 'none', null, {timeout: 90000});
        await page.waitForTimeout(1200);
        await tap(235, 414);
        await tap(160, 192);
        check(await field('Username').evaluate(e => document.activeElement === e), 'Touch selects the browser-native username input');
        await page.keyboard.type(credentials.username); // No artificial typing delay.
        await tap(160, 240);
        check(await field('Password').evaluate(e => document.activeElement === e && e.type === 'password'), 'Touch focuses a masked browser-native password input');
        await page.keyboard.insertText(credentials.password);
        await page.waitForTimeout(600);
        check(await field('Password').evaluate(e => document.activeElement === e) && await page.evaluate(() => engineImeFocusCount === 0), 'Focus stays with the native password field without a hidden engine IME handoff');
        await page.setViewportSize({width: 390, height: 440});
        await page.waitForTimeout(300);
        check(await field('Password').evaluate(e => {const r=e.getBoundingClientRect(); return r.y >= 0 && r.bottom <= innerHeight;}), 'Password stays within the resized keyboard viewport');
        const reply = page.waitForResponse(r => r.url() === base + '/api/v1/auth/login');
        await field('Password').press('Enter');
        check((await reply).status() === 200, 'Rapid input and a Unicode password reach the real account service intact');
        await page.waitForTimeout(1200);
        check(await field('Password').count() === 0, 'Leaving login removes the DOM password field');
        await page.setViewportSize({width: 390, height: 844});
        await page.waitForTimeout(500);
        await tap(160, 466);
        await field('ChatInput').waitFor({state: 'attached', timeout: 15000});
        await page.waitForTimeout(1000);
        const box = await field('ChatInput').boundingBox();
        await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
        await page.waitForTimeout(300);
        check(await field('ChatInput').evaluate(e => document.activeElement === e), 'Map chat activates the native text field by touch');
        await field('ChatInput').evaluate(e => {
            e.dispatchEvent(new CompositionEvent('compositionstart', {bubbles:true, data:''}));
            e.value='zhongwen';
            e.dispatchEvent(new InputEvent('input', {bubbles:true, data:'zhongwen', isComposing:true}));
            e.dispatchEvent(new KeyboardEvent('keydown', {bubbles:true, key:'Enter', keyCode:229, isComposing:true}));
        });
        await page.waitForTimeout(300);
        check(sent.length === 0, 'IME candidate-confirming Enter does not send unfinished pinyin');
        await field('ChatInput').evaluate(e => {
            e.value='中文聊天测试🙂'; e.setSelectionRange(e.value.length,e.value.length);
            e.dispatchEvent(new CompositionEvent('compositionend', {bubbles:true, data:'中文聊天测试🙂'}));
            e.dispatchEvent(new InputEvent('input', {bubbles:true, data:'中文聊天测试🙂'}));
            e.dispatchEvent(new KeyboardEvent('keyup', {bubbles:true, key:'Enter'}));
        });
        await page.waitForTimeout(300);
        check(sent.length === 0 && await field('ChatInput').inputValue() === '中文聊天测试🙂', 'Committed Chinese and emoji remain an editable unsent draft');
        await field('ChatInput').press('Enter');
        for(let i=0;i<50 && (!received.some(d => JSON.stringify(d).includes('中文聊天测试🙂')) || await field('ChatInput').inputValue());i++) await page.waitForTimeout(100);
        check(sent.length === 1 && sent[0].text === '中文聊天测试🙂', 'Send transmits the complete Chinese and emoji message exactly once');
        check(received.some(d => JSON.stringify(d).includes('中文聊天测试🙂')) && await field('ChatInput').inputValue() === '', 'Real server confirms the message and clears both browser/Godot drafts');
        check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'No credentials or drafts saved to key/value storage');
        check(errors.length === 0, 'No browser or Godot script runtime errors');
        await page.screenshot({path: path.join(output, 'chat-confirmed.png')});
        fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({checks, failures:0,
            scope:'Touch-emulated Chromium, real official WASM and disposable Rust/Postgres; synthetic composition events, no physical phone IME'}, null, 2));
        console.log(`WEB TEXT INPUT: ${checks} checks, 0 failures`);
    } catch(error) {
        await page.screenshot({path: path.join(output, 'failure.png')}).catch(()=>{});
        console.error(error.message);
        process.exitCode=1;
    } finally {await browser.close();}
})();
