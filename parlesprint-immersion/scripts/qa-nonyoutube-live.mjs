import { chromium, expect } from "@playwright/test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const extension = path.join(root, ".output-qa/chrome-mv3");
const url = process.env.PARLESPRINT_LIVE_URL;
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "ps-nyt-"));
const context = await chromium.launchPersistentContext(profile, {
  channel: "chromium", headless: false,
  args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`, "--autoplay-policy=no-user-gesture-required", "--allowlisted-extension-id=ijclgmkoljddlalgcnpodeemcmcipolb"],
  viewport: { width: 1280, height: 800 },
});
try {
  const worker = context.serviceWorkers()[0] ?? await context.waitForEvent("serviceworker");
  const page = await context.newPage();
  await page.goto(url, { waitUntil: "domcontentloaded" });
  const media = page.locator("video, audio").first();
  await media.waitFor({ state: "attached", timeout: 20000 });
  await media.evaluate(async (m) => { m.muted = false; m.volume = 1; await m.play(); });
  await expect.poll(() => media.evaluate((m) => m.currentTime), { timeout: 10000 }).toBeGreaterThan(0.5);
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${new URL(worker.url()).host}/popup.html`);
  await popup.getByText("Video has no captions?").click();
  const gateNote = await popup.locator(".gate-hint, [role=status]").allInnerTexts();
  console.log("gate note:", JSON.stringify(gateNote));
  const consent = popup.locator("label").filter({ hasText: "Send this tab’s audio to Google" }).getByRole("checkbox");
  if (!(await consent.isChecked())) await consent.click();
  await page.bringToFront();
  await popup.getByRole("button", { name: "Start live captions on this tab" }).evaluate((b) => b.click());
  await page.waitForTimeout(25000);
  const stats = await worker.evaluate(async () => (await chrome.storage.local.get("qaLive")).qaLive);
  console.log("NOTES:", JSON.stringify(stats?.notes?.slice(0, 5)));
  console.log("STATS sent/skipped/interim/final:", stats?.sent, stats?.skipped, stats?.interim, stats?.final);
  const text = await page.evaluate(() => document.querySelector("parlesprint-immersion")?.shadowRoot?.querySelector(".sentence")?.textContent ?? "");
  console.log("on-page text:", JSON.stringify(text.slice(0, 120)));
  console.log("RESULT:", stats && stats.interim + stats.final > 0 && text.length > 5 ? "PASS" : "FAIL");
} finally {
  await context.close();
  await fs.rm(profile, { recursive: true, force: true });
}
