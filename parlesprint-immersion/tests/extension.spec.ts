import { test, expect, chromium, type BrowserContext } from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
let context: BrowserContext;
const id = "ijclgmkoljddlalgcnpodeemcmcipolb";
test.beforeAll(async () => {
  const extension = path.resolve(".output/chrome-mv3");
  context = await chromium.launchPersistentContext("", {
    channel: "chromium",
    headless: true,
    args: [
      `--disable-extensions-except=${extension}`,
      `--load-extension=${extension}`,
      "--autoplay-policy=no-user-gesture-required",
    ],
    viewport: { width: 1280, height: 800 },
  });
});
test.afterAll(async () => {
  await context?.close();
});
test("real MV3 popup, subtitle timing, replay, notebook, navigation, errors", async () => {
  const worker =
    context.serviceWorkers()[0] ??
    (await context.waitForEvent("serviceworker"));
  expect(worker.url()).toContain(id);
  // This spec exercises the signed-out error path; don't inherit an auth
  // session from any other extension test or an existing Chromium profile.
  await worker.evaluate(async () => {
    await (globalThis as any).chrome.storage.local.clear();
    await (globalThis as any).chrome.storage.local.set({ prefs: { compactView: false } });
  });
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await expect(popup.locator(".brand-word")).toBeVisible();
  await expect(popup.locator(".live-card")).toBeVisible();
  expect(
    await popup
      .locator(".ps.popup")
      .evaluate((el) => el.getBoundingClientRect().width),
  ).toBe(400);
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await expect(
    popup.getByText("Save a word or sentence while you watch."),
  ).toBeVisible();
  const page = await context.newPage();
  const video = await fs.readFile("tests/fixtures/timing.webm");
  await page.route("https://www.youtube.com/test-video.webm", (r) => {
    const m = /bytes=(\d+)-(\d*)/.exec(r.request().headers().range ?? "");
    const start = m ? Number(m[1]) : 0;
    const end = m && m[2] ? Number(m[2]) : video.length - 1;
    return r.fulfill({
      status: m ? 206 : 200,
      contentType: "video/webm",
      headers: {
        "Accept-Ranges": "bytes",
        ...(m
          ? { "Content-Range": `bytes ${start}-${end}/${video.length}` }
          : {}),
      },
      body: video.subarray(start, end + 1),
    });
  });
  await page.route("https://www.youtube.com/watch?*", (r) =>
    r.fulfill({
      contentType: "text/html",
      body: `<!doctype html><html><head><meta charset="UTF-8"><title>ParleSprint integration fixture</title></head><body style="margin:0;background:#f2f3ed;font-family:Arial;color:#273d33"><main style="padding:36px;max-width:840px"><small>PARLESPRINT · INTEGRATION TEST</small><h1>French subtitle practice</h1><p>Local video fixture. Original French subtitles for timing verification.</p><video style="width:760px;max-width:100%" controls src="/test-video.webm"></video><p>Imported subtitles are illustrative and do not represent spoken audio.</p></main></body></html>`,
    }),
  );
  await page.goto("https://www.youtube.com/watch?v=fixture-one");
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.readyState),
    )
    .toBeGreaterThan(0);
  const panel = page.getByRole("complementary", {
    name: "ParleSprint Immersion",
  });
  await expect(panel).toBeVisible();
  await panel
    .getByLabel("Import French subtitles")
    .setInputFiles("public/demo-fr.srt");
  await expect(panel.getByText("Source: demo-fr.srt")).toBeVisible();
  await page.locator("video").evaluate((v: HTMLVideoElement) => {
    v.currentTime = 1;
    v.dispatchEvent(new Event("timeupdate"));
  });
  await expect(panel.locator(".sentence")).toContainText("Bonjour");
  const first = await panel.locator(".sentence").innerText();
  await panel.getByRole("button", { name: "More subtitle settings" }).click();
  await panel
    .getByRole("button", { name: "Study sentence", exact: true })
    .click();
  await panel.getByRole("button", { name: "Save phrase", exact: true }).click();
  await expect(panel.getByRole("button", { name: "Saved ✓" })).toBeVisible();
  await expect(
    popup.getByRole("button", { name: "Remove phrase" }),
  ).toHaveCount(1);
  await page.locator("video").evaluate((v: HTMLVideoElement) => {
    v.currentTime = 6;
    v.dispatchEvent(new Event("timeupdate"));
  });
  await expect(panel.locator(".sentence")).not.toHaveText(first);
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeLessThan(5.5);
  await expect
    .poll(
      () => page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
      { timeout: 9000 },
    )
    .toBe(true);
  await panel.getByText("Reading & playback", { exact: true }).click();
  await panel.getByLabel("Hide French until revealed").check();
  await expect(
    panel.getByRole("button", { name: "Reveal French sentence" }),
  ).toBeVisible();
  await panel.getByRole("button", { name: "Reveal French sentence" }).click();
  await panel.getByText("Source: demo-fr.srt", { exact: true }).click();
  await panel
    .getByRole("button", { name: "Check for French page captions" })
    .click();
  await expect(panel.getByRole("status")).toContainText(
    "Live French captions are still available",
  );
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "invalid.srt",
    mimeType: "text/plain",
    buffer: Buffer.from("not subtitles"),
  });
  await expect(panel.getByRole("alert")).toContainText("Invalid subtitle");
  await panel
    .getByRole("button", { name: "Study sentence", exact: true })
    .click();
  // Word meaning is free and needs no account; AI explanation is opt-in only.
  await expect(panel.getByRole("button", { name: "Explain in context" })).toHaveCount(0);
  await expect(panel.getByRole("button", { name: "Allow explanations" })).toHaveCount(0);
  await page.evaluate(() => {
    history.pushState({}, "", "/watch?v=fixture-two");
  });
  await expect(panel.getByText("Source: demo-fr.srt")).toHaveCount(0);
  await page.evaluate(() => {
    history.pushState({}, "", "/watch?v=fixture-one");
  });
  await expect(panel.getByText("Source: demo-fr.srt")).toBeVisible();
  await popup.getByRole("tab", { name: "Practice", exact: true }).click();
  await popup.getByLabel("Show captions on videos").uncheck();
  await expect(panel).toHaveCount(0);
  await popup.getByLabel("Show captions on videos").check();
  await expect(page.getByRole("complementary")).toBeVisible();
  await page.locator("video").evaluate((v: HTMLVideoElement) => {
    v.pause();
    v.currentTime = 1;
    v.dispatchEvent(new Event("timeupdate"));
  });
  await page.getByText("Reading & playback", { exact: true }).click();
  await page.getByLabel("Hide French until revealed").uncheck();
  await page.screenshot({ path: "artifacts/extension-timing-fixture.png" });
  await popup.screenshot({ path: "artifacts/popup.png" });
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await popup.getByRole("button", { name: "Export vocabulary" }).click();
  await popup.reload();
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await expect(
    popup.getByRole("button", { name: "Remove phrase" }),
  ).toHaveCount(1);
  await popup.getByRole("button", { name: "Remove phrase" }).click();
  await expect(
    popup.getByText("Save a word or sentence while you watch."),
  ).toBeVisible();
  const errors = await worker.evaluate(
    () => (globalThis as any).chrome.runtime.lastError?.message ?? null,
  );
  expect(errors).toBeNull();
});

test("concurrent notebook writes and native French TextTrack fallback", async () => {
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  const results = await popup.evaluate(async () => {
    const api = (globalThis as any).chrome;
    return Promise.all(
      ["one", "two"].map((id) =>
        api.runtime.sendMessage({
          type: "save-word",
          word: {
            id,
            text: "bonjour",
            sentence: "Bonjour tout le monde.",
            level: "A1",
            savedAt: Date.now(),
          },
        }),
      ),
    );
  });
  expect(results.every((r) => !r.error)).toBe(true);
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await expect(
    popup.getByRole("button", { name: "Remove phrase" }),
  ).toHaveCount(2);
  await popup.getByRole("button", { name: "Remove phrase" }).first().click();
  await popup.getByRole("button", { name: "Remove phrase" }).click();
  const page = await context.newPage();
  await page.route("https://www.youtube.com/watch?*", (r) =>
    r.fulfill({
      contentType: "text/html",
      body: '<!doctype html><html><meta charset="UTF-8"><body><h1>Native caption fixture</h1><video controls></video></body></html>',
    }),
  );
  await page.goto("https://www.youtube.com/watch?v=native-fixture");
  await page.locator("video").evaluate((v: HTMLVideoElement) => {
    const t = v.addTextTrack("captions", "French", "fr");
    t.mode = "hidden";
    t.addCue(new VTTCue(0, 5, "Bonjour, les amis !"));
  });
  const panel = page.getByRole("complementary", {
    name: "ParleSprint Immersion",
  });
  await expect(panel).toBeVisible();
  await panel
    .getByText("Optional subtitle alternatives", { exact: true })
    .click();
  await panel.getByRole("button", { name: "More subtitle settings" }).click();
  await panel
    .getByRole("button", { name: "Check for French page captions" })
    .click();
  await expect(panel.getByText("Source: French player captions")).toBeVisible();
  await expect(panel.locator(".sentence")).toContainText("Bonjour, les amis !");
  await popup.getByRole("tab", { name: "Practice", exact: true }).click();
  for (const level of ["A1", "A2", "B1", "B2"]) {
    await panel.getByLabel("Your French").selectOption(level);
    await expect(popup.getByLabel("Your French")).toHaveValue(level);
  }
  await panel.getByText("Timing & transcript").click();
  await expect(panel.getByLabel("Subtitle delay in seconds")).toBeVisible();
  await panel.getByLabel("Subtitle delay in seconds").fill("2");
  await expect(panel.locator(".sentence")).toHaveCount(0);
  await panel.getByLabel("Subtitle delay in seconds").fill("0");
  await expect(panel.locator(".sentence")).toContainText("Bonjour");
  await page.setViewportSize({ width: 640, height: 800 });
  await expect(panel).toBeVisible();
  const box = await panel.boundingBox();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.width).toBeLessThanOrEqual(640);
  await panel.getByRole("button", { name: "Minimize immersion" }).click();
  await expect(
    panel.getByRole("button", { name: "Expand immersion" }),
  ).toBeVisible();
  await panel.getByRole("button", { name: "Expand immersion" }).click();
  await expect(panel.locator(".sentence")).toBeVisible();
  await popup.close();
  await page.close();
});
