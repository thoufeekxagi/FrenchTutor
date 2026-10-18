import identity from "./extension-identity.json";
import { defineConfig } from "wxt";
import tailwindcss from "@tailwindcss/vite";
const qa = process.env.PARLESPRINT_QA === "1";
// The Chrome Web Store rejects packages whose manifest has a "key"; keep it only for local builds.
const store = process.env.PARLESPRINT_STORE === "1";
export default defineConfig({
  ...(qa ? { outDir: ".output-qa" } : {}),
  modules: ["@wxt-dev/module-react"],
  vite: () => ({ plugins: [tailwindcss()], define: { __QA__: JSON.stringify(qa) } }),
  manifest: {
    ...(store ? {} : { key: identity.key }),
    name: "ParleSprint Immersion",
    description:
      "French captions under YouTube videos with instant word meanings, English translation and a private vocabulary notebook.",
    permissions: ["storage", "activeTab", "scripting", "tabCapture", "offscreen"],
    host_permissions: [
      "https://oxfnrsjskdjbroekxdco.supabase.co/*",
      "https://translate.googleapis.com/*",
      "https://www.youtube.com/*",
      ...(qa ? ["https://upload.wikimedia.org/*"] : []),
    ],
    web_accessible_resources: [
      // The caption panel can be started on any video page, so its stylesheet and fonts must load there too.
      { resources: ["fonts/*", "content-scripts/content.css"], matches: ["<all_urls>"], use_dynamic_url: true },
    ],
    icons: {
      16: "icon-16.png",
      32: "icon-32.png",
      48: "icon-48.png",
      128: "icon-128.png",
    },
  },
});
