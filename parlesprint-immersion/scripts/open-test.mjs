import { chromium } from "@playwright/test";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const extension = path.join(root, ".output/chrome-mv3");
const videoId = process.env.PARLESPRINT_VIDEO || "EaNqp4FXh-s";
const start = process.env.PARLESPRINT_START || "60";
const context = await chromium.launchPersistentContext(path.join(root, ".local-browser"), {
  channel: "chromium",
  headless: false,
  args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`],
  viewport: null,
});
const page = context.pages()[0] ?? (await context.newPage());
await page.goto(`https://www.youtube.com/watch?v=${videoId}&t=${start}s`, { waitUntil: "domcontentloaded" });
console.log(`ParleSprint Immersion test browser is open on YouTube video ${videoId}. Close the window to stop.`);
await new Promise((resolve) => context.on("close", resolve));
