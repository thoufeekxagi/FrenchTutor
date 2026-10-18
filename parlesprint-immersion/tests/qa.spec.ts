import {
  test,
  expect,
  chromium,
  type BrowserContext,
  type Page,
} from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
let context: BrowserContext;
const id = "ijclgmkoljddlalgcnpodeemcmcipolb";
let counter = 0;
test.beforeAll(async () => {
  const ext = path.resolve(".output/chrome-mv3");
  context = await chromium.launchPersistentContext("", {
    channel: "chromium",
    headless: true,
    args: [
      `--disable-extensions-except=${ext}`,
      `--load-extension=${ext}`,
      "--autoplay-policy=no-user-gesture-required",
    ],
    viewport: { width: 1280, height: 800 },
  });
});
test.afterAll(async () => await context?.close());
test.beforeEach(async () => {
  const w =
    context.serviceWorkers()[0] ??
    (await context.waitForEvent("serviceworker"));
  await w.evaluate(() => (globalThis as any).chrome.storage.local.clear());
});
test.afterEach(async () => {
  for (const page of context.pages()) await page.close();
});
async function fixture() {
  const page = await context.newPage();
  const data = await fs.readFile("tests/fixtures/timing.webm");
  await page.route("https://www.youtube.com/timing.webm", (r) => {
    const match = /bytes=(\d+)-(\d*)/.exec(r.request().headers().range ?? "");
    const start = match ? Number(match[1]) : 0;
    const end = match?.[2] ? Number(match[2]) : data.length - 1;
    return r.fulfill({
      status: match ? 206 : 200,
      contentType: "video/webm",
      headers: {
        "Accept-Ranges": "bytes",
        ...(match
          ? { "Content-Range": `bytes ${start}-${end}/${data.length}` }
          : {}),
      },
      body: data.subarray(start, end + 1),
    });
  });
  await page.route("https://www.youtube.com/watch?*", (r) =>
    r.fulfill({
      contentType: "text/html",
      body: '<!doctype html><html><meta charset="UTF-8"><body><h1>QA fixture</h1><main id="primary-inner"><div id="player-container-outer"><div id="movie_player" class="html5-video-player"><video controls src="/timing.webm" style="display:block;width:min(80vw,900px);aspect-ratio:16/9;background:#222"></video></div></div><div id="below-description">Video description</div></main></body></html>',
    }),
  );
  await page.goto(`https://www.youtube.com/watch?v=qa-${++counter}`);
  const panel = page.getByRole("complementary", {
    name: "ParleSprint Immersion",
  });
  await expect(panel).toBeVisible();
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.readyState),
    )
    .toBeGreaterThan(0);
  await panel.getByRole("button", { name: "More subtitle settings" }).click();
  return { page, panel };
}
async function imported() {
  const value = await fixture();
  await value.panel
    .getByLabel("Import French subtitles")
    .setInputFiles("public/demo-fr.srt");
  await expect(value.panel.getByText("Source: demo-fr.srt")).toBeVisible();
  return value;
}
async function seek(page: Page, t: number) {
  await page.locator("video").evaluate((v: HTMLVideoElement, t) => {
    v.currentTime = t;
  }, t);
  await expect
    .poll(() =>
      page
        .locator("video")
        .evaluate((v: HTMLVideoElement, t) => Math.abs(v.currentTime - t), t),
    )
    .toBeLessThan(0.2);
}

test("watch-page default stays compact, brand-free and below the player", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles("public/demo-fr.srt");
  await panel.getByRole("button", { name: "Hide subtitle settings" }).click();
  await expect(panel.locator(".brand-lockup")).toHaveCount(0);
  await expect(panel.locator(".sentence")).toBeVisible();
  await expect(panel.locator(".sentence")).toContainText("Bonjour");
  await expect(panel.getByText("Reading & playback", { exact: true })).toBeHidden();
  const [panelBox, videoBox] = await Promise.all([
    panel.boundingBox(),
    page.locator("video").boundingBox(),
  ]);
  expect(panelBox).not.toBeNull();
  expect(videoBox).not.toBeNull();
  expect(panelBox!.y).toBeGreaterThanOrEqual(videoBox!.y + videoBox!.height);
  await expect(panel).toHaveClass(/layout-below/);
  await expect(panel.locator(".sentence")).toHaveCSS("-webkit-line-clamp", "2");
  expect(
    await page.locator("parlesprint-immersion").evaluate(
      (host) =>
        host.parentElement?.id === "primary-inner" &&
        host.previousElementSibling?.id === "player-container-outer",
    ),
  ).toBe(true);
  await page.screenshot({ path: "artifacts/quiet-watch-default.png" });
});

test("theater width stays below the player; floating captions can be moved and resized", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles("public/demo-fr.srt");
  await page.locator("#player-container-outer").evaluate((el) => {
    (el as HTMLElement).style.width = "100vw";
    (el.querySelector("video") as HTMLElement).style.width = "100vw";
  });
  await expect
    .poll(async () => {
      const panelBox = await panel.boundingBox();
      const playerBox = await page.locator("video").boundingBox();
      return panelBox!.y >= playerBox!.y + playerBox!.height;
    })
    .toBe(true);
  await panel.getByText("Reading & playback", { exact: true }).click();
  await panel.getByLabel("Caption placement").selectOption("floating");
  await expect(panel).toHaveClass(/layout-floating/);

  const move = await panel.getByRole("button", { name: "Move captions" }).boundingBox();
  const beforeMove = await panel.boundingBox();
  await page.mouse.move(move!.x + move!.width / 2, move!.y + move!.height / 2);
  await page.mouse.down();
  await page.mouse.move(move!.x + move!.width / 2 + 70, move!.y + move!.height / 2 + 55);
  await page.mouse.up();
  const afterMove = await panel.boundingBox();
  expect(afterMove!.x).toBeGreaterThan(beforeMove!.x + 30);
  expect(afterMove!.y).toBeGreaterThan(beforeMove!.y + 20);

  const resize = await panel.getByRole("button", { name: "Resize captions" }).boundingBox();
  const beforeResize = await panel.boundingBox();
  await page.mouse.move(resize!.x + resize!.width / 2, resize!.y + resize!.height / 2);
  await page.mouse.down();
  await page.mouse.move(resize!.x + resize!.width / 2 + 65, resize!.y + resize!.height / 2 + 45);
  await page.mouse.up();
  const afterResize = await panel.boundingBox();
  expect(afterResize!.width).toBeGreaterThan(beforeResize!.width + 30);
  expect(afterResize!.height).toBeGreaterThan(beforeResize!.height + 20);

  const savedRect = await panel.evaluate((el) => ({ left: el.style.left, top: el.style.top, width: el.style.width }));
  await page.reload();
  const reloaded = page.getByRole("complementary", { name: "ParleSprint Immersion" });
  await expect(reloaded).toHaveClass(/layout-floating/);
  await expect.poll(() => reloaded.evaluate((el) => el.style.left)).toBe(savedRect.left);
  await expect.poll(() => reloaded.evaluate((el) => el.style.width)).toBe(savedRect.width);
});

test("spoken-word highlight follows caption timing and can be switched off", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "words.srt",
    mimeType: "text/plain",
    buffer: Buffer.from("1\n00:00:00,000 --> 00:00:10,000\nBonjour, comment allez-vous ?"),
  });
  await seek(page, 1);
  await page.locator("video").evaluate((video: HTMLVideoElement) => video.play());
  await expect(panel.locator(".word.spoken")).toHaveText("Bonjour");
  await panel.screenshot({ path: "artifacts/spoken-word-highlight-timed-fixture.png" });
  await seek(page, 8);
  await expect(panel.locator(".word.spoken")).toHaveText("allez-vous");
  await panel.getByText("Reading & playback", { exact: true }).click();
  await panel.getByLabel("Highlight words as the video plays").uncheck();
  await expect(panel.locator(".word.spoken")).toHaveCount(0);
  await page.locator("video").evaluate((video: HTMLVideoElement) => video.pause());
});

test("10/15 second seeks stay on the video timeline and ads suppress video captions", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "playhead-edges.srt",
    mimeType: "text/plain",
    buffer: Buffer.from(
      "1\n00:00:10,000 --> 00:00:12,000\nDix secondes.\n\n2\n00:00:15,000 --> 00:00:18,000\nQuinze secondes.",
    ),
  });
  await seek(page, 10);
  await expect(panel.locator(".sentence")).toContainText("Dix secondes.");
  await seek(page, 15);
  await expect(panel.locator(".sentence")).toContainText("Quinze secondes.");

  await page.locator("#movie_player").evaluate((player) => player.classList.add("ad-showing"));
  await expect(panel.locator(".sentence")).toHaveCount(0);

  await page.locator("#movie_player").evaluate((player) => player.classList.remove("ad-showing"));
  await expect(panel.locator(".sentence")).toContainText("Quinze secondes.");
});

test("first practice works entirely offline with real media, free meaning, replay and vocabulary", async () => {
  await context.setOffline(true);
  const page = await context.newPage();
  await page.goto(`chrome-extension://${id}/practice.html`);
  await expect(
    page.getByRole("heading", { name: "A little French. A real first step." }),
  ).toBeVisible();
  const panel = page.getByRole("complementary", {
    name: "ParleSprint Immersion",
  });
  await expect(panel.locator(".sentence")).toContainText("Bonjour");
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.readyState),
    )
    .toBeGreaterThan(0);
  await panel.getByText("Reveal sentence translation").click();
  await expect(
    panel.getByText(
      "Hello! Today, I am preparing for my first trip to Quebec.",
    ),
  ).toBeVisible();
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeGreaterThan(0.1);
  await page.locator("video").evaluate((v: HTMLVideoElement) => v.pause());
  await panel
    .getByRole("button", { name: "Study Bonjour", exact: true })
    .click();
  await panel.getByRole("button", { name: "Save phrase", exact: true }).click();
  await expect(panel.getByRole("button", { name: "Saved ✓" })).toBeVisible();
  await panel.evaluate((el) => {
    el.scrollTop = 0;
  });
  await page.screenshot({ path: "artifacts/qa-first-practice.png" });
  const opened = context.waitForEvent("page");
  await panel
    .getByRole("button", { name: "Account connection for AI", exact: true })
    .click();
  const popup = await opened;
  await popup.waitForLoadState();
  await expect(popup).toHaveURL(`chrome-extension://${id}/popup.html#account`);
  await expect(
    popup.getByRole("tab", { name: "Account", exact: true }),
  ).toHaveAttribute("aria-selected", "true");
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await expect(popup.getByText("Bonjour", { exact: true })).toBeVisible();
  await popup.getByRole("tab", { name: "Practice", exact: true }).click();
  await expect(
    popup.getByRole("link", { name: "Try your first practice" }),
  ).toBeVisible();
  await context.setOffline(false);
});

test("manual seeking and disabling the companion cancel the replay stop", async () => {
  const { page, panel } = await imported();
  await seek(page, 1);
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  await seek(page, 3.8);
  await page.locator("video").evaluate((v: HTMLVideoElement) => v.play());
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeGreaterThan(4.3);
  expect(
    await page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
  ).toBe(false);
  await page.locator("video").evaluate((v: HTMLVideoElement) => v.pause());
  await seek(page, 1);
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await popup.getByLabel("Show companion on video pages").uncheck();
  await expect(panel).toHaveCount(0);
  await seek(page, 3.8);
  await page.locator("video").evaluate((v: HTMLVideoElement) => v.play());
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeGreaterThan(4.3);
  expect(
    await page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
  ).toBe(false);
});

test("timing is per video and caption import does not finish on a different route", async () => {
  const { page, panel } = await imported();
  const first = page.url();
  await panel.getByText("Timing & transcript").click();
  await panel.getByLabel("Subtitle delay in seconds").fill("2");
  await page.evaluate(() => history.pushState({}, "", "/watch?v=qa-other"));
  await expect(panel.getByText("Source: demo-fr.srt")).toHaveCount(0);
  await panel
    .getByLabel("Import French subtitles")
    .setInputFiles("public/demo-fr.srt");
  await panel.getByText("Timing & transcript").click();
  await expect(panel.getByLabel("Subtitle delay in seconds")).toHaveValue("0");
  await page.evaluate((url) => history.pushState({}, "", url), first);
  await expect(panel.getByLabel("Subtitle delay in seconds")).toHaveValue("2");
  await panel.getByText("Source: demo-fr.srt", { exact: true }).click();
  await panel
    .getByRole("button", { name: "Clear subtitles", exact: true })
    .click();
  await expect(panel.getByText("Source: demo-fr.srt")).toHaveCount(0);
  await panel
    .getByLabel("Import French subtitles")
    .evaluate((el) =>
      el.addEventListener(
        "change",
        () => history.pushState({}, "", "/watch?v=qa-redirected"),
        { capture: true, once: true },
      ),
    );
  await panel
    .getByLabel("Import French subtitles")
    .setInputFiles("public/demo-fr.srt");
  await expect(panel.getByText("Source: demo-fr.srt")).toHaveCount(0);
  await page.evaluate((url) => history.pushState({}, "", url), first);
  await expect(panel.getByText("Source: demo-fr.srt")).toHaveCount(0);
});

test("all transcript pages, keyboard reveal, long words, 200 percent zoom and homepage are usable", async () => {
  const { page, panel } = await fixture();
  const time = (t: number) =>
    `00:${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")},000`;
  const subtitles = Array.from(
    { length: 250 },
    (_, i) =>
      `${i + 1}\n${time(i * 2)} --> ${time(i * 2 + 1)}\nPhrase numéro ${i + 1}.`,
  ).join("\n\n");
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "long.srt",
    mimeType: "text/plain",
    buffer: Buffer.from(subtitles),
  });
  await panel.getByText("Timing & transcript").click();
  await panel
    .getByRole("button", { name: "Next sentences", exact: true })
    .click();
  await panel
    .getByRole("button", { name: "Next sentences", exact: true })
    .click();
  await expect(panel.getByText("Sentences 201–250 of 250")).toBeVisible();
  await expect(
    panel.getByRole("button", { name: /Phrase numéro 250/ }),
  ).toBeVisible();
  await panel
    .getByRole("button", { name: "Jump to current sentence", exact: true })
    .click();
  await expect(panel.getByText("Sentences 1–100 of 250")).toBeVisible();
  await page.evaluate(() => {
    (window as any).__siteKeys = 0;
    document.addEventListener("keydown", () => {
      (window as any).__siteKeys++;
    });
  });
  await panel.getByText("Reading & playback", { exact: true }).click();
  await panel.getByLabel("Hide French until revealed").press("Space");
  expect(await page.evaluate(() => (window as any).__siteKeys)).toBe(0);
  await expect(
    panel.getByRole("button", { name: "Reveal French sentence" }),
  ).toBeVisible();
  await panel
    .getByRole("button", { name: "Reveal French sentence" })
    .press("Enter");
  await expect(panel.locator(".sentence")).toContainText("Phrase numéro 1");
  const worker = context.serviceWorkers()[0]!;
  await worker.evaluate(async () => {
    const chrome = (globalThis as any).chrome;
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    await chrome.tabs.setZoom(tabs[0].id, 2);
  });
  await expect
    .poll(() => page.evaluate(() => innerWidth))
    .toBeLessThanOrEqual(640);
  await expect(
    panel.getByRole("button", { name: "Minimize immersion" }),
  ).toBeVisible();
  await panel.getByRole("button", { name: "Minimize immersion" }).click();
  await panel.getByRole("button", { name: "Expand immersion" }).click();
  const box = await panel.boundingBox();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.width).toBeLessThan(640);
  await page.screenshot({ path: "artifacts/qa-zoom.png" });
  await worker.evaluate(async () => {
    const chrome = (globalThis as any).chrome;
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    await chrome.tabs.setZoom(tabs[0].id, 1);
  });
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "word.srt",
    mimeType: "text/plain",
    buffer: Buffer.from(
      `1\n00:00:00,000 --> 00:00:02,000\n${"a".repeat(3500)}`,
    ),
  });
  const overflow = await panel.evaluate(
    (el) => el.scrollWidth > el.clientWidth + 2,
  );
  expect(overflow).toBe(false);
  await page.evaluate(() => history.pushState({}, "", "/"));
  await expect(panel).toHaveCount(0);
});

test("caption reveal and meaning reveal stay independent across playback", async () => {
  const { page, panel } = await imported();
  const worker = context.serviceWorkers()[0]!;
  await worker.evaluate(async () => {
    const c = (globalThis as any).chrome;
    await c.storage.local.set({
      session: {
        access_token: "fixture-access",
        refresh_token: "fixture-refresh",
        expires_at: Date.now() + 3600000,
      },
      prefs: {
        level: "B1",
        hidden: true,
        enabled: true,
        aiConsent: true,
        offset: 0,
      },
    });
  });
  await context.route(
    "https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-explain",
    (r) => {
      expect(r.request().postDataJSON().text).toBe("Bonjour");
      return r.fulfill({
        contentType: "application/json",
        body: JSON.stringify({
          meaning: "Fixture meaning",
          grammar: "Fixture grammar",
          example: "Bonjour !",
          exampleTranslation: "Hello!",
        }),
      });
    },
  );
  await expect(
    panel.getByRole("button", { name: "Reveal French sentence" }),
  ).toBeVisible();
  await panel.getByRole("button", { name: "Reveal French sentence" }).click();
  await panel
    .getByRole("button", { name: "Study Bonjour", exact: true })
    .click();
  await expect(
    panel.getByRole("button", { name: "Reveal meaning", exact: true }),
  ).toBeVisible();
  await seek(page, 5);
  await panel.getByRole("button", { name: "Reveal French sentence" }).click();
  await expect(
    panel.getByRole("button", { name: "Reveal meaning", exact: true }),
  ).toBeVisible();
  await expect(panel.getByText("Fixture meaning", { exact: true })).toHaveCount(
    0,
  );
  await panel
    .getByRole("button", { name: "Reveal meaning", exact: true })
    .click();
  await expect(
    panel.getByText("Fixture meaning", { exact: true }),
  ).toBeVisible();
  await seek(page, 9);
  await expect(
    panel.getByText("Fixture meaning", { exact: true }),
  ).toBeVisible();
  await context.unroute(
    "https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-explain",
  );
});

test("sentence translation uses a separate one-field response and is reused on the same caption", async () => {
  const { panel } = await imported();
  const worker = context.serviceWorkers()[0]!;
  await worker.evaluate(async () => {
    const c = (globalThis as any).chrome;
    await c.storage.local.set({
      session: {
        access_token: "fixture-access",
        refresh_token: "fixture-refresh",
        expires_at: Date.now() + 3600000,
      },
    });
  });
  let requests = 0;
  await context.route(
    "https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-explain",
    async (route) => {
      requests++;
      const body = route.request().postDataJSON();
      expect(body.mode).toBe("translation");
      await route.fulfill({
        contentType: "application/json",
        body: JSON.stringify({ translation: "Hello! Today, I am preparing for my first trip to Quebec." }),
      });
    },
  );
  await panel.getByRole("button", { name: "Translate sentence", exact: true }).click();
  await expect(panel.getByText(/Allow ParleSprint to send this sentence/)).toBeVisible();
  await panel.getByRole("button", { name: "Allow & translate", exact: true }).click();
  await expect(panel.getByText("Hello! Today, I am preparing for my first trip to Quebec.", { exact: true })).toBeVisible();
  await panel.getByRole("button", { name: "Hide translation", exact: true }).click();
  await expect(panel.locator(".sentence-translation")).toHaveCount(0);
  await panel.getByRole("button", { name: "Translate sentence", exact: true }).click();
  await expect(panel.locator(".sentence-translation")).toBeVisible();
  expect(requests).toBe(1);
  await context.unroute("https://oxfnrsjskdjbroekxdco.supabase.co/functions/v1/immersion-explain");
});

test("short sentence replay stops accurately at fast playback and clears after subtitle removal", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "short.srt",
    mimeType: "text/plain",
    buffer: Buffer.from("1\n00:00:01,000 --> 00:00:01,120\nSalut !"),
  });
  await seek(page, 1.02);
  await page.locator("video").evaluate((v: HTMLVideoElement) => {
    v.playbackRate = 2;
  });
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
    )
    .toBe(true);
  const stopped = await page
    .locator("video")
    .evaluate((v: HTMLVideoElement) => v.currentTime);
  expect(stopped).toBeGreaterThanOrEqual(1.12);
  expect(stopped).toBeLessThan(1.26);
  await seek(page, 1.02);
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  await panel.getByText("Source: short.srt", { exact: true }).click();
  await panel
    .getByRole("button", { name: "Clear subtitles", exact: true })
    .click();
  await seek(page, 1.05);
  await page.locator("video").evaluate((v: HTMLVideoElement) => v.play());
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeGreaterThan(1.4);
  expect(
    await page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
  ).toBe(false);
});

test("every bundled spoken sentence and its authored meaning is synchronized", async () => {
  const page = await context.newPage();
  await page.goto(`chrome-extension://${id}/practice.html`);
  const data = JSON.parse(await fs.readFile("public/practice.json", "utf8"));
  const panel = page.getByRole("complementary", {
    name: "ParleSprint Immersion",
  });
  await expect(panel.locator(".sentence")).toBeVisible();
  for (const cue of data.cues) {
    await seek(page, cue.start + 0.1);
    await expect(panel.locator(".sentence")).toHaveText(cue.text);
    const reveal = panel.getByText("Reveal sentence translation", {
      exact: true,
    });
    if (!(await panel.getByText(cue.translation, { exact: true }).isVisible()))
      await reveal.click();
    await expect(
      panel.getByText(cue.translation, { exact: true }),
    ).toBeVisible();
  }
  await seek(page, data.duration - 0.05);
  await expect(panel.locator(".sentence")).toHaveCount(0);
});

test("practice uses bundled Inter, blue primary actions and fits a narrow screen", async () => {
  const page = await context.newPage();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`chrome-extension://${id}/practice.html`);
  const panel = page.getByRole("complementary", {
    name: "ParleSprint Immersion",
  });
  await expect(panel.locator(".sentence")).toContainText("Bonjour");
  await expect
    .poll(() =>
      page.evaluate(() =>
        Array.from(document.fonts).some(
          (face) =>
            face.family.replaceAll('"', "") === "ParleSprint Inter" &&
            face.status === "loaded",
        ),
      ),
    )
    .toBe(true);
  const family = await panel.evaluate((el) => getComputedStyle(el).fontFamily);
  expect(family).toContain("ParleSprint Inter");
  await panel
    .getByRole("button", { name: "Study Bonjour", exact: true })
    .click();
  const primary = panel.getByRole("button", {
    name: "Explain in context",
    exact: true,
  });
  await expect(primary).toHaveCSS("background-color", "rgb(37, 99, 235)");
  const overflow = await page.evaluate(() => ({
    document:
      document.documentElement.scrollWidth -
      document.documentElement.clientWidth,
    panels: Array.from(
      document.querySelectorAll(".companion,.practice-main"),
    ).map((el) => el.scrollWidth - el.clientWidth),
  }));
  expect(overflow.document).toBeLessThanOrEqual(2);
  expect(overflow.panels.every((width) => width <= 2)).toBe(true);
  await page.screenshot({
    path: "artifacts/qa-practice-narrow.png",
    fullPage: true,
  });
});

test("word occurrences and keyboard phrase ranges save exact text with live notebook highlighting", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "selection.srt",
    mimeType: "text/plain",
    buffer: Buffer.from(
      "1\n00:00:00,000 --> 00:00:10,000\nBonjour, bonjour ! Je voudrais réserver.",
    ),
  });
  const repeated = panel.getByRole("button", {
    name: "Study bonjour",
    exact: true,
  });
  await repeated.click();
  await page.mouse.move(0, 0);
  await expect(repeated).toHaveCSS("background-color", "rgb(37, 99, 235)");
  await expect(panel.locator('.word[aria-pressed="true"]')).toHaveCount(1);
  await expect(
    panel.getByRole("button", { name: "Study Bonjour", exact: true }),
  ).toHaveAttribute("aria-pressed", "false");
  await expect(
    panel.getByRole("button", { name: "Study !", exact: true }),
  ).toHaveCount(0);
  await panel
    .getByRole("button", { name: "Select a phrase", exact: true })
    .press("Enter");
  await panel
    .getByRole("button", { name: "Study voudrais", exact: true })
    .press("Enter");
  await panel
    .getByRole("button", { name: "Study Je", exact: true })
    .press("Enter");
  await expect(
    panel
      .getByRole("region", { name: "Selected phrase" })
      .getByRole("heading", { name: "Je voudrais", exact: true }),
  ).toBeVisible();
  await expect(panel.locator('.word[aria-pressed="true"]')).toHaveCount(2);
  await panel.getByRole("button", { name: "Save phrase", exact: true }).click();
  await expect(panel.locator('.word[data-saved="true"]')).toHaveCount(2);
  await repeated.click();
  await expect(
    panel.getByRole("button", { name: "Study Je", exact: true }),
  ).toHaveCSS("color", "rgb(22, 101, 52)");
  await expect(
    panel.getByRole("button", { name: "Study Je", exact: true }),
  ).toHaveCSS("text-decoration-style", "dotted");
  await panel.getByRole("button", { name: "Study Je", exact: true }).click();
  await panel
    .getByRole("button", { name: "Study réserver", exact: true })
    .click({ modifiers: ["Shift"] });
  await expect(
    panel.getByRole("heading", { name: "Je voudrais réserver", exact: true }),
  ).toBeVisible();
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await expect(
    popup.getByRole("heading", { name: "Je voudrais", exact: true }),
  ).toBeVisible();
  await popup
    .getByRole("button", { name: "Remove phrase", exact: true })
    .click();
  await expect(panel.locator('.word[data-saved="true"]')).toHaveCount(0);
  await page.close();
});

test("replay holds an adjacent sentence for study and next previous respect slower playback", async () => {
  const { page, panel } = await fixture();
  await panel.getByLabel("Import French subtitles").setInputFiles({
    name: "adjacent.srt",
    mimeType: "text/plain",
    buffer: Buffer.from(
      "1\n00:00:01,000 --> 00:00:01,400\nPremière phrase.\n\n2\n00:00:01,400 --> 00:00:01,800\nDeuxième phrase.",
    ),
  });
  await seek(page, 1.05);
  await panel.getByText("Reading & playback", { exact: true }).click();
  await panel
    .getByLabel("Playback speed", { exact: true })
    .selectOption("0.75");
  expect(
    await page
      .locator("video")
      .evaluate((v: HTMLVideoElement) => v.playbackRate),
  ).toBe(0.75);
  await panel.getByRole("button", { name: "↻ Repeat", exact: true }).click();
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeGreaterThanOrEqual(1.4);
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
    )
    .toBe(true);
  await expect(panel.locator(".sentence")).toHaveText("Première phrase.");
  await panel.getByText("More sentences", { exact: true }).click();
  await expect(
    panel.getByRole("button", { name: "Previous sentence", exact: true }),
  ).toBeDisabled();
  await panel
    .getByRole("button", { name: "Next sentence", exact: true })
    .click();
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.currentTime),
    )
    .toBeGreaterThanOrEqual(1.8);
  await expect
    .poll(() =>
      page.locator("video").evaluate((v: HTMLVideoElement) => v.paused),
    )
    .toBe(true);
  await expect(panel.locator(".sentence")).toHaveText("Deuxième phrase.");
  await expect(
    panel.getByRole("button", { name: "Next sentence", exact: true }),
  ).toBeDisabled();
  await panel
    .getByRole("button", { name: "Previous sentence", exact: true })
    .click();
  await expect(panel.locator(".sentence")).toHaveText("Première phrase.");
});

test("reading preferences synchronize with popup and retain floating placement after reload", async () => {
  const { page, panel } = await imported();
  const originalSize = await panel
    .locator(".sentence")
    .evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await popup.getByText("Reading preferences", { exact: true }).click();
  await popup.getByLabel("Caption size", { exact: true }).selectOption("large");
  await popup
    .getByLabel("Caption placement", { exact: true })
    .selectOption("floating");
  await popup
    .getByLabel("Highlight saved vocabulary", { exact: true })
    .uncheck();
  await expect(panel).toHaveClass(/caption-large/);
  await expect(panel).toHaveClass(/layout-floating/);
  const largerSize = await panel
    .locator(".sentence")
    .evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  expect(largerSize).toBeGreaterThan(originalSize);
  const box = await panel.boundingBox();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.x + box!.width).toBeLessThanOrEqual(1280);
  await panel.getByText("Reading & playback", { exact: true }).click();
  await expect(
    panel.getByLabel("Highlight saved words and phrases", { exact: true }),
  ).not.toBeChecked();
  await panel
    .getByLabel("Highlight saved words and phrases", { exact: true })
    .check();
  await expect(
    popup.getByLabel("Highlight saved vocabulary", { exact: true }),
  ).toBeChecked();
  await page.reload();
  await expect(panel).toHaveClass(/caption-large/);
  await expect(panel).toHaveClass(/layout-floating/);
  await panel.getByRole("button", { name: "More subtitle settings" }).click();
  await panel.getByText("Reading & playback", { exact: true }).click();
  await expect(panel.getByLabel("Caption size", { exact: true })).toHaveValue(
    "large",
  );
  await expect(
    panel.getByLabel("Caption placement", { exact: true }),
  ).toHaveValue("floating");
});

test("notebook accent search filters phrases while Anki export retains actual complete fields", async () => {
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  await popup.evaluate(async () => {
    const api = (globalThis as any).chrome;
    for (const word of [
      {
        id: "qa-ecole",
        text: "École",
        sentence: "Je vais à l’école.",
        level: "A1",
        savedAt: Date.now(),
        explanation: {
          meaning: "School",
          grammar: "A feminine noun.",
          example: "Une école.",
          exampleTranslation: "A school.",
        },
      },
      {
        id: "qa-billet",
        text: "billet",
        sentence: "Mon billet, s’il vous plaît.",
        level: "A1",
        savedAt: Date.now(),
      },
    ]) {
      const result = await api.runtime.sendMessage({ type: "save-word", word });
      if (result.error) throw Error(result.error);
    }
  });
  await popup.getByRole("tab", { name: "Notebook", exact: true }).click();
  await popup.getByLabel("Search your notebook", { exact: true }).fill("ecole");
  await expect(
    popup.getByRole("heading", { name: "École", exact: true }),
  ).toBeVisible();
  await expect(
    popup.getByRole("heading", { name: "billet", exact: true }),
  ).toHaveCount(0);
  await popup
    .getByLabel("Search your notebook", { exact: true })
    .fill("doesnotexist");
  await expect(
    popup.getByRole("heading", { name: "No matching phrases", exact: true }),
  ).toBeVisible();
  const downloaded = popup.waitForEvent("download");
  await popup
    .getByRole("button", { name: "Export Anki CSV", exact: true })
    .click();
  const download = await downloaded;
  expect(download.suggestedFilename()).toBe("parlesprint-vocabulary-anki.csv");
  const file = await download.path();
  expect(file).not.toBeNull();
  const csv = await fs.readFile(file!, "utf8");
  expect(csv).toContain("#columns:Front,Back,Context");
  expect(csv).toContain('"École","School","Je vais à l’école."');
  expect(csv).toContain('"billet","","Mon billet, s’il vous plaît."');
  await popup
    .getByRole("button", { name: "Show all phrases", exact: true })
    .click();
  await expect(
    popup.getByRole("button", { name: "Remove phrase", exact: true }),
  ).toHaveCount(2);
});
