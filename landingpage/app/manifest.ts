import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "ParleSprint — Personalized French Practice",
    short_name: "ParleSprint",
    description: "Connected French practice with personalized feedback across vocabulary, grammar, listening, writing, and live AI speaking.",
    start_url: "/",
    display: "standalone",
    background_color: "#faf9f6",
    theme_color: "#1b2a4a",
    icons: [{ src: "/parle-mark.svg", sizes: "any", type: "image/svg+xml" }],
  };
}
