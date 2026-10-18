// Capture the running product using actual controls and an isolated profile.
import { chromium, expect } from '@playwright/test';
import path from 'node:path';
const ext = path.resolve('.output/chrome-mv3');
const context = await chromium.launchPersistentContext('', { channel:'chromium', headless:true,
 args:[`--disable-extensions-except=${ext}`,`--load-extension=${ext}`], viewport:{width:1280,height:800} });
try {
 const page=await context.newPage();
 await page.goto('chrome-extension://ijclgmkoljddlalgcnpodeemcmcipolb/practice.html');
 const panel=page.getByRole('complementary',{name:'ParleSprint Immersion'});
 await expect(panel.locator('.sentence')).toContainText('Bonjour');
 await page.evaluate(()=>document.fonts.ready);
 await page.locator('video').evaluate(video=>{video.preload='auto';video.load();});
 await expect.poll(()=>page.locator('video').evaluate(v=>v.readyState)).toBe(4);
 await panel.getByRole('button',{name:'↻ Repeat',exact:true}).click();
 await expect.poll(()=>page.locator('video').evaluate(v=>v.currentTime)).toBeGreaterThan(0.3);
 await page.locator('video').evaluate(v=>v.pause());
 await panel.getByText('Reveal sentence translation',{exact:true}).click();
 await page.screenshot({animations:"disabled",path:'store/screenshot-first-practice-1280x800.png'});
 await panel.getByRole('button',{name:'Study Bonjour',exact:true}).click();
 await panel.getByRole('button',{name:'Save phrase',exact:true}).click();
 await expect(panel.getByRole('button',{name:'Saved ✓',exact:true})).toBeVisible();
 await panel.getByRole('button',{name:'Select a phrase',exact:true}).click();
 await panel.getByRole('button',{name:'Study mon',exact:true}).click();
 await panel.getByRole('button',{name:'Study voyage',exact:true}).click();
 await expect(panel.getByRole('heading',{name:'mon premier voyage',exact:true})).toBeVisible();
 await panel.getByRole('button',{name:'Save phrase',exact:true}).click();
 await expect(panel.locator('.word[data-saved="true"]')).toHaveCount(4);
 await page.setViewportSize({width:1280,height:1000});
 await page.evaluate(()=>scrollTo(0,0));
 await panel.evaluate(el=>{el.scrollTop=0;});
 await page.screenshot({animations:"disabled",path:'artifacts/highlighting-practice.png'});
 const popup=await context.newPage();await popup.setViewportSize({width:400,height:600});
 await popup.goto('chrome-extension://ijclgmkoljddlalgcnpodeemcmcipolb/popup.html');
 await popup.evaluate(()=>document.fonts.ready);
 await popup.screenshot({animations:"disabled",path:'artifacts/premium-popup-practice.png'});
 await popup.getByRole('tab',{name:'Notebook',exact:true}).click();
 await expect(popup.getByText('mon premier voyage',{exact:true})).toBeVisible();
 await popup.screenshot({animations:"disabled",path:'artifacts/premium-popup-notebook.png'});
 await popup.getByRole('tab',{name:'Account',exact:true}).click();
 await expect(popup.getByLabel('Email',{exact:true})).toBeVisible();
 await popup.screenshot({animations:"disabled",path:'artifacts/premium-popup-account.png'});
 console.log('Captured real practice, popup, saved notebook and account UI. No mock data or account credentials inserted.');
} finally { await context.close(); }
