import { test, expect, chromium, type BrowserContext, type Page } from "@playwright/test";
declare const chrome: any;
import path from "node:path";
import fs from "node:fs/promises";

let context: BrowserContext;
const id = "ijclgmkoljddlalgcnpodeemcmcipolb";
test.beforeAll(async () => {
  const ext = path.resolve(".output/chrome-mv3");
  context = await chromium.launchPersistentContext("", {
    channel: "chromium",
    headless: true,
    args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
    viewport: { width: 1280, height: 800 },
  });
});
test.afterAll(async () => await context?.close());
test.afterEach(async () => {
  for (const page of context.pages()) await page.close();
});

type Track = { languageCode: string; kind?: string };
async function videoPage(tracks: Track[], title = "A video", description = ""): Promise<Page> {
  const data = await fs.readFile("tests/fixtures/timing.webm");
  const page = await context.newPage();
  await page.route("https://www.youtube.com/timing.webm", (r) => r.fulfill({ status: 200, contentType: "video/webm", body: data }));
  await page.route("https://www.youtube.com/api/timedtext*", (r) => r.fulfill({ contentType: "text/xml", body: '<timedtext><body><p t="0" d="2000">Bonjour tout le monde.</p></body></timedtext>' }));
  await page.route("https://www.youtube.com/youtubei/v1/player*", (r) =>
    r.fulfill({
      contentType: "application/json",
      body: JSON.stringify({
        playabilityStatus: { status: "OK" },
        videoDetails: { title, shortDescription: description, isLiveContent: false },
        captions: { playerCaptionsTracklistRenderer: { captionTracks: tracks.map((t) => ({ ...t, baseUrl: `https://www.youtube.com/api/timedtext?lang=${t.languageCode}` })) } },
      }),
    }),
  );
  await page.route("https://www.youtube.com/watch?*", (r) =>
    r.fulfill({ contentType: "text/html", body: '<!doctype html><meta charset="UTF-8"><title>Fixture</title><body><div id="movie_player" class="html5-video-player"><video controls src="/timing.webm" style="width:480px"></video></div><div id="secondary-inner"></div></body>' }),
  );
  await page.goto("https://www.youtube.com/watch?v=abcdefghijk");
  await expect(page.locator("parlesprint-immersion")).toHaveCount(1);
  return page;
}
async function popupFor(page: Page): Promise<Page> {
  const worker = context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
  const tabId = await worker.evaluate(async () => {
    const [tab] = await (globalThis as any).chrome.tabs.query({ url: "https://www.youtube.com/watch*" });
    return tab.id as number;
  });
  const popup = await context.newPage();
  await popup.addInitScript((tab) => {
    const original = chrome.tabs.query.bind(chrome.tabs);
    chrome.tabs.query = async (q: any) =>
      q?.active ? [{ id: tab, url: "https://www.youtube.com/watch?v=abcdefghijk" }] : original(q);
  }, tabId);
  await popup.goto(`chrome-extension://${id}/popup.html`);
  void page;
  return popup;
}
const startLive = (popup: Page) =>
  popup.evaluate(() => chrome.runtime.sendMessage({ type: "start-live-transcription" }));

test.beforeEach(async () => {
  const worker = context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
  await worker.evaluate(() => (globalThis as any).chrome.storage.local.clear());
  await worker.evaluate(() => (globalThis as any).chrome.storage.local.set({ transcriptionLiveConsent: true }));
});

test("French captions present: live captions are blocked and the popup says why", async () => {
  const page = await videoPage([{ languageCode: "fr", kind: "asr" }]);
  const popup = await popupFor(page);
  await expect(popup.getByText("This video already has captions")).toBeVisible();
  await expect(popup.getByRole("status").filter({ hasText: "already has French captions" })).toBeVisible();
  await expect(popup.getByRole("button", { name: "Start live captions on this tab" })).toHaveCount(0);
  await page.bringToFront();
  const result = await startLive(popup);
  expect(result.error).toContain("already has French captions");
});

test("English speech: live captions are blocked with the detected language", async () => {
  const page = await videoPage([{ languageCode: "en" }, { languageCode: "en", kind: "asr" }], "Me at the zoo");
  const popup = await popupFor(page);
  await expect(popup.getByText("Live captions are off for this video")).toBeVisible();
  await expect(popup.getByRole("status").filter({ hasText: "English speech" })).toBeVisible();
  await page.bringToFront();
  expect((await startLive(popup)).error).toContain("English speech");
});

test("no captions and unclear language: live captions stay available with a hint", async () => {
  const page = await videoPage([], "Vlog", "");
  const popup = await popupFor(page);
  await popup.getByText("Video has no captions?").click();
  await expect(popup.getByText("could not confirm this video is in French")).toBeVisible();
  await expect(popup.getByRole("button", { name: "Start live captions on this tab" })).toBeEnabled();
});

test("no captions on a clearly French video: no warning, live captions available", async () => {
  const page = await videoPage([], "Bonjour, nous allons apprendre le français avec des amis", "Une vidéo pour les débutants qui est très simple et pour tous les gens.");
  const popup = await popupFor(page);
  await popup.getByText("Video has no captions?").click();
  await expect(popup.getByRole("button", { name: "Start live captions on this tab" })).toBeEnabled();
  await expect(popup.getByText("could not confirm")).toHaveCount(0);
});
