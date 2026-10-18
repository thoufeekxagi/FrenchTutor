import { browser } from "wxt/browser";
/** The same Inter family as the app, bundled locally with its OFL license. */
const face = new FontFace(
  "ParleSprint Inter",
  `url(${browser.runtime.getURL("/fonts/inter-latin.woff2")})`,
  { weight: "100 900", style: "normal", display: "swap" },
);
document.fonts.add(face);
void face.load().catch(() => {});
