export type Level = "A1" | "A2" | "B1" | "B2";
export interface Explanation {
  meaning: string;
  grammar: string;
  example: string;
  exampleTranslation: string;
}
export interface Word {
  id: string;
  text: string;
  sentence: string;
  level: Level;
  explanation?: Explanation;
  savedAt: number;
}
export interface Preferences {
  level: Level;
  hidden: boolean;
  enabled: boolean;
  aiConsent: boolean;
  offset: number;
  highlightSaved: boolean;
  highlightSpokenWords: boolean;
  captionSize: "comfortable" | "large";
  dock: "right" | "left";
  placement: "side" | "overlay" | "below" | "floating";
  showCaptions: boolean;
  showTranslation: boolean;
  compactView: boolean;
  tourDone: boolean;
  /** Normalized viewport coordinates, persisted so the floating panel survives reloads. */
  floatRect: { left: number; top: number; width: number; height: number };
}
export const defaults: Preferences = {
  level: "A1",
  hidden: false,
  enabled: true,
  aiConsent: false,
  offset: 0,
  highlightSaved: true,
  highlightSpokenWords: true,
  captionSize: "comfortable",
  dock: "right",
  placement: "side",
  showCaptions: true,
  showTranslation: false,
  compactView: true,
  tourDone: false,
  floatRect: { left: 0.54, top: 0.16, width: 0.4, height: 0.34 },
};

/** Shared migration/validation boundary for popup, content UI and background. */
export function validatedPreferencePatch(raw: unknown): Partial<Preferences> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const value = raw as Record<string, unknown>;
  const patch: Partial<Preferences> = {};
  if (
    typeof value.level === "string" &&
    ["A1", "A2", "B1", "B2"].includes(value.level)
  )
    patch.level = value.level as Level;
  for (const key of [
    "hidden",
    "enabled",
    "aiConsent",
    "highlightSaved",
    "highlightSpokenWords",
    "showCaptions",
    "showTranslation",
    "compactView",
    "tourDone",
  ] as const) {
    if (typeof value[key] === "boolean") patch[key] = value[key];
  }
  if (typeof value.offset === "number" && Number.isFinite(value.offset))
    patch.offset = Math.max(-600, Math.min(600, value.offset));
  if (value.captionSize === "comfortable" || value.captionSize === "large")
    patch.captionSize = value.captionSize;
  if (value.dock === "left" || value.dock === "right") patch.dock = value.dock;
  if (value.placement === "side" || value.placement === "overlay" || value.placement === "below" || value.placement === "floating")
    patch.placement = value.placement;
  if (value.floatRect && typeof value.floatRect === "object" && !Array.isArray(value.floatRect)) {
    const rect = value.floatRect as Record<string, unknown>;
    const number = (key: string, fallback: number, min: number, max: number) => {
      const raw = rect[key];
      return typeof raw === "number" && Number.isFinite(raw)
        ? Math.max(min, Math.min(max, raw))
        : fallback;
    };
    patch.floatRect = {
      left: number("left", defaults.floatRect.left, 0, 0.98),
      top: number("top", defaults.floatRect.top, 0, 0.98),
      width: number("width", defaults.floatRect.width, 0.25, 0.9),
      height: number("height", defaults.floatRect.height, 0.16, 0.85),
    };
  }
  return patch;
}
export function normalizePreferences(raw: unknown): Preferences {
  const patch = validatedPreferencePatch(raw);
  return { ...defaults, ...patch };
}
export function applyPreferencesPatch(
  current: unknown,
  patch: unknown,
): Preferences {
  return {
    ...normalizePreferences(current),
    ...validatedPreferencePatch(patch),
  };
}
