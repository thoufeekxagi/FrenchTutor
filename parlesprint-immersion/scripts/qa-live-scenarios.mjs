import { chromium, expect } from "@playwright/test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const extension = path.join(root, ".output-qa/chrome-mv3");
const videoIds = (process.env.PARLESPRINT_VIDEOS || "D4dpRjd_rYo,aMx0d42wzBs,UsW1bR2oWj4").split(",");
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "parlesprint-scn-"));
const context = await chromium.launchPersistentContext(profile, {
  channel: "chromium",
  headless: false,
  args: [
    `--disable-extensions-except=${extension}`,
    `--load-extension=${extension}`,
    "--autoplay-policy=no-user-gesture-required",
    "--allowlisted-extension-id=ijclgmkoljddlalgcnpodeemcmcipolb",
  ],
  viewport: { width: 1440, height: 900 },
});
const results = [];
const note = (video, step, ok, detail = "") => {
  results.push({ video, step, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${video} ${step} ${detail}`);
};

try {
  const worker = context.serviceWorkers()[0] ?? await context.waitForEvent("serviceworker");
  const extensionId = new URL(worker.url()).host;
  const videoPage = await context.newPage();
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${extensionId}/popup.html`);
  const consent = popup.locator("label").filter({ hasText: "Send this tab’s audio to Google" }).getByRole("checkbox");
  if (!(await consent.isChecked())) await consent.click();
  const captured = () => worker.evaluate(async () => (await chrome.tabCapture.getCapturedTabs()).length);
  const sentence = () => videoPage.getByRole("complementary", { name: "ParleSprint Immersion" }).locator(".sentence").innerText().catch(() => "");
  const real = (t) => t.trim().length > 5 && !/^Listening/.test(t);
  const waitText = async (previous, timeout = 40000) => {
    const end = Date.now() + timeout;
    while (Date.now() < end) {
      const t = await sentence();
      if (real(t) && t !== previous) return t;
      await videoPage.waitForTimeout(700);
    }
    return "";
  };
  const start = async () => {
    await videoPage.bringToFront();
    await popup.getByRole("button", { name: "Start live captions on this tab" }).evaluate((b) => b.click());
  };
  const stop = () => popup.getByRole("button", { name: "Stop live captions" }).evaluate((b) => b.click());
  const video = videoPage.locator("video");

  for (const id of videoIds) {
    await videoPage.goto(`https://www.youtube.com/watch?v=${id}`, { waitUntil: "domcontentloaded", timeout: 45000 });
    await video.waitFor({ timeout: 25000 });
    await expect.poll(() => video.evaluate((v) => v.readyState), { timeout: 25000 }).toBeGreaterThan(0);
    await video.evaluate(async (v) => { v.muted = false; v.volume = 1; await v.play(); });
    // Skip any pre-roll ad before the test begins.
    for (let i = 0; i < 40 && await videoPage.locator(".ad-showing").count(); i++) {
      const skip = videoPage.locator(".ytp-skip-ad-button, .ytp-ad-skip-button-modern");
      if (await skip.count()) await skip.first().click().catch(() => {});
      await videoPage.waitForTimeout(1000);
    }
    await start();
    let text = await waitText("");
    note(id, "first transcript", !!text, text.slice(0, 70));
    if (!text) { await stop().catch(() => {}); continue; }
    note(id, "tab capture active", (await captured()) === 1);

    await video.evaluate((v) => v.pause());
    await videoPage.waitForTimeout(6000);
    const frozen = await sentence();
    await videoPage.waitForTimeout(4000);
    note(id, "pause holds text", (await sentence()) === frozen);
    await video.evaluate((v) => v.play());
    const afterResume = await waitText(frozen);
    note(id, "resume gives new text", !!afterResume, afterResume.slice(0, 70));

    const t0 = await video.evaluate((v) => v.currentTime);
    const dur = await video.evaluate((v) => v.duration);
    console.log("pre-seek", t0, "duration", dur, "ad", await videoPage.locator(".ad-showing").count());
    await video.evaluate((v, d) => { v.currentTime = Math.min(v.currentTime + 90, d - 20); }, dur);
    console.log("post-seek", await video.evaluate((v) => v.currentTime), "ad", await videoPage.locator(".ad-showing").count(), videoPage.url());
    const afterSeek = await waitText(afterResume);
    const t1 = await video.evaluate((v) => v.currentTime);
    note(id, "seek forward", !!afterSeek && t1 > t0 + 60, `${t0.toFixed(0)}s->${t1.toFixed(0)}s ${afterSeek.slice(0, 60)}`);

    await video.evaluate((v) => { v.currentTime = Math.max(0, v.currentTime - 60); });
    const afterBack = await waitText(afterSeek);
    note(id, "seek back", !!afterBack, afterBack.slice(0, 60));

    await video.evaluate((v) => { v.muted = true; });
    await videoPage.waitForTimeout(3000);
    await video.evaluate((v) => { v.muted = false; });
    const afterUnmute = await waitText(afterBack);
    note(id, "mute/unmute recovers", !!afterUnmute, afterUnmute.slice(0, 60));

    await videoPage.keyboard.press("t");
    await videoPage.waitForTimeout(1500);
    const afterTheater = await waitText(afterUnmute);
    note(id, "theater mode keeps captions", !!afterTheater);
    await videoPage.keyboard.press("t");

    await stop();
    await videoPage.waitForTimeout(2000);
    note(id, "stop releases capture", (await captured()) === 0);

    await start();
    const restarted = await waitText("");
    note(id, "restart works", !!restarted, restarted.slice(0, 60));
    await stop();
    await videoPage.waitForTimeout(1500);
  }
} finally {
  await context.close();
  await fs.rm(profile, { recursive: true, force: true });
  const failed = results.filter((r) => !r.ok);
  console.log(JSON.stringify({ total: results.length, failed: failed.length }));
}
