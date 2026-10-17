// Deterministic browser checks for slow, stalled and failed engine startup.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const output = process.argv[2];
assert(output);
fs.mkdirSync(output, {recursive: true});
const shell = fs.readFileSync(path.join(__dirname, '../client/web/shell.html'), 'utf8')
    .replaceAll('$GODOT_PROJECT_NAME', 'Loader fixture').replaceAll('$GODOT_HEAD_INCLUDE', '')
    .replaceAll('$GODOT_URL', '/engine.js').replaceAll('$GODOT_CONFIG', '{}');
const fakeEngine = `window.fixture = {calls:0}; window.Engine = class {
    static getMissingFeatures() {return [];}
    startGame(options) {fixture.calls++; fixture.progress = options.onProgress;
        return new Promise((resolve,reject) => {fixture.resolve = resolve; fixture.reject = reject;});}
};`;
const server = http.createServer((req,res) => {
    res.setHeader('Content-Type', req.url === '/engine.js' ? 'application/javascript' : 'text/html');
    res.end(req.url === '/engine.js' ? fakeEngine : shell);
});

(async () => {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const browser = await chromium.launch({headless:true,
        executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    let checks = 0;
    const check = (value,label) => {assert.ok(value,label); checks++; console.log('PASS: '+label);};
    try {
        const page = await browser.newPage({viewport:{width:390,height:844}});
        await page.clock.install();
        const url = 'http://127.0.0.1:'+server.address().port;
        await page.goto(url);
        await page.locator('#start').click();
        check(await page.locator('#start').isDisabled(), 'Only one engine initialization owns the loading state');
        check(await page.locator('#progress').getAttribute('value') === null, 'Unknown totals use an animated indeterminate bar');
        await page.evaluate(() => fixture.progress(1048576,5242880));
        check((await page.locator('#details').innerText()).includes('1.0 MB / 5.0 MB'), 'Loaded and total bytes are visible on mobile');
        await page.clock.fastForward(21000);
        check((await page.locator('#notice').innerText()).includes('网络较慢'), 'Stalled transfers explain why progress stopped');
        check(await page.locator('#start').isEnabled(), 'A stalled load exposes a manual reload action');
        await page.screenshot({path:path.join(output,'stalled.png')});
        await page.evaluate(() => fixture.progress(2097152,5242880));
        check(await page.locator('#start').isDisabled() && !(await page.locator('#notice').innerText()).includes('网络较慢'), 'New bytes recover without starting another engine');
        await page.evaluate(() => fixture.progress(5242880,5242880));
        check((await page.locator('#notice').innerText()).includes('正在启动'), 'Completed downloads distinguish initialization from network transfer');
        await page.evaluate(() => fixture.resolve());
        await page.waitForFunction(() => document.getElementById('loading').style.display === 'none');
        check(await page.locator('#canvas').evaluate(node => node === document.activeElement), 'Successful startup hides the loader and focuses the canvas');
        await page.goto(url);
        await page.locator('#start').click();
        await page.evaluate(() => fixture.reject(new Error('Failed to fetch')));
        await page.waitForFunction(() => document.getElementById('start').disabled === false);
        check((await page.locator('#notice').innerText()).includes('Failed to fetch'), 'Request failure preserves its cause');
        check((await page.locator('#details').innerText()).includes('不会清除本站存档'), 'Reload explains that existing saves are preserved');
        await Promise.all([page.waitForNavigation(),page.locator('#start').click()]);
        check((await page.locator('#start').innerText()) === '开始游戏', 'Retry reloads the page instead of overlapping engine requests');
        console.log(`WEB LOADER: ${checks} checks, 0 failures`);
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {console.error(error);server.close();process.exitCode=1;});
