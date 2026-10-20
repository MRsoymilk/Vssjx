// Use a disposable local forum for login checks; public mode is guest-only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const args = process.argv.slice(2);
const openRegistration = args.includes('--registration=open');
const [base, output, credentials] = args.filter(value => value !== '--registration=open');
const local = new URL(base).hostname === '127.0.0.1';
assert(!credentials || local, 'Never import production credentials into browser fixtures');
let browser, count = 0;
function check(value, title) {assert(value, title); count++; console.log('PASS: ' + title);}
(async () => {
  try {
    fs.mkdirSync(output, {recursive: true});
    browser = await chromium.launch({headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    const context = await browser.newContext({viewport: {width: 1440, height: 1000}});
    const page = await context.newPage();
    const errors = [], failed = [], requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => {if (response.status() >= 400) failed.push(response.status() + ' ' + new URL(response.url()).pathname);});
    page.on('request', request => requests.push(request.url()));
    if (!local) {
      await page.goto(new URL(base).origin + '/', {waitUntil: 'networkidle'});
      check(await page.locator('a[href="/flarum/"]').count() === 3, 'Portal forum navigation and card links are enabled');
      check(requests.every(url => !/^\/(?:flarum|webgame|api)(?:\/|$)/.test(new URL(url).pathname)), 'Portal does not preload forum, game or API');
      await page.screenshot({path: path.join(output, 'portal-forum-enabled.png'), fullPage: true});
      await page.locator('a[href="/flarum/"]').first().click();
      await page.waitForURL(base + '/');
      check(page.url() === base + '/', 'Portal link enters the deployed forum');
    }
    const response = await page.goto(base + '/', {waitUntil: 'networkidle'});
    await page.waitForFunction(() => window.flarum?.core?.app?.booted || document.querySelector('.IndexPage'));
    check(response.status() === 200, 'Forum homepage responds over the intended prefix');
    check((await page.title()).includes('剑侠茶馆'), 'Chinese forum title is present');
    check(await page.locator('.Header-secondary').getByText('登录', {exact: true}).count() > 0, 'Chinese JavaScript UI has loaded');
    const register = page.locator('.Header-secondary').getByText('注册', {exact: true});
    check((await register.count() > 0) === openRegistration, 'Registration matches the expected state');
    if (openRegistration) {
      await register.click();
      await page.waitForSelector('.SignUpModal input[name=email]');
      check(await page.locator('.SignUpModal input[name=username], .SignUpModal input[name=email], .SignUpModal input[name=password]').count() === 3, 'Registration form opens with username, email and password; no account is submitted');
      await page.screenshot({path: path.join(output, 'forum-registration.png'), fullPage: true});
      await page.locator('.Modal-close').click();
    }
    check(await page.locator('link[rel=stylesheet]').count() > 0, 'Styles are loaded');
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Desktop layout fits viewport');
    const cookies = await context.cookies();
    check(cookies.some(cookie => cookie.name === 'flarum_session' && cookie.path === '/flarum' && cookie.secure && cookie.httpOnly), 'Session cookie is secure, HTTP-only and scoped to forum');
    await page.screenshot({path: path.join(output, 'forum-desktop.png'), fullPage: true});
    await page.setViewportSize({width: 390, height: 844});
    check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Mobile layout fits viewport');
    await page.screenshot({path: path.join(output, 'forum-mobile.png'), fullPage: true});
    await page.setViewportSize({width: 1440, height: 1000});
    if (credentials) {
      const admin = JSON.parse(fs.readFileSync(credentials, 'utf8'));
      await page.locator('.Header-secondary').getByText('登录', {exact: true}).click();
      await page.locator('.LogInModal input[name=identification]').fill(admin.username);
      await page.locator('.LogInModal input[name=password]').fill(admin.password);
      await page.locator('.LogInModal button[type=submit]').click();
      await page.waitForFunction(() => !document.querySelector('.LogInModal') && document.querySelector('.Header-secondary .SessionDropdown'));
      check(true, 'Disposable local administrator can log in');
      await page.goto(base + '/admin', {waitUntil: 'networkidle'});
      await page.waitForSelector('.AdminPage, .DashboardPage, .App-content');
      check((await page.title()).includes('剑侠茶馆'), 'Local administrator dashboard is accessible');
    }
    check(failed.length === 0, 'No failing forum assets or API requests: ' + failed.join('; '));
    check(errors.length === 0, 'No uncaught JavaScript errors: ' + errors.join('; '));
    check(requests.every(url => new URL(url).origin === new URL(base).origin), 'Initial forum UI makes no third-party requests');
    fs.writeFileSync(path.join(output, 'requests.json'), JSON.stringify(requests.map(url => new URL(url).pathname), null, 2));
    console.log(`FLARUM BROWSER: ${count} checks passed`);
  } catch (error) {console.error(error); process.exitCode = 1;}
  finally {if (browser) await browser.close();}
})();
