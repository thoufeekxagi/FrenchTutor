import { chromium, expect } from "@playwright/test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const extension = path.join(root, ".output/chrome-mv3");
const videoId = process.env.PARLESPRINT_LIVE_VIDEO_ID || "qkBf1pshW8E";
const screenshot = `artifacts/live-transcription-youtube-${videoId}.png`;
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "parlesprint-live-"));
const context = await chromium.launchPersistentContext(profile, {
  channel: "chromium",
  headless: process.env.PARLESPRINT_HEADLESS === "1",
  args: [
    `--disable-extensions-except=${extension}`,
    `--load-extension=${extension}`,
    "--autoplay-policy=no-user-gesture-required",
  ],
  viewport: { width: 1440, height: 900 },
});

try {
  const worker = context.serviceWorkers()[0] ?? await context.waitForEvent("serviceworker");
  const videoPage = await context.newPage();
  await videoPage.goto(`https://www.youtube.com/watch?v=${encodeURIComponent(videoId)}`, {
    waitUntil: "domcontentloaded",
    timeout: 45000,
  });
  const video = videoPage.locator("video");
  await video.waitFor({ timeout: 25000 });
  await expect.poll(() => video.evaluate((element) => element.readyState), { timeout: 25000 }).toBeGreaterThan(0);
  await video.evaluate(async (element) => {
    element.muted = false;
    element.volume = 1;
    await element.play();
  });
  await expect.poll(() => video.evaluate((element) => element.currentTime), { timeout: 10000 }).toBeGreaterThan(0.5);

  const popup = await context.newPage();
  const extensionId = new URL(worker.url()).host;
  await popup.goto(`chrome-extension://${extensionId}/popup.html`);
  const consent = popup.locator("label").filter({ hasText: "I agree to send this tab’s audio directly to Google" }).getByRole("checkbox");
  if (!(await consent.isChecked())) {
    await consent.click();
    await expect(consent).toBeChecked({ timeout: 5000 });
  }
  await worker.evaluate(() => chrome.action.openPopup());
  await videoPage.bringToFront();
  const activeTabs = await worker.evaluate(async () => {
    const [current] = await chrome.tabs.query({ active: true, currentWindow: true });
    const [lastFocused] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    const safe = (tab) => tab?.url ? `${new URL(tab.url).host}${new URL(tab.url).pathname}` : "";
    return { currentWindow: safe(current), lastFocusedWindow: safe(lastFocused) };
  });
  const activeUrl = activeTabs.lastFocusedWindow;
  if (!activeUrl.startsWith("www.youtube.com/watch")) {
    throw new Error(`The French video is not the active tab (${JSON.stringify(activeTabs)}). No capture request was sent.`);
  }

  await popup.getByRole("button", { name: "Start live captions on this tab" }).evaluate((button) => button.click());
  const panel = videoPage.getByRole("complementary", { name: "ParleSprint Immersion" });
  await expect(panel).toBeVisible({ timeout: 15000 });
  await expect.poll(async () => {
    const [panelBox, videoBox] = await Promise.all([panel.boundingBox(), video.boundingBox()]);
    return !!panelBox && !!videoBox && panelBox.y >= videoBox.y + videoBox.height - 1;
  }, { timeout: 10000 }).toBe(true);
  await expect.poll(async () => {
    const text = await panel.locator(".sentence").innerText().catch(() => "");
    return text.trim().length > 5 && text !== "Listening…";
  }, { timeout: 35000, intervals: [500, 1000, 2000] }).toBe(true);

  const transcript = await panel.locator(".sentence").innerText();
  const playback = await video.evaluate((element) => ({ paused: element.paused, muted: element.muted, time: element.currentTime }));
  await videoPage.screenshot({ path: path.join(root, screenshot), fullPage: false });
  await popup.getByRole("button", { name: "Stop live captions" }).evaluate((button) => button.click());
  console.log(JSON.stringify({ result: "PASS", videoId, video: await videoPage.title(), transcript, playback, screenshot }));
} finally {
  await context.close();
  await fs.rm(profile, { recursive: true, force: true });
}
