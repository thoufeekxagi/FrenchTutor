import { chromium } from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
import os from "node:os";
const ext = path.resolve(process.env.PARLESPRINT_BUILD || ".output/chrome-mv3");
const id = process.env.PARLESPRINT_VIDEO || "UsW1bR2oWj4";
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "ps-ui-"));
const ctx = await chromium.launchPersistentContext(profile, { channel: "chromium", headless: false, args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`, "--autoplay-policy=no-user-gesture-required"], viewport: { width: 1440, height: 900 } });
let failed = 0;
const ok = (name, pass, d = "") => { if (!pass) failed++; console.log(`${pass ? "PASS" : "FAIL"} ${name} ${d}`); };
try {
  const page = await ctx.newPage();
  await page.goto(`https://www.youtube.com/watch?v=${id}`, { waitUntil: "domcontentloaded" });
  const v = page.locator("video"); await v.waitFor();
  await v.evaluate(async (x) => { x.muted = true; await x.play().catch(() => {}); });
  for (let i = 0; i < 40 && await page.locator(".ad-showing").count(); i++) { const s = page.locator(".ytp-skip-ad-button, .ytp-ad-skip-button-modern"); if (await s.count()) await s.first().click().catch(() => {}); await page.waitForTimeout(1000); }
  if (process.env.PARLESPRINT_SEEK) { await page.waitForTimeout(3000); await v.evaluate((x, t) => { x.currentTime = t; }, Number(process.env.PARLESPRINT_SEEK)); }
  const bar = page.getByRole("complementary", { name: "ParleSprint Immersion" });
  await bar.locator(".sentence").waitFor({ timeout: 25000 });
  const inside = async () => { const [b, p] = await Promise.all([bar.locator(".ov-line").boundingBox(), page.locator("#movie_player").boundingBox()]); const vp = page.viewportSize(); return b && p && b.y >= p.y + p.height - 1 && b.y + b.height <= vp.height; };
  ok("caption bar sits under the player, visible without scrolling", await inside());
  await page.screenshot({ path: "/tmp/psshots/1-caption.png" });
  await v.evaluate((x) => x.pause());
  const before = await v.evaluate((x) => x.paused);
  await bar.locator(".word").first().click();
  await bar.locator(".ov-meaning .meaning-main").waitFor({ timeout: 8000 });
  const word = await bar.locator(".ov-meaning strong").innerText();
  const meaning = await bar.locator(".ov-meaning .meaning-main").innerText();
  ok("click word gives meaning with no account", !!meaning, `${word} -> ${meaning}`);
  ok("word is highlighted", (await bar.locator(".word.selected").count()) > 0);
  const afterPaused = await v.evaluate((x) => x.paused);
  ok("video not toggled by clicking caption", afterPaused === before, `before=${before} after=${afterPaused}`);
  await page.screenshot({ path: "/tmp/psshots/2-meaning.png" });
  await bar.getByRole("button", { name: "Close meaning" }).click();
  await bar.getByRole("button", { name: "EN", exact: true }).click();
  await bar.locator(".ov-tx").waitFor({ timeout: 8000 });
  ok("EN toggle shows line translation", true, await bar.locator(".ov-tx").innerText());
  await page.screenshot({ path: "/tmp/psshots/3-translation.png" });
  await bar.getByRole("button", { name: "FR", exact: true }).click();
  await page.waitForTimeout(300);
  ok("FR toggle hides captions", (await bar.locator(".sentence").count()) === 0);
  await bar.getByRole("button", { name: "FR", exact: true }).click();
  await v.evaluate((x) => x.play());
  await page.keyboard.press("t"); await page.waitForTimeout(1500);
  ok("theater mode keeps bar under player in view", await inside());
  await page.screenshot({ path: "/tmp/psshots/4-theater.png" });
  await page.keyboard.press("t");
  
} finally { await ctx.close(); await fs.rm(profile, { recursive: true, force: true }); console.log(JSON.stringify({ failed })); }
