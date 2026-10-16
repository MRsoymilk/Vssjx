// Exercise the real deployed WASM login UI without creating accounts or using player credentials.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base, output] = process.argv.slice(2);
assert(base && output);
fs.mkdirSync(output, {recursive: true});

(async () => {
    const browser = await chromium.launch({headless: true,
        executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
        args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader']});
    const page = await browser.newPage({viewport: {width: 800, height: 850}});
    const errors = [];
    let checks = 0;
    const check = (ok, label) => {assert.ok(ok, label); checks++; console.log('PASS: ' + label);};
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text());});
    async function click(x, y) {
        const bounds = await page.locator('#canvas').boundingBox();
        await page.mouse.click(bounds.x + x / 320 * bounds.width, bounds.y + y / 480 * bounds.height);
        await page.waitForTimeout(400);
    }
    try {
        await page.goto(base);
        await page.locator('#start').click();
        await page.waitForFunction(() => document.getElementById('loading').style.display === 'none', null, {timeout: 90000});
        await page.waitForTimeout(1500);
        check(await page.evaluate(() => window.isSecureContext), 'Deployed page is a browser secure context');
        await click(235, 414);
        // Cover login now opens the account page directly, without a mode dialog.
        await page.screenshot({path: path.join(output, 'online-login.png')});
        await click(160, 192);
        await page.keyboard.type('deploy_probe_' + Date.now().toString(36), {delay: 80});
        await click(160, 240);
        await page.keyboard.type('nonexistent-account-probe-password', {delay: 80});
        const reply = page.waitForResponse(response => response.url() === base + '/api/v1/auth/login', {timeout: 15000});
        await click(160, 317);
        check((await reply).status() === 401, 'Real Godot login reaches the deployed same-origin API and receives an auth rejection');
        await page.waitForTimeout(700); // Let the engine consume the HTTP completion.
        await page.screenshot({path: path.join(output, 'auth-response.png')});
        const upgraded = await page.evaluate(() => new Promise(resolve => {
            const socket = new WebSocket(location.origin.replace('http', 'ws') + '/api/v1/world/ws');
            const timer = setTimeout(() => {socket.close(); resolve(false);}, 8000);
            socket.onopen = () => {clearTimeout(timer); socket.close(); resolve(true);};
            socket.onerror = () => {clearTimeout(timer); resolve(false);};
        }));
        check(upgraded, 'Real browser WebSocket reaches the same-origin game service');
        check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'Probe leaves no credentials in browser key/value storage');
        check(errors.length === 0, 'No browser or Godot runtime script errors');
        fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({checks, failures: 0, browser: browser.version(),
            scope: 'Deployed Godot Web entry in Windows Chromium, not mobile, authenticated play or capacity acceptance'}, null, 2));
        console.log(`WEB DEPLOY BROWSER: ${checks} checks, 0 failures`);
    } catch (error) {
        await page.screenshot({path: path.join(output, 'failure.png')}).catch(() => {});
        console.error(error.message);
        process.exitCode = 1;
    } finally {
        await browser.close();
    }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
