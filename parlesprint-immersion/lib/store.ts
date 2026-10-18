import { create } from "zustand";
import { browser } from "wxt/browser";
import {
  defaults,
  normalizePreferences as prefsFrom,
  applyPreferencesPatch,
  validatedPreferencePatch,
  type Preferences,
  type Word,
} from "./types";
interface State {
  prefs: Preferences;
  words: Word[];
  ready: boolean;
  storageError: string;
  load: () => Promise<void>;
  update: (patch: Partial<Preferences>) => Promise<void>;
  save: (word: Word) => Promise<void>;
  remove: (id: string) => Promise<void>;
}
function wordsFrom(value: unknown): Word[] {
  return Array.isArray(value)
    ? value
        .filter(
          (w) =>
            w &&
            typeof w.id === "string" &&
            typeof w.text === "string" &&
            typeof w.sentence === "string" &&
            ["A1", "A2", "B1", "B2"].includes(w.level) &&
            typeof w.savedAt === "number" &&
            (!w.explanation ||
              ["meaning", "grammar", "example", "exampleTranslation"].every(
                (k) => typeof w.explanation[k] === "string",
              )),
        )
        .slice(0, 2000)
    : [];
}
export const useStore = create<State>((set, get) => ({
  prefs: defaults,
  words: [],
  ready: false,
  storageError: "",
  load: async () => {
    try {
      const data = await browser.storage.local.get(["prefs", "words"]);
      set({
        prefs: prefsFrom(data.prefs),
        words: wordsFrom(data.words),
        ready: true,
        storageError: "",
      });
    } catch {
      set({
        ready: true,
        storageError:
          "Could not read browser storage. Reload the page to try again.",
      });
    }
  },
  update: async (patch) => {
    const previous = get().prefs;
    const validPatch = validatedPreferencePatch(patch);
    set({
      prefs: applyPreferencesPatch(previous, validPatch),
      storageError: "",
    });
    try {
      const result = await browser.runtime.sendMessage({
        type: "update-prefs",
        patch: validPatch,
      });
      if (result?.error) throw Error(result.error);
      set({ prefs: prefsFrom(result.prefs) });
    } catch {
      set({
        prefs: previous,
        storageError: "Your preference could not be saved. Please try again.",
      });
    }
  },
  save: async (word) => {
    try {
      const result = await browser.runtime.sendMessage({
        type: "save-word",
        word,
      });
      if (result?.error) throw Error(result.error);
      set({ words: wordsFrom(result.words), storageError: "" });
    } catch (e) {
      set({
        storageError:
          "Your phrase could not be saved. Browser storage may be full.",
      });
      throw e;
    }
  },
  remove: async (id) => {
    try {
      const result = await browser.runtime.sendMessage({
        type: "remove-word",
        id,
      });
      if (result?.error) throw Error(result.error);
      set({ words: wordsFrom(result.words), storageError: "" });
    } catch {
      set({
        storageError: "Your phrase could not be removed. Please try again.",
      });
    }
  },
}));
browser.storage.onChanged.addListener((changes, area) => {
  if (area !== "local") return;
  if (changes.prefs)
    useStore.setState({ prefs: prefsFrom(changes.prefs.newValue) });
  if (changes.words)
    useStore.setState({ words: wordsFrom(changes.words.newValue) });
});
