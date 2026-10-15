// Optional real Chromium checks; install playwright-core outside the repository.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {chromium} = require(process.env.PLAYWRIGHT_MODULE_PATH || "playwright-core");
const [base, output] = process.argv.slice(2);
(async () => {
    const browser = await chromium.launch({headless:true, executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
    let checks = 0;
    const check = value => { assert.ok(value); checks++; };
    try {
        const page = await browser.newPage({viewport:{width:1280,height:1100}});
        const errors = [];
        page.on("pageerror", error=>errors.push(error.message));
        page.on("console", message=>{if(message.type()==="error") errors.push(message.text());});
        await page.goto(base);
        await page.waitForFunction(()=>document.getElementById("health").textContent === "运行中");
        check((await page.locator("#cards .card").count()) === 4);
        check((await page.locator("#cards").innerText()).includes("2 / 1000"));
        check((await page.locator("#database").innerText()).includes("ok"));
        check((await page.locator("#http").innerText()).includes("/api/v1/auth/login"));
        const before = await page.locator("#notice").innerText();
        await page.waitForTimeout(5200);
        check((await page.locator("#notice").innerText()) !== before);
        check((await page.locator("#trend span").count()) >= 2);
        await page.screenshot({path:`${output}/dashboard-desktop.png`,fullPage:true});
        await page.setViewportSize({width:390,height:844});
        await page.screenshot({path:`${output}/dashboard-mobile.png`,fullPage:true});
        check(await page.evaluate(()=>document.documentElement.scrollWidth <= innerWidth));
        const snapshot = await (await page.request.get(`${base}/api/status`)).json();
        snapshot.boot_id = "browser-restart-fixture";
        snapshot.recent_events.push({time_ms:Date.now(),kind:"fixture",code:'<img src=x onerror="window.injected=true">',correlation_id:"literal-only"});
        await page.route("**/api/status", route=>route.fulfill({json:snapshot}));
        await page.locator("#refresh").click();
        await page.waitForFunction(()=>document.getElementById("events").textContent.includes("literal-only"));
        check((await page.locator("#events img").count()) === 0);
        check(await page.evaluate(()=>!window.injected));
        check((await page.locator("#trend span").count()) === 1);
        await page.unroute("**/api/status");
        await page.route("**/api/status", route=>route.abort());
        const priorErrors = errors.length;
        await page.locator("#refresh").click();
        await page.waitForFunction(()=>document.getElementById("health").textContent === "连接中断");
        check((await page.locator("#notice").innerText()).includes("旧数据"));
        check((await page.locator("#cards .card").count()) === 4);
        await page.screenshot({path:`${output}/dashboard-disconnected.png`,fullPage:true});
        // A deliberately aborted fetch emits a network console error; earlier errors are not allowed.
        check(priorErrors === 0);
        fs.writeFileSync(`${output}/browser.json`,JSON.stringify({checks,failures:0,browser:browser.version(),screenshots:3},null,2));
        console.log(`BROWSER: ${checks} checks, 0 failures; 3 real headless Chromium screenshots`);
    } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exit(1);});
