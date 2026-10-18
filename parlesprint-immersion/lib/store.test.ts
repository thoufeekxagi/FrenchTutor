import { describe, it, expect, vi, beforeEach } from "vitest";
const mock = vi.hoisted(() => ({
  get: vi.fn(),
  send: vi.fn(),
  listener: undefined as any,
}));
vi.mock("wxt/browser", () => ({
  browser: {
    runtime: { sendMessage: mock.send },
    storage: {
      local: { get: mock.get },
      onChanged: {
        addListener: (f: any) => {
          mock.listener = f;
        },
      },
    },
  },
}));
import { useStore } from "./store";
import { defaults } from "./types";
beforeEach(() => {
  mock.get.mockReset();
  mock.send.mockReset();
  useStore.setState({
    prefs: defaults,
    words: [],
    ready: false,
    storageError: "",
  });
});
describe("local-first storage recovery", () => {
  it("opens an actionable error instead of leaving the app hidden when storage fails", async () => {
    mock.get.mockRejectedValue(Error("unavailable"));
    await expect(useStore.getState().load()).resolves.toBeUndefined();
    expect(useStore.getState().ready).toBe(true);
    expect(useStore.getState().storageError).toContain("Reload");
  });
  it("does not render malformed persisted preferences or vocabulary", async () => {
    mock.get.mockResolvedValue({
      prefs: { level: "C9", enabled: "yes", aiConsent: 1 },
      words: [
        { id: "bad", text: { unsafe: true } },
        {
          id: "valid",
          text: "salut",
          sentence: "Salut !",
          level: "A1",
          savedAt: 1,
        },
      ],
    });
    await useStore.getState().load();
    expect(useStore.getState().prefs).toEqual(defaults);
    expect(useStore.getState().words.map((w) => w.id)).toEqual(["valid"]);
  });
  it("rolls back and reports a failed preference update without an unhandled rejection", async () => {
    mock.send.mockRejectedValue(Error("worker unavailable"));
    await expect(
      useStore.getState().update({ enabled: false }),
    ).resolves.toBeUndefined();
    expect(useStore.getState().prefs.enabled).toBe(true);
    expect(useStore.getState().storageError).toContain("could not be saved");
  });
  it("reports failed vocabulary deletion while keeping the saved phrase", async () => {
    const word = {
      id: "1",
      text: "salut",
      sentence: "Salut !",
      level: "A1" as const,
      savedAt: 1,
    };
    useStore.setState({ words: [word] });
    mock.send.mockResolvedValue({ error: "quota exceeded" });
    await useStore.getState().remove(word.id);
    expect(useStore.getState().words).toEqual([word]);
    expect(useStore.getState().storageError).toContain("could not be removed");
  });
});
