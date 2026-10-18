import identity from "./extension-identity.json";
import { defineConfig } from "wxt";
import tailwindcss from "@tailwindcss/vite";
const qa = process.env.PARLESPRINT_QA === "1";
export default defineConfig({
  ...(qa ? { outDir: ".output-qa" } : {}),
  modules: ["@wxt-dev/module-react"],
  vite: () => ({ plugins: [tailwindcss()] }),
  manifest: {
    key: identity.key,
    name: "ParleSprint Immersion",
    description:
      "French captions under YouTube videos with instant word meanings, English translation and a private vocabulary notebook.",
    permissions: ["storage", "activeTab", "scripting", "tabCapture", "offscreen"],
    host_permissions: [
      "https://oxfnrsjskdjbroekxdco.supabase.co/*",
      "https://generativelanguage.googleapis.com/*",
      "https://translate.googleapis.com/*",
      "https://www.youtube.com/*",
      ...(qa ? ["https://www.youtube.com/*"] : []),
    ],
    web_accessible_resources: [
      { resources: ["fonts/*"], matches: ["<all_urls>"] },
    ],
    icons: {
      16: "icon-16.png",
      32: "icon-32.png",
      48: "icon-48.png",
      128: "icon-128.png",
    },
  },
});
