// Production game export, no test autoloads, state mutation, or injected game API.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base, output] = process.argv.slice(2);
const logs = [], errors = [];
let context, page, checks = 0;
const check = (value, description) => { assert.ok(value, description); checks++; console.log('PASS: ' + description); };
async function launch() {
    context = await chromium.launchPersistentContext(path.join(output, 'browser-profile'), {
        headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
        viewport: {width: 800, height: 850}, hasTouch: true, args: ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'],
    });
    page = await context.newPage();
    page.on('console', message => { logs.push(message.text()); if (/SCRIPT ERROR|Parse Error|^ERROR:/.test(message.text())) errors.push(message.text()); });
    page.on('pageerror', error => errors.push(error.message));
}
async function shot(name) { await page.screenshot({path: path.join(output, name + '.png')}); }
async function click(x, y) {
    const bounds = await page.locator('#canvas').boundingBox();
    await page.mouse.click(bounds.x + x / 320 * bounds.width, bounds.y + y / 480 * bounds.height);
    await page.waitForTimeout(350);
}
async function boot() {
    await page.goto(base);
    await page.locator('#start').click();
    await page.waitForFunction(() => document.getElementById('loading').style.display === 'none', null, {timeout: 90000});
    await page.waitForTimeout(1500);
}
async function saved() {
    return page.evaluate(async () => {
        if (!(await indexedDB.databases()).some(db => db.name === 'vssjx-offline-v1')) return null;
        return new Promise((resolve, reject) => {
            const open = indexedDB.open('vssjx-offline-v1');
            open.onerror = () => reject(new Error('Cannot read owned test slot'));
            open.onsuccess = () => {
                const db = open.result, tx = db.transaction('saves'), request = tx.objectStore('saves').get('save-v1');
                let result;
                request.onsuccess = () => { result = request.result; };
                tx.oncomplete = () => { db.close(); resolve(result ? JSON.parse(result) : null); };
                tx.onabort = () => { db.close(); reject(new Error('Read aborted')); };
            };
        });
    });
}
async function waitSaved(predicate, timeout = 15000) {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
        const value = await saved();
        if (predicate(value)) return value;
        await page.waitForTimeout(250);
    }
    throw new Error('Expected save state not reached; actual: ' + JSON.stringify(await saved()));
}
async function enterLocal() {
    await click(235, 414); // original cover -> Web offline/online choice
    await click(160, 256); // centered dialog, offline button
    await page.waitForTimeout(700);
}

(async () => {
    try {
        await launch();
        await boot();
        check(logs.some(line => /4\.7\.2.*official/.test(line)), 'Real official Godot WASM started');
        check(await saved() === null, 'Fresh browser has no offline character');
        await shot('01-cover');
        await enterLocal();
        await shot('02-empty-local-selection');
        await click(26, 466); // selection menu
        await click(54, 370); // create local character
        await page.waitForTimeout(500);
        await shot('02-creation');
        await click(160, 278);
        // Real key events; CDP insertText is not a desktop/mobile IME test.
        await page.keyboard.type('WebHero', {delay: 100});
        await page.waitForTimeout(500);
        await click(20, 467);
        const initial = await waitSaved(value => value?.name === 'WebHero');
        check(initial.version === 1 && initial.gold === 30, 'UI creates and commits unchanged v1 offline character');
        await shot('03-first-entry');
        await click(160, 464); // created character -> explicit Enter
        await page.waitForTimeout(700);
        await page.keyboard.press('e');
        await page.waitForTimeout(1200);
        await shot('04-quest-dialog');
        await click(100, 319);
        check((await waitSaved(value => value?.quest === 1)).name === initial.name, 'NPC quest accepted through real UI and committed');
        await page.keyboard.down('d');
        await page.waitForTimeout(500);
        await page.keyboard.up('d');
        const moved = await waitSaved(value => value?.cell[0] !== initial.cell[0]);
        check(moved.cell[0] > initial.cell[0], 'Keyboard locomotion changes saved map position');
        await shot('05-world-moved');
        await click(160 + (18 - moved.cell[0]) * 16, 215.5 + (10 - moved.cell[1]) * 16);
        await page.waitForTimeout(4500);
        await shot('06-battle-ready');
        await page.keyboard.press('0');
        const won = await waitSaved(value => value?.kills === 1, 60000);
        check(won.gold === 42 && won.xp === 16 && won.defeated.includes('wolf_a'), 'Real resource preparation, battle and one-time reward commit');
        await shot('07-victory');
        await click(160, 325);
        // Reload runs the unchanged production main scene and restores via Game.
        await boot();
        check(JSON.stringify(await saved()) === JSON.stringify(won), 'Page reload preserves the committed v1 slot');
        await enterLocal();
        await shot('08-reloaded-character');
        await click(160, 464); // character selection Enter
        await page.waitForTimeout(700);
        await page.keyboard.down('s');
        await page.waitForTimeout(450);
        await page.keyboard.up('s');
        const resumed = await waitSaved(value => value?.cell[1] !== won.cell[1]);
        check(resumed.name === won.name && resumed.kills === 1 && resumed.gold === won.gold, 'Actual loaded Game resumes movement without losing or replaying rewards');
        await page.setViewportSize({width: 390, height: 844});
        await page.waitForTimeout(400);
        const bounds = await page.locator('#canvas').boundingBox();
        check(Math.abs(bounds.width / bounds.height - 2 / 3) < 0.01 && bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= 391 && bounds.y + bounds.height <= 844, 'Portrait mobile-size viewport fits the complete game without cropping');
        await shot('09-mobile-sized-world');
        await page.touchscreen.tap(bounds.x + bounds.width / 2, bounds.y + bounds.height * 0.56);
        const touched = await waitSaved(value => JSON.stringify(value?.cell) !== JSON.stringify(resumed.cell));
        check(touched.kills === 1, 'Browser-emulated touch navigates the actual game');
        await page.setViewportSize({width: 844, height: 390});
        await page.waitForTimeout(400);
        const landscape = await page.locator('#canvas').boundingBox();
        check(Math.abs(landscape.width / landscape.height - 2 / 3) < 0.01 && landscape.y + landscape.height <= 390, 'Landscape-sized viewport retains portrait game and footer');
        await shot('10-landscape-sized');
        await context.close();
        context = null;
        await launch();
        await boot();
        const restarted = await saved();
        check(restarted.name === 'WebHero' && restarted.kills === 1 && restarted.gold === won.gold, 'Actual browser process restart retains character and rewards');
        await enterLocal();
        await click(160, 464);
        await page.waitForTimeout(1000);
        await shot('11-process-restarted-world');
        check((await page.evaluate(() => Object.keys(localStorage))).length === 0 && (await page.evaluate(() => Object.keys(sessionStorage))).length === 0, 'No credentials or address preferences in browser key/value storage');
        check(errors.length === 0, 'No runtime script or browser errors');
        fs.writeFileSync(path.join(output, 'browser-report.json'), JSON.stringify({checks, failures: 0, browser: context.browser().version(), scope: 'Real main-game Chromium UI, not mobile or public TLS acceptance'}, null, 2));
        console.log(`WEB GAME BROWSER: ${checks} checks, 0 failures`);
    } catch (error) {
        if (page) await shot('failure').catch(() => {});
        console.error(error);
        process.exitCode = 1;
    } finally {
        fs.writeFileSync(path.join(output, 'console.log'), logs.join('\n'));
        if (context) await context.close();
    }
})();
