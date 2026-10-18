import { beforeEach, describe, expect, it, vi } from "vitest";
import { defaults } from "../lib/types";
const mock = vi.hoisted(() => ({
  data: {} as Record<string, any>,
  changed: undefined as any,
  get: vi.fn(),
  send: vi.fn(),
}));
vi.mock("wxt/browser", () => ({
  browser: {
    runtime: { sendMessage: mock.send },
    storage: {
      local: { get: mock.get },
      onChanged: {
        addListener: (callback: any) => {
          mock.changed = callback;
        },
      },
    },
  },
}));
let store: typeof import("../lib/store").useStore;
beforeEach(async () => {
  vi.resetModules();
  mock.data = {};
  mock.get
    .mockReset()
    .mockImplementation(async () => structuredClone(mock.data));
  mock.send
    .mockReset()
    .mockImplementation(async ({ patch }) => ({
      prefs: { ...defaults, ...patch },
    }));
  store = (await import("../lib/store")).useStore;
});
describe("learner preference hydration and patch safety", () => {
  it("migrates legacy storage to complete defaults without losing valid choices", async () => {
    mock.data.prefs = {
      level: "B2",
      hidden: true,
      enabled: false,
      aiConsent: true,
      offset: 3,
    };
    await store.getState().load();
    expect(store.getState().ready).toBe(true);
    expect(store.getState().prefs).toEqual({
      ...defaults,
      level: "B2",
      hidden: true,
      enabled: false,
      aiConsent: true,
      offset: 3,
    });
    expect(mock.send).not.toHaveBeenCalled();
  });
  it("repairs malformed persisted fields without treating truthy strings as consent", async () => {
    mock.data.prefs = {
      level: {},
      hidden: 1,
      enabled: null,
      aiConsent: "yes",
      offset: Infinity,
      highlightSaved: "false",
      captionSize: "extra-large",
      dock: "top",
      placement: "center",
      floatRect: { left: Infinity, top: "bad", width: -1, height: 2 },
      highlightSpokenWords: "yes",
    };
    await store.getState().load();
    expect(store.getState().prefs).toEqual({
      ...defaults,
      floatRect: { left: 0.54, top: 0.16, width: 0.25, height: 0.85 },
    });
  });
  it("validates storage-change migrations and ignores non-local events", () => {
    mock.changed(
      {
        prefs: {
          newValue: {
            highlightSaved: false,
            captionSize: "large",
            dock: "left",
            offset: -1000,
      placement: "floating",
      floatRect: { left: -2, top: 3, width: 0.1, height: 2 },
          },
        },
      },
      "local",
    );
    expect(store.getState().prefs).toMatchObject({
      highlightSaved: false,
      captionSize: "large",
      dock: "left",
      offset: -600,
      placement: "floating",
      floatRect: { left: 0, top: 0.98, width: 0.25, height: 0.85 },
    });
    mock.changed({ prefs: { newValue: {} } }, "sync");
    expect(store.getState().prefs.captionSize).toBe("large");
    mock.changed({ prefs: { newValue: ["invalid"] } }, "local");
    expect(store.getState().prefs).toEqual(defaults);
  });
  it("filters an invalid patch before optimistic UI state and runtime persistence", async () => {
    store.setState({
      prefs: {
        ...defaults,
        highlightSaved: false,
        captionSize: "large",
        dock: "left",
      },
    });
    let resolve!: (value: unknown) => void;
    mock.send.mockImplementation(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    );
    const task = store
      .getState()
      .update({
        highlightSaved: "bad",
        captionSize: "huge",
        dock: "up",
        placement: "elsewhere",
        offset: 900,
        unknown: true,
      } as any);
    expect(store.getState().prefs).toMatchObject({
      highlightSaved: false,
      captionSize: "large",
      dock: "left",
      offset: 600,
      placement: "side",
    });
    expect(mock.send).toHaveBeenCalledWith({
      type: "update-prefs",
      patch: { offset: 600 },
    });
    resolve({ prefs: store.getState().prefs });
    await task;
    expect(store.getState().storageError).toBe("");
  });
  it("saves all three reading preferences and rolls back on storage failure", async () => {
    await store
      .getState()
      .update({ highlightSaved: false, captionSize: "large", dock: "left" });
    expect(store.getState().prefs).toMatchObject({
      highlightSaved: false,
      captionSize: "large",
      dock: "left",
    });
    const prior = store.getState().prefs;
    mock.send.mockRejectedValue(new Error("storage full"));
    await store
      .getState()
      .update({ captionSize: "comfortable", dock: "right" });
    expect(store.getState().prefs).toEqual(prior);
    expect(store.getState().storageError).toContain("could not be saved");
  });
  it("reports read failures without leaving the UI loading forever", async () => {
    mock.get.mockRejectedValue(new Error("storage unavailable"));
    await store.getState().load();
    expect(store.getState().ready).toBe(true);
    expect(store.getState().storageError).toContain("Could not read");
    expect(store.getState().prefs).toEqual(defaults);
  });
});
