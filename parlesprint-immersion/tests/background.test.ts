import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
const mock = vi.hoisted(() => ({
  data: {} as Record<string, any>,
  listener: undefined as any,
  installListener: undefined as any,
  browser: {
    tabs: { create: vi.fn(async () => ({})) },
    identity: {
      getRedirectURL: (p: string) =>
        `https://extension-id.chromiumapp.org/${p}`,
      launchWebAuthFlow: vi.fn(),
    },
    runtime: {
      id: "extension-id",
      getURL: (p: string) => `chrome-extension://extension-id${p}`,
      onInstalled: {
        addListener: (f: any) => {
          mock.installListener = f;
        },
      },
      onMessage: {
        addListener: (f: any) => {
          mock.listener = f;
        },
      },
    },
    storage: {
      local: {
        get: async (keys: string | string[]) =>
          Object.fromEntries(
            (Array.isArray(keys) ? keys : [keys]).map((k) => [
              k,
              structuredClone(mock.data[k]),
            ]),
          ),
        set: async (values: Record<string, any>) => {
          Object.assign(mock.data, structuredClone(values));
        },
        remove: async (keys: string | string[]) => {
          for (const key of Array.isArray(keys) ? keys : [keys])
            delete mock.data[key];
        },
      },
    },
  },
}));
vi.mock("wxt/browser", () => ({ browser: mock.browser }));
vi.mock("wxt/utils/define-background", () => ({
  defineBackground: (fn: () => void) => fn,
}));
const popup = {
  id: "extension-id",
  url: "chrome-extension://extension-id/popup.html",
};
const explanation = {
  meaning: "Hello",
  grammar: "A greeting",
  example: "Bonjour !",
  exampleTranslation: "Hello!",
};
const session = () => ({
  access_token: "access",
  refresh_token: "refresh",
  expires_at: Date.now() + 3600000,
});
const request = (text = "bonjour") => ({
  type: "explain",
  text,
  sentence: "Bonjour les amis.",
  level: "A1",
});
const send = (message: unknown, sender = popup) =>
  mock.listener(message, sender);
const response = (body: unknown) =>
  new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
  });
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}
beforeEach(async () => {
  vi.resetModules();
  vi.stubEnv("WXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("WXT_PUBLIC_SUPABASE_ANON_KEY", "public-anon");
  vi.stubEnv("WXT_PUBLIC_GOOGLE_OAUTH_ENABLED", "true");
  mock.data = { prefs: { aiConsent: true }, session: session() };
  mock.browser.identity.launchWebAuthFlow.mockReset();
  mock.browser.tabs.create.mockClear();
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => response(explanation)),
  );
  const module = await import("../entrypoints/background");
  (module.default as unknown as () => void)();
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});
describe("background request and account safety", () => {
  it("deduplicates concurrent refreshes and preserves distinct cache writes", async () => {
    mock.data.session.expires_at = 0;
    const refresh = deferred<Response>();
    const fetcher = vi.fn(async (url: string) =>
      url.includes("refresh_token") ? refresh.promise : response(explanation),
    );
    vi.stubGlobal("fetch", fetcher);
    const one = send(request("bonjour"));
    const two = send(request("amis"));
    await vi.waitFor(() => expect(fetcher).toHaveBeenCalledTimes(1));
    refresh.resolve(
      response({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_in: 3600,
      }),
    );
    expect(await one).toEqual({ explanation });
    expect(await two).toEqual({ explanation });
    expect(
      fetcher.mock.calls.filter(([url]) => url.includes("refresh_token")),
    ).toHaveLength(1);
    expect(Object.keys(mock.data.explanationCache)).toHaveLength(2);
    expect(mock.data.session.access_token).toBe("new-access");
  });
  it("translates a sentence once and keeps its local cache separate", async () => {
    const fetcher = vi.fn(async (_url: string, init?: RequestInit) => response({ translation: "Hello there." }));
    vi.stubGlobal("fetch", fetcher);
    const message = {
      type: "translate",
      text: "Bonjour Marie.",
      sentence: "Bonjour Marie.",
      level: "A1",
    };
    expect(await send(message)).toEqual({ translation: "Hello there." });
    expect(await send(message)).toEqual({ translation: "Hello there." });
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(JSON.parse(fetcher.mock.calls[0]![1]!.body as string)).toMatchObject({
      text: "Bonjour Marie.",
      mode: "translation",
    });
    expect(Object.values(mock.data.translationCache)).toEqual(["Hello there."]);
    expect(mock.data.explanationCache).toBeUndefined();
  });
  it("signs out offline and prevents late explanation cache restoration", async () => {
    mock.data.translationCache = { old: "cached" };
    const pending = deferred<Response>();
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) =>
        url.includes("/logout")
          ? Promise.reject(new TypeError("offline"))
          : pending.promise,
      ),
    );
    const task = send(request());
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    expect(await send({ type: "sign-out" })).toEqual({ ok: true });
    expect(mock.data.session).toBeUndefined();
    pending.resolve(response(explanation));
    expect((await task).error).toContain("changed");
    expect(mock.data.explanationCache).toBeUndefined();
    expect(mock.data.translationCache).toBeUndefined();
  });
  it("cannot restore a session when refresh completes after signout", async () => {
    mock.data.session.expires_at = 0;
    const pending = deferred<Response>();
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) =>
        url.includes("/logout")
          ? Promise.resolve(response({}))
          : pending.promise,
      ),
    );
    const task = send(request());
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    await send({ type: "sign-out" });
    pending.resolve(
      response({
        access_token: "late",
        refresh_token: "late",
        expires_in: 3600,
      }),
    );
    expect((await task).error).toContain("changed");
    expect(mock.data.session).toBeUndefined();
    expect(mock.data.explanationCache).toBeUndefined();
  });
  it("deduplicates identical explanations and clears prior account cache on sign-in", async () => {
    const pending = deferred<Response>();
    vi.stubGlobal(
      "fetch",
      vi.fn(() => pending.promise),
    );
    const one = send(request());
    const two = send(request());
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    pending.resolve(response(explanation));
    expect(await one).toEqual({ explanation });
    expect(await two).toEqual({ explanation });
    expect(fetch).toHaveBeenCalledTimes(1);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        response({
          access_token: "other-account",
          refresh_token: "other-refresh",
          expires_in: 3600,
        }),
      ),
    );
    expect(
      await send({
        type: "password",
        email: "user@example.com",
        password: "secret",
      }),
    ).toEqual({ ok: true });
    expect(mock.data.session.access_token).toBe("other-account");
    expect(mock.data.explanationCache).toBeUndefined();
  });
  it("cannot restore authentication when a sign-in finishes after sign-out", async () => {
    const pending = deferred<Response>();
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) =>
        url.includes("/logout")
          ? Promise.resolve(response({}))
          : pending.promise,
      ),
    );
    const task = send({
      type: "password",
      email: "user@example.com",
      password: "secret",
    });
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    expect(await send({ type: "sign-out" })).toEqual({ ok: true });
    pending.resolve(
      response({
        access_token: "late",
        refresh_token: "late",
        expires_in: 3600,
      }),
    );
    expect((await task).error).toContain("changed");
    expect(mock.data.session).toBeUndefined();
  });
  it("keeps the refresh token after a transient offline error", async () => {
    mock.data.session.expires_at = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.reject(new TypeError("offline"))),
    );
    expect((await send(request())).error).toContain("connection");
    expect(mock.data.session.refresh_token).toBe("refresh");
  });
  it("withdrawn consent discards an inflight response", async () => {
    const pending = deferred<Response>();
    vi.stubGlobal(
      "fetch",
      vi.fn(() => pending.promise),
    );
    const task = send(request());
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    await send({ type: "update-prefs", patch: { aiConsent: false } });
    pending.resolve(response(explanation));
    expect((await task).error).toContain("changed");
    expect(mock.data.explanationCache).toBeUndefined();
  });
  it("validates messages, exact popup identity, vocabulary, and malformed storage", async () => {
    expect((await send(null)).error).toContain("Invalid");
    expect(
      (await send({ type: "sign-out" }, { ...popup, url: popup.url + "-fake" }))
        .error,
    ).toContain("popup");
    expect(
      (await send({ type: "verify", email: "a@b.com", token: { bad: true } }))
        .error,
    ).toContain("valid");
    expect(
      (
        await send({
          type: "save-word",
          word: { id: "bad", text: "bonjour", sentence: "bonjour" },
        })
      ).error,
    ).toContain("Invalid");
    mock.data.words = { corrupted: true };
    expect(await send({ type: "remove-word", id: "missing" })).toEqual({
      words: [],
    });
    mock.data.prefs = { level: "C9", aiConsent: "yes", offset: Infinity };
    expect((await send(request())).error).toContain("Allow");
    const prefs = await send({ type: "update-prefs", patch: { hidden: true } });
    expect(prefs.prefs).toMatchObject({
      level: "A1",
      aiConsent: false,
      offset: 0,
      hidden: true,
    });
    mock.data.session = { access_token: "oops" };
    expect(await send({ type: "auth-status" })).toEqual({ linked: false });
    expect(fetch).not.toHaveBeenCalled();
  });
  it("uses valid cached explanations offline and ignores corrupted cache entries", async () => {
    const key = JSON.stringify([4, "explanation", "bonjour", "Bonjour les amis.", "A1"]);
    mock.data.explanationCache = { [key]: explanation };
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.reject(new Error("offline"))),
    );
    expect(await send(request())).toEqual({ explanation });
    expect(fetch).not.toHaveBeenCalled();
    mock.data.explanationCache = { [key]: { meaning: 42 } };
    expect((await send(request())).error).toBe("offline");
  });
});

describe("same-project provider account connection", () => {
  function providers() {
    const fetcher = vi.fn(async (url: string, _init?: RequestInit) =>
      url.includes("/settings")
        ? response({ external: { google: true, apple: true } })
        : response({
            access_token: "oauth-access",
            refresh_token: "oauth-refresh",
            expires_in: 3600,
            user: {
              id: "same-app-user",
              email: "learner@example.com",
              user_metadata: { full_name: "Marie Learner", admin: true },
              app_metadata: { provider: "google" },
            },
          }),
    );
    vi.stubGlobal("fetch", fetcher);
    return fetcher;
  }
  function callback(url: string, change?: (redirect: URL) => void) {
    const authorize = new URL(url);
    const redirect = new URL(authorize.searchParams.get("redirect_to")!);
    redirect.searchParams.set("code", "one-use-authorization-code");
    change?.(redirect);
    return redirect.href;
  }
  it("uses SHA256 PKCE and returns safe account identity without tokens", async () => {
    const fetcher = providers();
    let authorize!: URL;
    mock.browser.identity.launchWebAuthFlow.mockImplementation(
      async ({ url }) => {
        authorize = new URL(url);
        return callback(url);
      },
    );
    expect(await send({ type: "oauth", provider: "google" })).toEqual({
      ok: true,
    });
    expect(authorize.origin).toBe("https://example.supabase.co");
    expect(authorize.pathname).toBe("/auth/v1/authorize");
    expect(authorize.searchParams.get("provider")).toBe("google");
    expect(authorize.searchParams.get("code_challenge_method")).toBe("s256");
    const exchange = fetcher.mock.calls.find(([url]) =>
      url.includes("grant_type=pkce"),
    );
    expect(exchange).toBeDefined();
    const body = JSON.parse((exchange as any)[1].body);
    expect(body.auth_code).toBe("one-use-authorization-code");
    expect(body.code_verifier).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const digest = new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(body.code_verifier),
      ),
    );
    const encoded = btoa(String.fromCharCode(...digest))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    expect(authorize.searchParams.get("code_challenge")).toBe(encoded);
    expect(await send({ type: "auth-status" })).toEqual({
      linked: true,
      account: {
        id: "same-app-user",
        email: "learner@example.com",
        displayName: "Marie Learner",
        provider: "google",
      },
    });
    expect(
      await send(
        { type: "auth-status" },
        { ...popup, url: "https://www.youtube.com/watch" },
      ),
    ).toEqual({ linked: true });
    expect(mock.data.session.account.admin).toBeUndefined();
  });
  it.each([
    "state",
    "origin",
    "path",
    "fragment",
    "duplicate-code",
    "unknown-param",
  ])(
    "rejects a callback with invalid %s before token exchange",
    async (variant) => {
      const fetcher = providers();
      mock.browser.identity.launchWebAuthFlow.mockImplementation(
        async ({ url }) =>
          callback(url, (redirect) => {
            if (variant === "state")
              redirect.searchParams.set("state", "wrong");
            if (variant === "origin") redirect.hostname = "attacker.example";
            if (variant === "path") redirect.pathname += "-fake";
            if (variant === "fragment")
              redirect.hash = "access_token=untrusted";
            if (variant === "duplicate-code")
              redirect.searchParams.append("code", "second");
            if (variant === "unknown-param")
              redirect.searchParams.set("access_token", "untrusted");
          }),
      );
      expect(
        (await send({ type: "oauth", provider: "google" })).error,
      ).toContain("verified");
      expect(
        fetcher.mock.calls.some(([url]) => url.includes("grant_type=pkce")),
      ).toBe(false);
    },
  );
  it("never exposes native-only Apple as a working browser provider", async () => {
    providers();
    expect(await send({ type: "auth-capabilities" })).toMatchObject({
      google: true,
      apple: false,
    });
    expect((await send({ type: "oauth", provider: "apple" })).error).toContain(
      "configuration",
    );
    expect(mock.browser.identity.launchWebAuthFlow).not.toHaveBeenCalled();
  });
  it("cancels safely and does not leak raw browser/provider errors", async () => {
    providers();
    mock.browser.identity.launchWebAuthFlow.mockRejectedValue(
      new Error("private callback secret"),
    );
    const result = await send({ type: "oauth", provider: "google" });
    expect(result.error).toContain("cancelled");
    expect(result.error).not.toContain("private");
    expect(
      await send({ type: "oauth", provider: "not-supported" }),
    ).toMatchObject({ error: expect.any(String) });
  });
  it("sign-out invalidates an open one-use flow and blocks concurrent flows", async () => {
    const fetcher = providers();
    const pending = deferred<string>();
    let url = "";
    mock.browser.identity.launchWebAuthFlow.mockImplementation(
      ({ url: supplied }) => {
        url = supplied;
        return pending.promise;
      },
    );
    const task = send({ type: "oauth", provider: "google" });
    await vi.waitFor(() =>
      expect(mock.browser.identity.launchWebAuthFlow).toHaveBeenCalledTimes(1),
    );
    expect((await send({ type: "oauth", provider: "google" })).error).toContain(
      "already open",
    );
    await send({ type: "sign-out" });
    pending.resolve(callback(url));
    expect((await task).error).toContain("changed");
    expect(mock.data.session).toBeUndefined();
    expect(
      fetcher.mock.calls.some(([url]) => url.includes("grant_type=pkce")),
    ).toBe(false);
  });
  it("requires the exact extension popup to start OAuth", async () => {
    expect(
      (
        await send(
          { type: "oauth", provider: "google" },
          { ...popup, url: popup.url + "-fake" },
        )
      ).error,
    ).toContain("popup");
    expect(mock.browser.identity.launchWebAuthFlow).not.toHaveBeenCalled();
  });
});

describe("provider callback readiness gate", () => {
  it("does not advertise Google until the operator verified its callback allowlist", async () => {
    vi.stubEnv("WXT_PUBLIC_GOOGLE_OAUTH_ENABLED", "false");
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => response({ external: { google: true, apple: true } })),
    );
    expect(await send({ type: "auth-capabilities" })).toMatchObject({
      google: false,
      apple: false,
    });
    expect((await send({ type: "oauth", provider: "google" })).error).toContain(
      "callback",
    );
    expect(mock.browser.identity.launchWebAuthFlow).not.toHaveBeenCalled();
  });
});

describe("OAuth one-use exchange serialization", () => {
  it("blocks another provider flow while the first code is being exchanged", async () => {
    const pending = deferred<Response>();
    vi.stubGlobal(
      "fetch",
      vi.fn((url: string) =>
        url.includes("/settings")
          ? Promise.resolve(response({ external: { google: true } }))
          : pending.promise,
      ),
    );
    mock.browser.identity.launchWebAuthFlow.mockImplementation(
      async ({ url }) => {
        const redirect = new URL(new URL(url).searchParams.get("redirect_to")!);
        redirect.searchParams.set("code", "one-use-code");
        return redirect.href;
      },
    );
    const task = send({ type: "oauth", provider: "google" });
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(2));
    expect((await send({ type: "oauth", provider: "google" })).error).toContain(
      "already open",
    );
    pending.resolve(
      response({
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_in: 3600,
      }),
    );
    expect(await task).toEqual({ ok: true });
  });
});

describe("account connection routing and exact popup trust", () => {
  it("opens the account tab directly from a learning surface", async () => {
    expect(
      await send(
        { type: "open-connection" },
        { ...popup, url: "https://www.youtube.com/watch?v=lesson" },
      ),
    ).toEqual({ ok: true });
    expect(mock.browser.tabs.create).toHaveBeenCalledWith({
      url: popup.url + "#account",
    });
  });
  it("allows only the exact account hash alongside the base popup", async () => {
    expect(
      await send(
        { type: "sign-out" },
        { ...popup, url: popup.url + "#account" },
      ),
    ).toEqual({ ok: true });
  });
  it.each([
    "?account=true",
    "#practice",
    "#account-extra",
    "?x=1#account",
    "/account",
    "#account?x=1",
  ])(
    "rejects account operations from the untrusted popup variant %s",
    async (suffix) => {
      expect(
        (
          await send(
            { type: "sign-out" },
            { ...popup, url: popup.url + suffix },
          )
        ).error,
      ).toContain("popup");
      expect(mock.data.session).toBeDefined();
    },
  );
});

describe("practice setup and preference migration", () => {
  it("opens the fixed local practice target and ignores caller-supplied URLs", async () => {
    expect(
      await send({ type: "open-practice", url: "https://attacker.example" }),
    ).toEqual({ ok: true });
    expect(mock.browser.tabs.create).toHaveBeenCalledWith({
      url: "chrome-extension://extension-id/practice.html",
    });
    expect(fetch).not.toHaveBeenCalled();
  });
  it("opens practice once on first install and never on updates", async () => {
    await mock.installListener({ reason: "update" });
    expect(mock.browser.tabs.create).not.toHaveBeenCalled();
    await Promise.all([
      mock.installListener({ reason: "install" }),
      mock.installListener({ reason: "install" }),
    ]);
    expect(mock.browser.tabs.create).toHaveBeenCalledTimes(1);
    expect(mock.data.firstPracticeOpened).toBe(true);
    await mock.installListener({ reason: "install" });
    expect(mock.browser.tabs.create).toHaveBeenCalledTimes(1);
    expect(fetch).not.toHaveBeenCalled();
  });
  it("migrates old persisted preferences while validating new patches", async () => {
    mock.data.prefs = {
      level: "B1",
      hidden: true,
      offset: 900,
      highlightSaved: "false",
      captionSize: "huge",
      dock: "top",
      aiConsent: "yes",
    };
    const result = await send({
      type: "update-prefs",
      patch: { enabled: false },
    });
    expect(result.prefs).toEqual({
      level: "B1",
      hidden: true,
      enabled: false,
      aiConsent: false,
      offset: 600,
      highlightSaved: true,
      highlightSpokenWords: true,
      captionSize: "comfortable",
      dock: "right",
      placement: "below",
      floatRect: { left: 0.54, top: 0.16, width: 0.4, height: 0.34 },
    });
    expect(mock.data.prefs).toEqual(result.prefs);
    const updated = await send({
      type: "update-prefs",
      patch: { highlightSaved: false, captionSize: "large", dock: "left" },
    });
    expect(updated.prefs).toMatchObject({
      highlightSaved: false,
      captionSize: "large",
      dock: "left",
    });
    const ignored = await send({
      type: "update-prefs",
      patch: {
        highlightSaved: 1,
        captionSize: false,
        dock: "up",
        unknown: "ignored",
      },
    });
    expect(ignored.prefs).toEqual(updated.prefs);
    expect((await send({ type: "update-prefs", patch: [] })).error).toContain(
      "Invalid",
    );
  });
});
