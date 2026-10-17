// Real browser against the owned integration fixture's private monitor.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base, output] = process.argv.slice(2);
(async()=>{
    const browser=await chromium.launch({headless:true, executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    let checks=0;
    const check=v=>{assert.ok(v);checks++;};
    try {
        const page=await browser.newPage({viewport:{width:1280,height:1000}});
        const errors=[];page.on('pageerror',e=>errors.push(e.message));
        await page.goto(base);
        await page.waitForFunction(()=>document.getElementById('users-list').children.length>0);
        check(await page.locator('#users-title').isVisible());
        await page.locator('#users-q').fill('audit_first');
        await page.locator('#users-search button[type=submit]').click();
        await page.waitForFunction(()=>document.getElementById('users-list').children.length===1);
        await page.locator('#users-list button').click();
        await page.waitForFunction(()=>!document.getElementById('user-detail').hidden);
        check((await page.locator('#user-name').innerText()).includes('audit_first'));
        check((await page.locator('#user-characters').innerText()).includes('铜钱'));
        await page.waitForFunction(()=>document.getElementById('audit-list').children.length===100);
        const character=await page.locator('#audit-character option').nth(1).getAttribute('value');
        await page.locator('#audit-character').selectOption(character);
        await page.waitForFunction(()=>document.getElementById('audit-list').textContent.includes('pve.equip') && !document.getElementById('audit-list').textContent.includes('fixture.event'));
        check((await page.locator('#audit-list').textContent()).includes(character));
        await page.locator('#audit-character').selectOption('');
        await page.waitForFunction(()=>document.getElementById('audit-list').children.length===100);
        await page.locator('#audit-more').click();
        await page.waitForFunction(()=>document.getElementById('audit-list').children.length>100);
        check((await page.locator('#audit-list').innerText()).includes('pve.equip'));
        await page.locator('#audit-outcome').selectOption('rejected');
        await page.waitForFunction(()=>document.getElementById('audit-list').textContent.includes('PVE_ID_CONFLICT') && !document.getElementById('audit-list').textContent.includes('fixture.event'));
        check(!(await page.locator('#audit-list').innerText()).includes('fixture.event'));
        await page.locator('#user-action-kind').selectOption('disable');
        await page.locator('#user-reason').fill('浏览器回归验证');
        const sent=[];
        page.on('request',r=>{if(r.method()==='POST' && r.url().endsWith('/actions')) sent.push(r.postDataJSON());});
        // Simulate the response being lost AFTER the server commits the ban.
        await page.route('**/api/users/*/actions',async route=>{const response=await route.fetch();check(response.ok());await route.abort();},{times:1});
        page.once('dialog',d=>d.accept());
        await page.locator('#user-execute').click();
        await page.waitForFunction(()=>document.getElementById('user-action-status').textContent.includes('结果未确认') && !document.getElementById('user-execute').disabled);
        page.once('dialog',d=>d.accept());
        await page.locator('#user-execute').click();
        await page.waitForFunction(()=>document.getElementById('user-name').textContent.includes('已封禁') && !document.getElementById('user-execute').disabled);
        check((await page.locator('#user-action-status').innerText()).includes('已执行'));
        check(sent.length===2 && sent[0].operation_id===sent[1].operation_id);
        await page.locator('#audit-outcome').selectOption('accepted');
        await page.waitForFunction(()=>document.getElementById('audit-list').textContent.includes('operator.disable'));
        await page.locator('#audit-list details').first().locator('summary').click();
        await page.screenshot({path:`${output}/users-desktop.png`,fullPage:true});
        await page.setViewportSize({width:390,height:844});
        await page.screenshot({path:`${output}/users-mobile.png`,fullPage:true});
        check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        // Only route interception supplies HTML-looking values; production usernames are canonical.
        const fixture=await (await page.request.get(base+'/api/users?q=audit_first')).json();
        fixture.users[0].username='<img src=x onerror="window.injected=true">';
        await page.route('**/api/users?*',r=>r.fulfill({json:fixture}));
        await page.locator('#users-refresh').click();
        await page.waitForFunction(()=>document.getElementById('users-list').textContent.includes('<img'));
        check(await page.locator('#users-list img').count()===0);
        check(await page.evaluate(()=>!window.injected));
        check(errors.length===0);
        fs.writeFileSync(`${output}/browser.json`,JSON.stringify({checks,failures:0,browser:browser.version(),screenshots:2},null,2));
        console.log(`SECURITY BROWSER: ${checks} checks, 0 failures`);
    } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exit(1);});
