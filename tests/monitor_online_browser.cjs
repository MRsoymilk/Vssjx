// Real Chromium: chart, range selection, history gaps, error/stale handling and mobile layout.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright-core');
const [base,output]=process.argv.slice(2);
(async()=>{
    const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    let checks=0;const check=value=>{assert.ok(value);checks++;};
    try {
        const page=await browser.newPage({viewport:{width:1280,height:1100}}),errors=[];
        page.on('pageerror',e=>errors.push(e.message));
        await page.goto(base);
        await page.waitForFunction(()=>document.getElementById('daily-online-rows').children.length===30);
        check((await page.locator('#daily-online-status').innerText()).includes('今日累计 2 人'));
        check(await page.locator('#daily-online-chart svg path.daily-line').count()===1);
        check(await page.locator('#daily-online-chart circle').count()===5);
        check((await page.locator('#daily-online-rows').textContent()).includes('未采集'));
        await page.locator('#daily-online-range').selectOption('7');
        await page.waitForFunction(()=>document.getElementById('daily-online-rows').children.length===7);
        check((await page.locator('#daily-online-chart path').getAttribute('d')).includes('L'));
        await page.locator('#daily-online-range').selectOption('90');
        await page.waitForFunction(()=>document.getElementById('daily-online-rows').children.length===90);
        await page.locator('#daily-online-range').selectOption('7');
        await page.waitForFunction(()=>document.getElementById('daily-online-rows').children.length===7);
        await page.locator('.daily-online-panel summary').click();
        check(await page.locator('#daily-online-rows').isVisible());
        await page.screenshot({path:`${output}/online-desktop.png`,fullPage:true});
        await page.setViewportSize({width:390,height:844});
        check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        await page.screenshot({path:`${output}/online-mobile.png`,fullPage:true});
        const before=await page.locator('#daily-online-chart').innerHTML();
        await page.route('**/api/online/daily?*',r=>r.abort());
        await page.locator('#refresh').click();
        await page.waitForFunction(()=>document.getElementById('daily-online-status').textContent.includes('获取失败'));
        check(await page.locator('#daily-online-chart').innerHTML()===before);
        check((await page.locator('#daily-online-status').innerText()).includes('保留上次数据'));
        await page.unroute('**/api/online/daily?*');
        await page.locator('#refresh').click();
        await page.waitForFunction(()=>document.getElementById('daily-online-status').textContent.includes('今日累计 2 人'));
        check(errors.length===0);
        fs.writeFileSync(`${output}/browser.json`,JSON.stringify({checks,failures:0,browser:browser.version(),screenshots:2},null,2));
        console.log(`ONLINE BROWSER: ${checks} checks, 0 failures; 2 real Chromium screenshots`);
    } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
