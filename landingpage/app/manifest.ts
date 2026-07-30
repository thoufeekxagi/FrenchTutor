import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "ParleSprint — Guided French Learning",
    short_name: "ParleSprint",
    description: "A guided French learning path for beginners across listening, speaking, reading, and writing.",
    start_url: "/",
    display: "standalone",
    background_color: "#f8f9fa",
    theme_color: "#007bff",
    icons: [
      { src: "/parle-mark.svg", sizes: "any", type: "image/svg+xml" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
  };
}
