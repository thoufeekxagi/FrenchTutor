import { chromium } from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
import os from "node:os";
const ext = path.resolve(".output/chrome-mv3");
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "ps-final-"));
const ctx = await chromium.launchPersistentContext(profile, { channel: "chromium", headless: false, args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`, "--autoplay-policy=no-user-gesture-required"], viewport: { width: 1440, height: 900 } });
let failed = 0;
const ok = (name, pass, d = "") => { if (!pass) failed++; console.log(`${pass ? "PASS" : "FAIL"} ${name} ${d}`); };
try {
  const worker = ctx.serviceWorkers()[0] ?? await ctx.waitForEvent("serviceworker");
  const page = await ctx.newPage();
  await page.goto("https://www.youtube.com/watch?v=EaNqp4FXh-s", { waitUntil: "domcontentloaded" });
  const v = page.locator("video"); await v.waitFor();
  await v.evaluate(async (x) => { x.muted = true; x.currentTime = 62; await x.play().catch(() => {}); });
  const bar = page.getByRole("complementary", { name: "ParleSprint Immersion" });
  for (let i = 0; i < 40 && !(await bar.locator(".sentence").count()); i++) { await v.evaluate((x) => { x.currentTime = 62; }).catch(() => {}); await page.waitForTimeout(1000); }
  await bar.locator(".sentence").waitFor({ timeout: 5000 });
  const where = await page.evaluate(() => document.querySelector("parlesprint-immersion")?.parentElement?.id);
  ok("default placement is the suggested-videos column", where === "secondary-inner", where);
  const vis = await bar.boundingBox();
  ok("bar visible without scrolling", !!vis && vis.y >= 0 && vis.y + vis.height <= 900, JSON.stringify(vis));
  await page.screenshot({ path: "/tmp/psshots/f1-side-tour.png" });
  const tour = bar.getByRole("dialog", { name: "Quick tour" });
  ok("first-run tour shows", await tour.isVisible());
  for (let i = 0; i < 5; i++) { const next = tour.getByRole("button", { name: /Next|Done/ }); if (!(await next.count())) break; await next.click(); await page.waitForTimeout(150); }
  ok("tour finishes and stays gone", (await tour.count()) === 0);
  await bar.locator(".word").first().click();
  await bar.locator(".ov-meaning .meaning-main").waitFor({ timeout: 10000 });
  ok("word meaning", true, await bar.locator(".ov-meaning .meaning-main").innerText());
  await bar.getByRole("button", { name: "Explain in context" }).click();
  await bar.locator(".ov-explain").waitFor({ timeout: 30000 });
  const ex = await bar.locator(".ov-explain").innerText();
  ok("Explain in context works with no login", ex.length > 40 && !/account|sign/i.test(ex), ex.slice(0, 90).replace(/\n/g, " "));
  await page.screenshot({ path: "/tmp/psshots/f2-explain.png" });
  // floating
  await worker.evaluate(() => chrome.storage.local.set({ prefs: { placement: "floating", tourDone: true } }));
  await page.waitForTimeout(1500);
  const panel = page.getByRole("complementary", { name: "ParleSprint Immersion" });
  const en = panel.getByRole("button", { name: /English: (on|off)/ });
  ok("floating panel has an English toggle", await en.isVisible());
  if (await en.isVisible()) {
    await v.evaluate(async (x) => { x.currentTime = 66; await x.play().catch(() => {}); });
    await en.click();
    await panel.locator(".sentence-translation").first().waitFor({ timeout: 10000 }).catch(() => {});
    ok("floating panel shows live English", (await panel.locator(".sentence-translation").count()) > 0, await panel.locator(".sentence-translation").first().innerText().catch(() => ""));
  }
  await page.screenshot({ path: "/tmp/psshots/f3-floating.png" });
} finally { await ctx.close(); await fs.rm(profile, { recursive: true, force: true }); console.log(JSON.stringify({ failed })); }
