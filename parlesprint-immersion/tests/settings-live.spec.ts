import { test, expect, chromium } from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
test("settings apply live, popup says Saved, re-injection replaces the stale panel", async () => {
  const ext = path.resolve(".output/chrome-mv3");
  const ctx = await chromium.launchPersistentContext("", { channel: "chromium", headless: true, args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`], viewport: { width: 1280, height: 800 } });
  const w = ctx.serviceWorkers()[0] ?? (await ctx.waitForEvent("serviceworker"));
  const id = new URL(w.url()).host;
  await w.evaluate(() => (globalThis as any).chrome.storage.local.clear());
  const data = await fs.readFile("tests/fixtures/timing.webm");
  const page = await ctx.newPage();
  await page.route("https://www.youtube.com/timing.webm", (r) => r.fulfill({ status: 200, contentType: "video/webm", body: data }));
  await page.route("https://www.youtube.com/watch?*", (r) => r.fulfill({ contentType: "text/html", body: '<!doctype html><meta charset="UTF-8"><body><div id="columns"><main id="primary-inner"><div id="player-container-outer"><div id="movie_player" class="html5-video-player"><video controls src="/timing.webm" style="width:640px"></video></div></div><div id="below">below</div></main><aside id="secondary"><div id="secondary-inner"><div>Suggested</div></div></aside></div></body>' }));
  await page.goto("https://www.youtube.com/watch?v=live");
  const host = page.locator("parlesprint-immersion");
  await expect(host).toHaveCount(1);
  const parent = () => page.evaluate(() => document.querySelector("parlesprint-immersion")?.parentElement?.id);
  expect(await parent()).toBe("secondary-inner");
  const popup = await ctx.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await expect(popup.getByRole("status")).toContainText("Saved automatically");
  await popup.getByLabel("Caption placement").selectOption("below");
  await expect(popup.getByRole("status")).toContainText("Saved ✓");
  await expect.poll(parent).not.toBe("secondary-inner");
  await popup.getByLabel("Caption placement").selectOption("side");
  await expect.poll(parent).toBe("secondary-inner");
  // simulate the extension-update path: inject the content script again
  await w.evaluate(async () => {
    const c = (globalThis as any).chrome;
    const [tab] = await c.tabs.query({ url: "https://www.youtube.com/watch*" });
    await c.scripting.executeScript({ target: { tabId: tab.id }, files: ["content-scripts/content.js"] });
  });
  await page.waitForTimeout(800);
  await expect(host).toHaveCount(1);
  await ctx.close();
});
