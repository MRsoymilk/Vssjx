// Isolated real-browser preview. Serves only three prepared navigation files.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [folder, output] = process.argv.slice(2);
assert(folder && output, 'Usage: node tests/portal_browser.cjs <prepared-directory> <screenshot-directory>');
const routes = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/navigation.html', ['index.html', 'text/html; charset=utf-8']],
  ['/navigation/portal.css', ['portal.css', 'text/css; charset=utf-8']],
  ['/navigation/app-icon.webp', ['app-icon.webp', 'image/webp']],
]);
const requests = [], errors = [];
let browser, checks = 0;
const check = (condition, message) => {assert.ok(condition, message); checks++; console.log('PASS: ' + message);};
const server = http.createServer((request, response) => {
  requests.push(request.url);
  const entry = routes.get(request.url);
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Content-Security-Policy', "default-src 'none'; img-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  if (!entry) {response.writeHead(404); response.end(); return;}
  response.setHeader('Content-Type', entry[1]);
  response.end(fs.readFileSync(path.join(folder, entry[0])));
});

(async () => {
  try {
    fs.mkdirSync(output, {recursive: true});
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const base = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    const context = await browser.newContext();
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {if (message.type() === 'error') errors.push(message.text());});
    for (const [name, width, height] of [['desktop', 1440, 1000], ['mobile', 390, 844], ['small-mobile', 320, 740], ['landscape', 844, 390]]) {
      await page.setViewportSize({width, height});
      await page.goto(base, {waitUntil: 'networkidle'});
      check(await page.title() === '蜀山剑侠 · 归来 — 江湖驿站', name + ': correct title');
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), name + ': no horizontal overflow');
      check(await page.getByRole('button', {name: '论坛筹备中'}).isDisabled(), name + ': forum stays disabled');
      check(await page.getByRole('link', {name: '进入游戏'}).getAttribute('href') === '/webgame/', name + ': explicit new game entry');
      check(await page.getByRole('link', {name: '下载 APK'}).getAttribute('href') === '/downloads/vssjx-arm64.apk', name + ': existing download retained');
      check(await page.locator('.hero-icon').evaluate(image => image.complete && image.naturalWidth === 256), name + ': reused icon decoded');
      await page.screenshot({path: path.join(output, name + '.png'), fullPage: true});
    }
    await page.goto(base + '/navigation.html', {waitUntil: 'networkidle'});
    await page.keyboard.press('Tab');
    check(await page.locator('.skip-link').evaluate(link => link === document.activeElement), 'Keyboard skip link receives focus');
    await page.keyboard.press('Enter');
    check(new URL(page.url()).hash === '#main', 'Skip link reaches main content');
    await page.emulateMedia({reducedMotion: 'reduce'});
    check(await page.locator('.button-primary').evaluate(button => getComputedStyle(button).transitionDuration === '0s'), 'Reduced-motion preference respected');
    check(requests.every(url => routes.has(url)), 'Navigation never requests API, engine, forum or third-party resources');
    check(errors.length === 0, 'No browser or CSP errors: ' + errors.join('; '));
    fs.writeFileSync(path.join(output, 'requests.json'), JSON.stringify(requests, null, 2));
    console.log(`PORTAL BROWSER: ${checks} checks, 0 failures`);
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})();
