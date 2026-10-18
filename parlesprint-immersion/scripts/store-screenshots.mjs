import { chromium } from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
import os from "node:os";
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const ext = path.join(root, ".output/chrome-mv3");
const out = path.join(root, "store/screenshots");
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "ps-shots-"));
const ctx = await chromium.launchPersistentContext(profile, { channel: "chromium", headless: false, args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`, "--autoplay-policy=no-user-gesture-required"], viewport: { width: 1280, height: 800 } });
try {
  const page = await ctx.newPage();
  await page.goto("https://www.youtube.com/watch?v=EaNqp4FXh-s&t=61s", { waitUntil: "domcontentloaded" });
  const v = page.locator("video"); await v.waitFor({ timeout: 30000 }); console.log("video ready");
  const panel = page.getByRole("complementary", { name: "ParleSprint Immersion" });
  await v.evaluate((x) => { x.muted = true; x.play().catch(() => {}); }).catch(() => {});
  for (let i = 0; i < 60; i++) {
    const ok = await v.evaluate((x) => x.readyState >= 3 && !x.seeking && !x.paused && x.currentTime > 61.5 && x.currentTime < 67).catch(() => false);
    if (ok && (await panel.locator(".sentence").count())) break;
    await page.waitForTimeout(1000);
  }
  await panel.locator(".sentence").waitFor({ timeout: 8000 }); console.log("caption visible");
  // let the tour pass, then take the clean default view
  const tour = panel.getByRole("dialog", { name: "Quick tour" });
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(out, "1-tour.png") });
  if (await tour.count()) await tour.getByRole("button", { name: "Skip" }).click({ timeout: 8000 });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(out, "2-captions-french-english.png") });
  await v.evaluate((x) => x.pause());
  await panel.locator(".word").nth(2).click({ timeout: 8000 }); console.log("word clicked");
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(out, "3-word-meaning.png") });
  const explain = panel.getByRole("button", { name: "Explain in context" });
  if (await explain.count()) { await explain.click({ timeout: 8000 }); await page.waitForTimeout(6000); }
  await page.evaluate(() => window.scrollBy(0, 300));
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(out, "4-explain.png") });
  console.log("captured; sentence:", (await panel.locator(".sentence").first().innerText()).slice(0, 80));
  // popup at real toolbar size
  const worker = ctx.serviceWorkers()[0] ?? await ctx.waitForEvent("serviceworker");
  const pop = await ctx.newPage();
  await pop.setViewportSize({ width: 400, height: 600 });
  await pop.goto(`chrome-extension://${new URL(worker.url()).host}/popup.html`);
  await pop.waitForTimeout(1200);
  await pop.screenshot({ path: path.join(out, "5-popup-400x600.png") });
} finally { await ctx.close(); await fs.rm(profile, { recursive: true, force: true }); }
