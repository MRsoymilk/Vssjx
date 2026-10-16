// Real production WASM UI; the public cover now leads directly to account login.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base, output] = process.argv.slice(2);
const logs = [], errors = [];
let checks = 0, context, page;
const check = (value, description) => {assert.ok(value, description); checks++; console.log('PASS: ' + description);};
async function click(x, y, touch = false) {
    const bounds = await page.locator('#canvas').boundingBox();
    const point = [bounds.x + x / 320 * bounds.width, bounds.y + y / 480 * bounds.height];
    if (touch) await page.touchscreen.tap(...point);
    else await page.mouse.click(...point);
    await page.waitForTimeout(400);
}
async function shot(name) {await page.screenshot({path: path.join(output, name + '.png')});}
async function boot() {
    await page.goto(base);
    await page.locator('#start').click();
    await page.waitForFunction(() => document.getElementById('loading').style.display === 'none', null, {timeout: 90000});
    await page.waitForTimeout(1200);
}
(async () => {
    try {
        context = await chromium.launchPersistentContext(path.join(output, 'browser-profile'), {
            headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
            viewport: {width: 800, height: 850}, hasTouch: true,
            args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
        });
        page = await context.newPage();
        page.on('console', message => {logs.push(message.text()); if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text());});
        page.on('pageerror', error => errors.push(error.message));
        await boot();
        check(logs.some(line => /4\.7\.2.*official/.test(line)), 'Real official Godot WASM starts');
        await shot('01-cover');
        await click(235, 414); // Exactly one cover activation; no mode-selection click.
        await shot('02-direct-login');
        await click(160, 192);
        await page.keyboard.type('web_entry_probe', {delay: 80});
        await click(160, 240);
        await page.keyboard.type('frontend-entry-probe-password', {delay: 80});
        const reply = page.waitForResponse(response => response.url() === base + '/api/v1/auth/login', {timeout: 15000});
        await click(160, 317);
        check((await reply).status() === 503, 'One cover click opens usable account login and receives the explicit fixture rejection');
        await page.waitForTimeout(700);
        await shot('03-login-response');
        await click(45, 460);
        await shot('04-return-to-cover');
        await page.setViewportSize({width: 390, height: 844});
        await page.waitForTimeout(300);
        const portrait = await page.locator('#canvas').boundingBox();
        check(Math.abs(portrait.width / portrait.height - 2 / 3) < 0.01 && portrait.x >= 0 && portrait.y >= 0 && portrait.x + portrait.width <= 391 && portrait.y + portrait.height <= 844, 'Mobile-sized portrait keeps the complete game in view');
        await click(235, 414, true);
        await shot('05-touch-login');
        await page.setViewportSize({width: 844, height: 390});
        await page.waitForTimeout(300);
        const landscape = await page.locator('#canvas').boundingBox();
        check(Math.abs(landscape.width / landscape.height - 2 / 3) < 0.01 && landscape.y + landscape.height <= 390, 'Landscape size preserves the portrait login and footer');
        await shot('06-landscape-login');
        check(await page.evaluate(() => localStorage.length === 0 && sessionStorage.length === 0), 'Navigation stores no credentials or address preferences');
        await boot();
        await click(235, 414);
        await shot('07-reloaded-direct-login');
        check(errors.length === 0, 'No Godot script or browser runtime errors through return, touch and reload');
        fs.writeFileSync(path.join(output, 'browser-report.json'), JSON.stringify({checks, failures: 0, browser: context.browser().version(),
            scope: 'Production WASM direct-login UI with a rejecting HTTP fixture; not authenticated gameplay or mobile hardware acceptance'}, null, 2));
        console.log(`WEB GAME BROWSER: ${checks} checks, 0 failures`);
    } catch (error) {
        if (page) await shot('failure').catch(() => {});
        console.error(error.message);
        process.exitCode = 1;
    } finally {
        fs.writeFileSync(path.join(output, 'console.log'), logs.join('\n'));
        if (context) await context.close();
    }
})();
