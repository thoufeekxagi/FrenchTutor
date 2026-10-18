import "../lib/font";
import { createRoot } from "react-dom/client";
import { createShadowRootUi } from "wxt/utils/content-script-ui/shadow-root";
import { defineContentScript } from "wxt/utils/define-content-script";
import { browser } from "wxt/browser";
import { Immersion } from "../lib/Immersion";
import {
  isCurrentPlaybackTranscript,
  isPlaybackDiscontinuity,
  type PlaybackClock,
} from "../lib/playbackClock";
import "../lib/style.css";
export default defineContentScript({
  matches: ["https://www.youtube.com/watch*", "https://www.youtube.com/shorts/*"],
  cssInjectionMode: "ui",
  async main(ctx) {
    const globalWindow = window as Window & { __parleSprintImmersionLoaded?: boolean };
    if (globalWindow.__parleSprintImmersionLoaded) return;
    globalWindow.__parleSprintImmersionLoaded = true;
    ctx.onInvalidated(() => {
      globalWindow.__parleSprintImmersionLoaded = false;
    });
    let liveCaptureActive = false;
    let currentClock: PlaybackClock | undefined;
    let lastPublishedClock: PlaybackClock | undefined;
    let clockVideo: HTMLVideoElement | null = null;
    let clockTimer: number | undefined;
    let playerObserver: MutationObserver | undefined;
    let observedPlayer: Element | null = null;
    let clockListeners: Array<[string, EventListener]> = [];
    const currentVideoKey = () => {
      const url = new URL(location.href);
      const id = url.searchParams.get("v") || url.pathname.match(/^\/shorts\/([\w-]+)/)?.[1];
      return `youtube:${id || url.pathname}`;
    };
    const adIsShowing = () => {
      const player = document.querySelector<HTMLElement>("#movie_player, .html5-video-player");
      return !!player?.classList.contains("ad-showing");
    };
    const sampleClock = (): PlaybackClock => {
      const video = document.querySelector<HTMLVideoElement>("video");
      const candidate: PlaybackClock = {
        currentTime: Number.isFinite(video?.currentTime) ? Math.max(0, video!.currentTime) : 0,
        paused: video?.paused ?? true,
        muted: !!video && (video.muted || video.volume === 0),
        playbackRate: Number.isFinite(video?.playbackRate) ? video!.playbackRate : 1,
        seeking: video?.seeking ?? false,
        adShowing: adIsShowing(),
        epoch: currentClock?.epoch ?? 0,
        videoKey: currentVideoKey(),
        observedAt: performance.now(),
      };
      if (currentClock && isPlaybackDiscontinuity(currentClock, candidate))
        candidate.epoch = currentClock.epoch + 1;
      currentClock = candidate;
      return candidate;
    };
    const publishClock = (force = false) => {
      const value = sampleClock();
      if (!liveCaptureActive) return value;
      const previous = lastPublishedClock;
      const changed = !previous ||
        Math.abs(value.currentTime - previous.currentTime) >= 0.12 ||
        value.paused !== previous.paused ||
        value.playbackRate !== previous.playbackRate ||
        value.seeking !== previous.seeking ||
        value.adShowing !== previous.adShowing ||
        value.epoch !== previous.epoch ||
        value.videoKey !== previous.videoKey;
      if (force || changed) {
        lastPublishedClock = value;
        void browser.runtime.sendMessage({ type: "live-video-clock", ...value }).catch(() => undefined);
      }
      return value;
    };
    const bindClockVideo = () => {
      const next = document.querySelector<HTMLVideoElement>("video");
      if (next === clockVideo) return;
      for (const [event, listener] of clockListeners)
        clockVideo?.removeEventListener(event, listener);
      clockListeners = [];
      clockVideo = next;
      if (next) {
        for (const event of ["play", "playing", "pause", "ratechange", "volumechange", "timeupdate", "seeking", "seeked", "ended", "loadedmetadata", "durationchange", "emptied", "waiting"]) {
          const listener: EventListener = () => { publishClock(true); };
          next.addEventListener(event, listener);
          clockListeners.push([event, listener]);
        }
      }
      publishClock(true);
    };
    const watchAdClass = () => {
      const player = document.querySelector("#movie_player, .html5-video-player");
      if (player === observedPlayer) return;
      playerObserver?.disconnect();
      observedPlayer = player;
      if (player) {
        playerObserver = new MutationObserver(() => { publishClock(true); });
        playerObserver.observe(player, { attributes: true, attributeFilter: ["class"] });
      }
    };
    const startClockMonitor = () => {
      if (clockTimer !== undefined) return;
      bindClockVideo();
      watchAdClass();
      publishClock(true);
      clockTimer = window.setInterval(() => {
        bindClockVideo();
        watchAdClass();
        publishClock();
      }, 200);
    };
    const stopClockMonitor = () => {
      if (clockTimer !== undefined) window.clearInterval(clockTimer);
      clockTimer = undefined;
      lastPublishedClock = undefined;
    };
    const runtimeListener = (message: unknown) => {
      if (!message || typeof message !== "object") return;
      const data = message as Record<string, unknown>;
      if (data.type === "live-get-clock") {
        bindClockVideo();
        const value = sampleClock();
        return {
          hasVideo: !!clockVideo,
          ...value,
        };
      }
      if (data.type === "live-transcription-status") {
        liveCaptureActive = data.status === "connecting" || data.status === "listening";
        if (liveCaptureActive) startClockMonitor();
        else stopClockMonitor();
      }
      if (data.type === "live-transcription-interim" || data.type === "live-transcription-final") {
        const value = publishClock(true);
        if (!isCurrentPlaybackTranscript(data.epoch, value)) return;
      }
      if (typeof data.type === "string" && data.type.startsWith("live-transcription-")) {
        window.dispatchEvent(new CustomEvent("parlesprint-live-event", { detail: data }));
      }
    };
    browser.runtime.onMessage.addListener(runtimeListener);
    ctx.onInvalidated(() => {
      stopClockMonitor();
      for (const [event, listener] of clockListeners)
        clockVideo?.removeEventListener(event, listener);
      playerObserver?.disconnect();
      browser.runtime.onMessage.removeListener(runtimeListener);
    });
    const ui = await createShadowRootUi(ctx, {
      name: "parlesprint-immersion",
      position: "inline",
      // The host must participate in the page stacking order, not only its child.
      css: ":host{display:block!important;position:relative!important;width:100%!important;z-index:2147483647!important;overflow:visible!important;}:host(.ps-ov){position:absolute!important;inset:0!important;width:100%!important;height:100%!important;pointer-events:none!important;}",
      isolateEvents: true,
      anchor: "body",
      onMount(container) {
        const root = createRoot(container);
        root.render(<Immersion />);
        return root;
      },
      onRemove(root) {
        root?.unmount();
      },
    });
    ui.mount();

    const host = ui.shadowHost;
    type Placement = "side" | "overlay" | "below" | "floating";
    const parsePlacement = (value: unknown): Placement =>
      value === "floating" || value === "overlay" || value === "below" ? value : "side";
    let placement: Placement = "side";
    const placeHost = () => {
      if (placement === "overlay") {
        const player = document.querySelector<HTMLElement>("#movie_player");
        if (player) {
          if (host.parentElement !== player) player.append(host);
          host.classList.add("ps-ov");
          for (const name of ["position", "left", "top", "right", "bottom", "width", "height"])
            host.style.removeProperty(name);
          return;
        }
      }
      host.classList.remove("ps-ov");
      host.style.removeProperty("pointer-events");
      host.style.removeProperty("bottom");
      host.style.removeProperty("right");
      if (placement === "floating") {
        if (host.parentElement !== document.body) document.body.append(host);
        host.style.setProperty("position", "fixed", "important");
        host.style.setProperty("left", "0", "important");
        host.style.setProperty("top", "0", "important");
        host.style.setProperty("width", "0", "important");
        host.style.setProperty("height", "0", "important");
        return;
      }
      if (placement === "side") {
        const column = document.querySelector<HTMLElement>("ytd-watch-flexy #secondary-inner, #secondary-inner");
        if (column) {
          if (host.parentElement !== column || column.firstElementChild !== host) column.prepend(host);
          host.style.setProperty("position", "relative", "important");
          host.style.setProperty("width", "100%", "important");
          host.style.setProperty("height", "auto", "important");
          return;
        }
      }
      host.style.setProperty("position", "relative", "important");
      host.style.setProperty("left", "auto", "important");
      host.style.setProperty("top", "auto", "important");
      host.style.setProperty("width", "100%", "important");
      host.style.setProperty("height", "auto", "important");
      const topRow = document.querySelector<HTMLElement>(
        "ytd-watch-metadata #top-row, #above-the-fold #top-row",
      );
      if (topRow && topRow.parentElement) {
        if (host.previousElementSibling !== topRow) topRow.insertAdjacentElement("afterend", host);
        return;
      }
      const below = document.querySelector<HTMLElement>(
        "ytd-watch-flexy #below, #below",
      );
      // YouTube theater mode absolutely positions its full-bleed player
      // wrapper. Insert before the normal-flow details section so the panel
      // remains below that player in both standard and theater layouts.
      if (below?.parentElement) {
        if (
          host.parentElement !== below.parentElement ||
          host.nextElementSibling !== below
        )
          below.parentElement.insertBefore(host, below);
        return;
      }
      const primary = document.querySelector<HTMLElement>(
        "ytd-watch-flexy #primary-inner, #primary-inner",
      );
      if (primary && document.querySelector("ytd-watch-flexy[theater]")) {
        if (host.parentElement !== primary || host.previousElementSibling !== null)
          primary.prepend(host);
        return;
      }
      const player = document.querySelector<HTMLElement>(
        "ytd-watch-flexy #player-container-outer, #player-container-outer, #player-container",
      );
      if (player?.parentElement &&
          (host.parentElement !== player.parentElement || host.previousElementSibling !== player)) {
        player.insertAdjacentElement("afterend", host);
      } else if (!player && host.parentElement !== document.body) {
        document.body.append(host);
      }
    };
    const refreshPlacement = () => {
      void browser.storage.local.get("prefs").then(({ prefs }) => {
        const value = prefs && typeof prefs === "object"
          ? (prefs as Record<string, unknown>).placement
          : undefined;
        placement = parsePlacement(value);
        placeHost();
      }).catch(placeHost);
    };
    let scheduled = false;
    let settleTimer: number | undefined;
    const schedulePlacement = () => {
      if (scheduled) return;
      scheduled = true;
      const settle = () => {
        if (!scheduled) return;
        scheduled = false;
        if (settleTimer !== undefined) window.clearTimeout(settleTimer);
        settleTimer = undefined;
        placeHost();
      };
      requestAnimationFrame(() => {
        // YouTube applies the theater attribute and swaps player geometry in
        // separate tasks. Wait another frame so the visible wrapper can be
        // selected after its dimensions have settled.
        requestAnimationFrame(settle);
      });
      settleTimer = window.setTimeout(settle, 150);
    };
    const layoutObserver = new ResizeObserver(schedulePlacement);
    const observedLayout = new WeakSet<Element>();
    const observePlayerLayout = () => {
      for (const element of document.querySelectorAll(
        "ytd-watch-flexy #player-full-bleed-container, ytd-watch-flexy #player-container-outer, ytd-watch-flexy #player-container, video",
      )) {
        if (observedLayout.has(element)) continue;
        observedLayout.add(element);
        layoutObserver.observe(element);
      }
    };
    const observer = new MutationObserver(() => {
      observePlayerLayout();
      schedulePlacement();
    });
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["class", "theater"],
    });
    const changed = (changes: Record<string, { newValue?: unknown }>, area: string) => {
      if (area !== "local" || !changes.prefs) return;
      const value = changes.prefs.newValue;
      const next = value && typeof value === "object"
        ? (value as Record<string, unknown>).placement
        : undefined;
      placement = parsePlacement(next);
      placeHost();
    };
    browser.storage.onChanged.addListener(changed);
    window.addEventListener("popstate", schedulePlacement);
    window.addEventListener("resize", schedulePlacement);
    document.addEventListener("yt-navigate-finish", schedulePlacement);
    observePlayerLayout();
    refreshPlacement();
    ctx.onInvalidated(() => {
      observer.disconnect();
      layoutObserver.disconnect();
      browser.storage.onChanged.removeListener(changed);
      window.removeEventListener("popstate", schedulePlacement);
      window.removeEventListener("resize", schedulePlacement);
      document.removeEventListener("yt-navigate-finish", schedulePlacement);
    });
  },
});
