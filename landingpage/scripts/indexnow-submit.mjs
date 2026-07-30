// Pings IndexNow (Bing, Yandex, and other participating engines) with every URL in the
// generated sitemap. Runs automatically as an npm "postbuild" hook, so every future blog
// post or story update gets submitted on the next deploy with zero manual steps, as long
// as it's included in sitemap.ts (blog posts and stories both already are).
//
// Google is not part of the IndexNow consortium — this does not affect Google indexing.
// Use Search Console's URL Inspection tool for that instead.

import { readFile } from "node:fs/promises";

const INDEXNOW_KEY = "c7fa3bbfdb352c5334a6da6fc282705ba40d5a2a2d7721a2d317158c09b5e9cf";
const SITEMAP_BODY_PATH = ".next/server/app/sitemap.xml.body";

async function getUrlsFromSitemap() {
  const xml = await readFile(SITEMAP_BODY_PATH, "utf-8");
  const matches = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)];
  return matches.map((m) => m[1]);
}

async function main() {
  let urlList;
  try {
    urlList = await getUrlsFromSitemap();
  } catch (error) {
    console.warn("IndexNow: couldn't read the built sitemap, skipping submission.", error instanceof Error ? error.message : error);
    return;
  }

  if (urlList.length === 0 || urlList[0].includes("localhost")) {
    console.log(`IndexNow: skipping submission (local build, ${urlList.length} URLs, host: ${urlList[0] ?? "none"}).`);
    return;
  }

  const host = new URL(urlList[0]).host;
  const siteUrl = new URL(urlList[0]).origin;

  const payload = {
    host,
    key: INDEXNOW_KEY,
    keyLocation: `${siteUrl}/${INDEXNOW_KEY}.txt`,
    urlList,
  };

  try {
    const response = await fetch("https://api.indexnow.org/indexnow", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify(payload),
    });
    console.log(`IndexNow: submitted ${urlList.length} URLs from the sitemap, status ${response.status}`);
  } catch (error) {
    // Never fail the build over an IndexNow ping.
    console.warn("IndexNow: submission failed, continuing build.", error instanceof Error ? error.message : error);
  }
}

main();
