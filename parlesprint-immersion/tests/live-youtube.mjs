import { chromium, expect } from '@playwright/test';
import path from 'node:path';
import fs from 'node:fs/promises';
const ext=path.resolve('.output/chrome-mv3');
const videoId=process.env.PARLESPRINT_YOUTUBE_VIDEO_ID||'qkBf1pshW8E';
const screenshot=`artifacts/live-youtube-${videoId}.png`;
const ctx=await chromium.launchPersistentContext('',{channel:'chromium',headless:true,args:[`--disable-extensions-except=${ext}`,`--load-extension=${ext}`],viewport:{width:1280,height:800}});
try{
 const page=await ctx.newPage();await page.goto(`https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`,{waitUntil:'domcontentloaded',timeout:30000});
 await page.getByRole('complementary',{name:'ParleSprint Immersion'}).waitFor({timeout:15000});
 await page.locator('video').waitFor({timeout:20000});
 const state=await page.locator('body').first().innerText();
 const video=await page.locator('video').evaluateAll(v=>v.map(x=>({ready:x.readyState,duration:Number.isFinite(x.duration)?x.duration:null,tracks:Array.from(x.textTracks).map(t=>({language:t.language,cues:t.cues?.length??0}))})));
 await expect.poll(()=>page.locator('video').evaluate(v=>v.readyState)).toBeGreaterThan(0);
 await expect.poll(async()=>{
   const box=await page.getByRole('complementary',{name:'ParleSprint Immersion'}).boundingBox();
   return !!box&&box.width>0&&box.height>0&&box.y>=0&&box.y<800;
 }).toBe(true);
 const panel=page.getByRole('complementary',{name:'ParleSprint Immersion'});
 const normalVideoBox=await page.locator('video').boundingBox();
 const theater=page.getByRole('button',{name:/Theater mode/});
 await expect(theater).toBeVisible();
 await theater.click();
 const theaterVideoBox=await page.locator('video').boundingBox();
 expect(theaterVideoBox.width).toBeGreaterThan(normalVideoBox.width+100);
 expect(await page.evaluate(()=>{
   const host=document.querySelector('parlesprint-immersion');
   const below=document.querySelector('ytd-watch-flexy #below');
   return !!host&&!!below&&host.parentElement===below.parentElement&&host.nextElementSibling===below;
 })).toBe(true);
 await expect.poll(async()=>{
   const [box,videoBox]=await Promise.all([panel.boundingBox(),page.locator('video').boundingBox()]);
   return !!box&&!!videoBox&&box.y>=videoBox.y+videoBox.height-1;
 }).toBe(true);
 await page.locator('.ytp-size-button').click();
 await expect.poll(async()=>{
   const [box,videoBox]=await Promise.all([panel.boundingBox(),page.locator('video').boundingBox()]);
   return !!box&&!!videoBox&&box.y>=videoBox.y+videoBox.height-1;
 }).toBe(true);
 console.log('youtube companion',JSON.stringify(await page.evaluate(()=>{
   const host=document.querySelector('parlesprint-immersion');
   const panel=host?.shadowRoot?.querySelector('aside');
   const box=(el)=>el?{x:el.getBoundingClientRect().x,y:el.getBoundingClientRect().y,width:el.getBoundingClientRect().width,height:el.getBoundingClientRect().height,display:getComputedStyle(el).display,visibility:getComputedStyle(el).visibility}:null;
   return {host:box(host),panel:box(panel),text:panel?.innerText?.slice(0,180)};
 })));
 await page.waitForTimeout(500);
 await panel.scrollIntoViewIfNeeded();
 await panel.screenshot({path:`artifacts/live-youtube-panel-${videoId}.png`});
 await page.screenshot({animations:'disabled',path:screenshot});
 await page.getByText('Optional subtitle alternatives',{exact:true}).click();
 await expect(page.getByRole('button',{name:'Check for French page captions'})).toBeEnabled();
 console.log(JSON.stringify({title:await page.title(),video,playerBlocked:/Sign in to confirm|not a bot|Video unavailable/.test(state),extensionVisible:true}));
 // The default companion must remain in normal flow below the video.
 const [panelRect,videoRect]=await Promise.all([panel.boundingBox(),page.locator('video').boundingBox()]);
 expect(panelRect.y).toBeGreaterThanOrEqual(videoRect.y+videoRect.height-1);
 await expect(page.locator('parlesprint-immersion')).toHaveCSS('position','relative');
 await expect(page.locator('parlesprint-immersion')).toHaveCSS('z-index','2147483647');
 const panelBox=await page.getByRole('complementary',{name:'ParleSprint Immersion'}).boundingBox();
 expect(panelBox.x).toBeGreaterThanOrEqual(0);
 expect(panelBox.x+panelBox.width).toBeLessThanOrEqual(1280);
 await panel.getByLabel('Import French subtitles').setInputFiles('public/demo-fr.srt');
 await page.locator('video').evaluate(v=>{v.pause();v.currentTime=6;});
 await expect(panel.locator('.sentence')).toContainText('Je voudrais');
 await panel.getByRole('button',{name:'↻ Repeat',exact:true}).click();
 await expect.poll(()=>page.locator('video').evaluate(v=>v.currentTime)).toBeLessThan(6);
 await page.locator('video').evaluate(v=>v.pause());
 const playheadCues='1\n00:00:10,000 --> 00:00:12,000\nDix secondes.\n\n2\n00:00:15,000 --> 00:00:18,000\nQuinze secondes.';
 const duration=await page.locator('video').evaluate(v=>v.duration);
 expect(duration).toBeGreaterThan(18);
 await panel.getByLabel('Import French subtitles').setInputFiles({name:'playhead-edges.srt',mimeType:'text/plain',buffer:Buffer.from(playheadCues)});
 for(const [time,text] of [[10,'Dix secondes.'],[15,'Quinze secondes.']]){
   await page.locator('video').evaluate((v,t)=>{v.pause();v.currentTime=t;},time);
   await expect.poll(()=>page.locator('video').evaluate(v=>v.currentTime)).toBeGreaterThanOrEqual(time-0.1);
   await expect(panel.locator('.sentence')).toContainText(text);
 }
 await page.locator('#movie_player').evaluate(el=>el.classList.add('ad-showing'));
 await expect(panel.locator('.sentence')).toHaveCount(0);
 await page.locator('#movie_player').evaluate(el=>el.classList.remove('ad-showing'));
 await expect(panel.locator('.sentence')).toContainText('Quinze secondes.');
 await page.bringToFront();
 await expect.poll(()=>page.evaluate(()=>document.hasFocus())).toBe(true);
 await page.locator('video').evaluate(v=>v.requestFullscreen());
 await expect(panel).toBeHidden();
 await page.evaluate(()=>document.exitFullscreen());
 await expect(panel).toBeVisible();
 console.log('PASS: the companion stays below the live YouTube player; imported timing cues synchronize/replay and fullscreen behavior works. The imported sample is a test fixture, not this video’s transcript.');
 await fs.writeFile(`artifacts/live-youtube-result-${videoId}.json`,JSON.stringify({videoId,title:await page.title(),video,playerBlocked:/Sign in to confirm|not a bot|Video unavailable/.test(state),extensionVisible:true,screenshot},null,2));
}catch(e){console.error(e.message);process.exitCode=1;}finally{await ctx.close();}
