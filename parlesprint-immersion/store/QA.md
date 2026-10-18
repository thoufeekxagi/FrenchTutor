# Release QA record

These are manual checks to perform, not claims of completed testing.

Record: date/time, Chrome version, OS, extension version, site/video URLs, caption source, backend state, pass/fail, screenshots, and issues.

1. Clean install: load `.output/chrome-mv3`, open a French video on YouTube, and click the extension icon. Confirm the consent notice appears before audio capture and the companion loads only once.
2. Live captions: play clear French audio, accept the live-audio notice, choose **Start live captions on this tab**, and verify (a) the video audio remains audible, (b) interim French text appears during speech, (c) final sentences are saved and can be studied/replayed, and (d) stop ends capture and the live WebSocket. Repeat on a non-YouTube video page to verify activeTab injection.
3. Consent and failure states: decline/withdraw consent, use a non-video page, try a Chrome internal page, disconnect the network, exhaust the quota, and deny the provider endpoint. Ensure capture never starts without consent, useful errors appear, and Stop always releases tab audio.
4. Reconnect: leave a video playing across a live-session renewal; confirm captions continue and there is no lingering capture after Stop, closing the tab, or browser exit.
5. Import / page captions: import an authorized matching SRT/VTT only as an optional fallback. Verify accents, apostrophes, multiline cues, and that the upload is not required for normal use. Test exposed browser caption tracks.
6. Controls: pause/play, seek forward/back by 10 and 15 seconds, repeat sentence, timing offset, hide/reveal, A1–B2 modes, enable/disable, and fullscreen. Confirm captions follow the playhead, and replay seeks to the estimated utterance. Check a pre-roll and mid-roll ad: no ad speech should be transcribed or displayed as the video's next line; captions should resume at the post-ad position. Also test player mute/unmute and 1×/2× playback.
7. Selection and storage: select a word and full sentence, save, reopen popup, reload the page, and restart Chrome. Verify transcript/vocabulary persists and remove works. Check duplicate saves and the storage limit.
8. Navigation: use YouTube next/back/forward, a non-watch page, and a second tab. Confirm transcripts remain separated by video page and the companion does not attach twice.
9. Keyboard/layout: reach controls by Tab, activate with keyboard, inspect focus visibility and accessible labels. Test a narrow window, 200% zoom, long captions, and long explanations.
10. Explanation AI: with separate explanation consent, request meaning/grammar/example/translation. Test timeout, offline, server errors, bad response, and quota exhaustion. Confirm local practice remains usable.
11. Privacy/build: inspect production manifest and ZIP. Confirm the API secret is absent; verify only storage/activeTab/scripting/tabCapture/offscreen permissions and the two host origins; verify no microphone permission, accurate free-tier disclosure, and public privacy link.

Use actual extension screenshots from these checks for the store. Record unresolved issues and block submission for broken core paths, misleading disclosures, exposed secrets, or an uncontrolled paid AI endpoint.

## Current run · October 17, 2026

- `npm run check`: strict TypeScript, 87 unit tests, and production build pass in the standalone Desktop folder.
- `npm run test:e2e`: all 15 Chromium flows pass.
- `npm run test:youtube`: the TV5MONDE French video loads and plays; `readyState=4`, 90.7 seconds, and no browser French text track. Companion placement, optional imported timing/replay, and fullscreen hide/restore pass. The test screenshot is `artifacts/live-youtube-panel.png`; it shows the compact live-first UI, not a transcript of the video.
- The extension ZIP has 26 runtime files, no environment files, and no provider/service secret values. The denied-consent endpoint check returns 403 `consent_required` with the expected extension origin. The deployed privacy URL returns 200.
- **Still required before submission:** start live capture from the actual Chrome toolbar popup, confirm French interim/final captions arrive while video audio continues, stop capture, and repeat on one non-YouTube video page. The fresh dedicated Chrome for Testing window is running the standalone Desktop copy at `~/Desktop/ParleSprint-Immersion` on the TV5MONDE video. Its panel says **Live French captions**. Play it, open ParleSprint from the toolbar, accept the audio notice, and press **Start live captions on this tab**. The launcher watches for captions and writes `artifacts/live-transcription-youtube.png` when the first text appears.

The automated live attempt deliberately stopped before audio or token request: Playwright cannot supply Chrome's real action-click permission for `activeTab`/`tabCapture`. It did not consume transcription quota. Do not mark live transcription passed until the manual toolbar start produces actual caption text and Stop releases capture.

## Current run · October 18, 2026 · ad and playhead robustness

- `npm run check`: strict TypeScript, 98 unit tests, and production build pass.
- `npm run test:e2e`: all 19 Chromium tests pass. The new timing regression seeks to 10 and 15 seconds on a 35-second video fixture, checks the corresponding caption, toggles a YouTube-style `#movie_player.ad-showing` marker, and confirms the caption hides and returns at the same playhead.
- `npm run test:youtube` passes on the real French YouTube videos `https://www.youtube.com/watch?v=UwqQbIDVSgE` (5:35) and `https://www.youtube.com/watch?v=D4dpRjd_rYo` (25:54): extension injection, below-player placement, 10s/15s cue timing, ad-marker UI suppression, theater mode, and fullscreen restore. The ad marker was simulated on each real page; neither run claims an actual served ad or live audio transcription. Imported cue text is test data, not a transcript of either video.
- Live tab capture now gates outgoing audio while the video is paused, seeking, muted, or in an ad. Seeks, ad transitions, missed large playhead jumps, and video navigation invalidate the current speech segment so late text from the previous segment is dropped. The extension resumes after the new player position stabilizes.
- **Still unverified:** real Chrome toolbar-started capture through an actual pre-roll/mid-roll ad, actual French interim/final transcription, and Stop releasing capture. The previous activeTab user-gesture limitation still applies; do not mark live capture fully QA-passed until that manual check succeeds.
