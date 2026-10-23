"use strict";
const {chromium}=require(process.env.PLAYWRIGHT_MODULE_PATH);
(async()=>{
    const browser=await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,headless:true,args:['--no-sandbox']});
    let checks=0;const check=(ok,text)=>{checks++;if(!ok)throw new Error(text);};
    try{
        const page=await browser.newPage({viewport:{width:1440,height:1000}}),faults=[];
        page.on('pageerror',e=>faults.push(e.message));page.on('dialog',d=>d.accept());
        await page.goto(process.argv[2]+'/maps');await page.waitForSelector('#map-editor:not([hidden])');
        check(await page.locator('nav a[href="/maps"]').count()===1,'shared navigation contains map management');
        check(await page.locator('#map-select option').count()===216,'searchable map catalog');
        await page.fill('#map-search','ai_001');check(await page.locator('#map-select option').count()===1,'map search filters ID');
        await page.selectOption('#map-select','ai_001');await page.waitForFunction(()=>document.querySelector('#map-title').textContent.includes('ai_001'));
        check(await page.locator('#map-residents tr').count()>0,'structured resident editor rendered');
        check(await page.locator('#map-portals fieldset').count()>0,'structured portal editor rendered');
        await page.fill('#map-reason','浏览器专项验证');await page.uncheck('#map-entry');
        await page.route('**/api/maps/ai_001/actions',async route=>{await new Promise(resolve=>setTimeout(resolve,200));await route.continue();});
        await page.click('#map-save');check(await page.locator('#map-entry').isDisabled(),'in-flight operations freeze editing');await page.waitForFunction(()=>document.querySelector('#map-status').textContent.includes('草稿已保存'));
        check((await page.request.get(process.argv[2]+'/api/maps/ai_001').then(r=>r.json())).active.entry_enabled,'save does not publish');
        await page.locator('#map-spawn input').first().fill('-1');await page.click('#map-validate');await page.waitForFunction(()=>document.querySelector('#map-status').textContent.includes('校验未通过'));
        check(await page.locator('#map-errors li').count()>0,'invalid grid coordinate shown without publication');
        await page.locator('#map-spawn input').first().fill('5');
        await page.click('#map-validate');await page.waitForFunction(()=>document.querySelector('#map-status').textContent.includes('校验通过'));
        await page.click('#map-publish');await page.waitForFunction(()=>document.querySelector('#map-status').textContent.includes('已发布'));
        check(!(await page.request.get(process.argv[2]+'/api/maps/ai_001').then(r=>r.json())).active.entry_enabled,'browser publish changes active entry control');
        await page.selectOption('#map-history','0');await page.click('#map-restore');await page.waitForFunction(()=>document.querySelector('#map-status').textContent.includes('恢复为草稿'));
        check(!(await page.request.get(process.argv[2]+'/api/maps/ai_001').then(r=>r.json())).active.entry_enabled,'history restore does not activate silently');
        await page.click('#map-publish');await page.waitForFunction(()=>document.querySelector('#map-status').textContent.includes('已发布'));
        check((await page.request.get(process.argv[2]+'/api/maps/ai_001').then(r=>r.json())).active.entry_enabled,'restored draft explicitly published');
        const image=process.env.SSJX_MAP_CAPTURE;if(image)await page.screenshot({path:image,fullPage:true});
        await page.setViewportSize({width:390,height:844});check(await page.locator('#map-save').isVisible(),'mobile layout retains action controls');
        check(faults.length===0,'no browser script errors: '+faults.join(';'));
        console.log(`MAP MANAGEMENT BROWSER: ${checks} checks, 0 failures`);
    }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
