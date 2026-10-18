import { chromium } from "@playwright/test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const extension = path.join(root, process.env.PARLESPRINT_BUILD || ".output/chrome-mv3");
const videoIds = (process.env.PARLESPRINT_VIDEOS || "D4dpRjd_rYo,aMx0d42wzBs,UsW1bR2oWj4").split(",");
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "parlesprint-cap-"));
const context = await chromium.launchPersistentContext(profile, {
  channel: "chromium",
  headless: false,
  args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`, "--autoplay-policy=no-user-gesture-required"],
  viewport: { width: 1440, height: 900 },
});
let failed = 0;
const note = (id, step, ok, detail = "") => {
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"} ${id} ${step} ${detail}`);
};
try {
  const page = await context.newPage();
  const sentence = () => page.getByRole("complementary", { name: "ParleSprint Immersion" }).locator(".sentence").innerText({ timeout: 500 }).catch(() => "");
  const waitFor = async (pred, ms) => {
    const end = Date.now() + ms;
    while (Date.now() < end) { const t = await sentence(); if (pred(t)) return t; await page.waitForTimeout(150); }
    return "";
  };
  const skipAds = async () => {
    for (let i = 0; i < 45 && await page.locator(".ad-showing").count(); i++) {
      const skip = page.locator(".ytp-skip-ad-button, .ytp-ad-skip-button-modern");
      if (await skip.count()) await skip.first().click().catch(() => {});
      await page.waitForTimeout(1000);
    }
  };
  const video = page.locator("video");
  for (const id of videoIds) {
    await page.goto(`https://www.youtube.com/watch?v=${id}`, { waitUntil: "domcontentloaded", timeout: 45000 });
    await video.waitFor({ timeout: 25000 });
    await video.evaluate(async (v) => { v.muted = true; await v.play().catch(() => {}); });
    await skipAds();
    const t = await waitFor((x) => x.trim().length > 3, 20000);
    note(id, "captions appear by themselves", !!t, JSON.stringify(t.slice(0, 80)));
    if (!t) continue;
    const time = await video.evaluate((v) => v.currentTime);
    // Line must be visible within a second of the playhead moving.
    await video.evaluate((v) => v.pause());
    const held = await sentence();
    await page.waitForTimeout(2500);
    note(id, "pause holds the line", (await sentence()) === held && !!held);
    await video.evaluate((v) => v.play());
    const dur = await video.evaluate((v) => v.duration);
    for (const target of [Math.min(time + 70, dur - 30), Math.max(2, time - 5), Math.min(dur * 0.5, dur - 30)]) {
      const before = await sentence();
      await video.evaluate((v, x) => { v.currentTime = x; }, target);
      const t0 = Date.now();
      const after = await waitFor((x) => x.trim().length > 3 && x !== before, 4000);
      note(id, `seek to ${target.toFixed(0)}s`, !!after, `${Date.now() - t0}ms ${JSON.stringify(after.slice(0, 60))}`);
    }
    await video.evaluate((v) => { v.playbackRate = 1.5; });
    const fast = await waitFor((x) => x.trim().length > 3, 3000);
    note(id, "1.5x speed", !!fast);
    await video.evaluate((v) => { v.playbackRate = 1; });
    await page.keyboard.press("t");
    await page.waitForTimeout(1200);
    note(id, "theater mode", !!(await waitFor((x) => x.trim().length > 3, 3000)));
    await page.keyboard.press("t");
    const [panel, vbox] = await Promise.all([page.getByRole("complementary", { name: "ParleSprint Immersion" }).boundingBox(), video.boundingBox()]);
    note(id, "panel below player (no overlap)", !!panel && !!vbox && panel.y >= vbox.y + vbox.height - 1);
  }
} finally {
  await context.close();
  await fs.rm(profile, { recursive: true, force: true });
  console.log(JSON.stringify({ failed }));
}
