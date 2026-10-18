import { chromium } from '@playwright/test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const extension=path.join(root,'.output/chrome-mv3');
const profile=process.env.PARLESPRINT_BROWSER_PROFILE??'.local-browser-live';
const videoId=process.env.PARLESPRINT_YOUTUBE_VIDEO_ID??'UwqQbIDVSgE';
const context=await chromium.launchPersistentContext(path.join(root,profile),{channel:'chromium',headless:false,args:[`--disable-extensions-except=${extension}`,`--load-extension=${extension}`],viewport:null});
const worker=context.serviceWorkers()[0]??await context.waitForEvent('serviceworker',{timeout:15000});
const id=new URL(worker.url()).host;
const video=await context.newPage();await video.goto(`https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`,{waitUntil:'domcontentloaded',timeout:45000});
await video.getByRole('complementary',{name:'ParleSprint Immersion'}).waitFor({timeout:20000});
await video.bringToFront();
console.log(`ParleSprint Immersion is running (${id}) in a dedicated Chrome for Testing window. YouTube video ${videoId} is open.\n\nTest live captions: (1) press Play and confirm you hear the video; (2) click the puzzle-piece Extensions button and open ParleSprint Immersion; (3) review and accept the audio notice; (4) choose “Start live captions on this tab”; (5) confirm “Listening for French” appears, then wait for spoken French to appear in the on-page caption panel. Reopen the popup and press Stop. The launcher will print the first caption and save a screenshot.\n\nThis uses the audio from the current tab only; it does not need subtitle files or a microphone. Close this test browser to stop.`);
let lastCaption='';
let lastHeading='';
let lastStatusText='';
const watcher=setInterval(()=>{void(async()=>{
  try{
    const state=await video.evaluate(()=>{
      const root=document.querySelector('parlesprint-immersion')?.shadowRoot;
      return {
        heading:root?.querySelector('.setup-card h3')?.textContent?.trim()??'',
        status:root?.querySelector('[role="status"]')?.textContent?.trim()??'',
        caption:root?.querySelector('.caption-card .sentence')?.textContent?.trim()??''
      };
    });
    if(state.heading!==lastHeading&&state.heading==='Listening for French.'){
      lastHeading=state.heading;
      console.log('Live status: Listening for French.');
    }
    if(state.caption&&state.caption.length>5&&state.caption!==lastCaption){
      lastCaption=state.caption;
      await video.getByRole('complementary',{name:'ParleSprint Immersion'}).screenshot({path:path.join(root,'artifacts/live-transcription-youtube.png')});
      console.log(`Live French caption: ${state.caption}`);
      console.log('Caption screenshot saved to artifacts/live-transcription-youtube.png');
    }
    if(state.status&&state.status!==lastStatusText){
      lastStatusText=state.status;
      console.log(`Live status: ${state.status}`);
    }
  }catch{}
})();},1000);
context.on('close',()=>{clearInterval(watcher);process.exit(0);});
