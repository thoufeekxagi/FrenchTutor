import { APP } from "./config";

/** Free and Pro limits. Free numbers mirror the server (immersion_take_quota); Pro values are placeholders. */
export const LIMITS = {
  free: { explainPerDay: 20, liveMinutesPerDay: 30, wordLookups: Infinity },
  pro: { explainPerDay: 500, liveMinutesPerDay: 300, wordLookups: Infinity },
} as const;

export const isPro = () => APP.plan === "pro";
export const limits = () => LIMITS[APP.plan];

/** Copy shown when a free limit is reached. Swap the text for an upgrade prompt when Pro launches. */
export function limitMessage(kind: "explain" | "live"): string {
  return kind === "explain"
    ? "You have used today’s free explanations. They reset tomorrow."
    : "Today’s free live captions are used up. They reset tomorrow.";
}
