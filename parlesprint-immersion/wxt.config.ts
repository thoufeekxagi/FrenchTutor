import identity from "./extension-identity.json";
import { defineConfig } from "wxt";
import tailwindcss from "@tailwindcss/vite";
export default defineConfig({
  modules: ["@wxt-dev/module-react"],
  vite: () => ({ plugins: [tailwindcss()] }),
  manifest: {
    key: identity.key,
    name: "ParleSprint Immersion",
    description:
      "Live French captions from video audio, sentence replay, and a personal vocabulary notebook.",
    permissions: ["storage", "activeTab", "scripting", "tabCapture", "offscreen"],
    host_permissions: [
      "https://oxfnrsjskdjbroekxdco.supabase.co/*",
      "https://generativelanguage.googleapis.com/*",
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
