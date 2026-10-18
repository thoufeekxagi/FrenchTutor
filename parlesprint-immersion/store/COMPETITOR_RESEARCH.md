# Competitor feedback → product changes

Research date: October 17, 2026. Scope: French-first Chrome extension 0.1.0.

## Method and limits

Read the first 10 recent English reviews shown on each live Chrome Web Store review page for Language Reactor, Trancy and eJOY (30 reviews total, including positive reviews). This is a bounded convenience sample, not all reviews and not a representative satisfaction survey. `competitor-feedback.csv` records dates, ratings, paraphrases, themes and primary URLs; no reviewer profile data was collected. Live page ratings differed from indexed search snippets, so no cached aggregate rating is used here. Read the linked public support threads and Language Reactor's actual Get Started page and annotated extension screenshot. Trancy's own guides informed the comparison of sentence controls, lookup and visible setup.

Complaints below are user reports, not independently reproduced defects in competitors. One timing complaint was explicitly marked fixed by its author. The available in-app browser cannot install Chrome extensions and the Mac's native surface was locked. No competitor was installed or runtime-tested; this report distinguishes primary review/documentation inspection from our own extension's browser tests. No competitor login, subscription, posting or data upload was performed.

## Evidence and disposition

| Issue / opportunity | Primary evidence | ParleSprint response | Status / boundary |
|---|---|---|---|
| Subtitle or translation server failures block the whole session | LR store reviews Oct 14, Oct 2 and Sep 16, 2026; [translation failure support thread](https://forum.languagelearningwithnetflix.com/t/language-reactor-failed-to-fetch-translations-on-youtube/33752) | Bundled offline listening sample; explicit local SRT/VTT path; one-click sample from empty companion; server failure leaves replay/saving available | Implemented fallback, not universal automatic-caption parity |
| Repeated login / broken account entry | Trancy Aug 6, 2026; LR Sep 25, 2026 | No account for local practice, highlights or saving; existing password account connection, refresh deduplication and clear sign-out; hide unavailable provider options | Local path and existing password connection verified; cannot promise every account type |
| Language/preferences reset | eJOY Sep 19, 2026; [Chrome community report Jun 15, 2025](https://support.google.com/chrome/thread/350965824/need-help-with-language-reactor-a-google-chrome-extension-program-for-language-learners?hl=en-EN) | French-first scope; persistent validated level, reading size, saved highlighting and left/right position; cross-tab changes retained; per-video timing/import restoration | Implemented; schema migration and browser reload tested |
| Cannot save a short expression without the full sentence | [LR phrase request Mar 31, 2026](https://forum.languagelearningwithnetflix.com/t/allow-manual-selection-of-multi-word-phrases-instead-of-just-full-sentences/39218); [drag-selection thread, latest request Jun 24, 2026](https://forum.languagelearningwithnetflix.com/t/would-love-to-click-and-drag-to-highlight-phrases-to-save/264) | Select a phrase: first/last word, or Shift-click to extend; exact selected phrase saved with full sentence context | Implemented; mouse and keyboard path, repeated words and punctuation tested. Drag gesture is not implemented |
| Saved lists become cluttered and awkward for Anki | Same phrase-selection threads | Save the phrase alone with context; search word/meaning/context without needing accents; free Anki-compatible CSV plus JSON export | Implemented; quoting, multiline and formula-neutralization tests |
| Subtitles vanish before speech finishes | LR Sep 24, 2026 review, later edited to say fixed | Imported cue boundaries remain authoritative; repeat ends at cue boundary and keeps the repeated line visible while paused; manual seek/play clears the hold | Implemented replay hold; cannot correct an inaccurate user-provided subtitle file automatically |
| Learners value efficient sentence navigation | LR Sep 16, 2026 positive review and [official controls guide](https://dev.languagereactor.com/help/basic) | Previous/next sentence, repeat, speed control and keyboard-operable buttons | Implemented. No global hotkeys that interfere with YouTube |
| Word highlighting / karaoke requested | [LR word-timing request Aug 17, 2025](https://forum.languagelearningwithnetflix.com/t/words-in-captions-automatically-highlighted-as-they-are-spoken/33172) | Explicit blue selected range; green dotted-underlined saved words/phrases; text legend and pressed state, larger captions, persistent opt-out | Selection and saved highlighting implemented. Karaoke remains deferred: SRT/VTT has sentence timing, not verified per-word audio alignment |
| More languages, pinyin, RTL rendering | Trancy Oct 11, Sep 30, Aug 29 and Aug 6, 2026 | Product explicitly targets French with English support; preserves French accents, apostrophes, hyphens and occurrence identity | Different scope, not claimed fixed for Arabic/Chinese/Tagalog/Bengali |
| Setup has too many prerequisites | Design observation from competitor setup guides, not a counted review complaint | First install opens ready-to-play offline sample once; no signup gate; YouTube setup is three explicit steps; imported controls collapse so captions take priority | Implemented; install/update/duplicate-event guards tested |
| Overlay feels too branded or takes attention from the video | Direct user feedback during design review, not a competitor review | Remove the wordmark from the watch-page companion; align a compact blue/white caption layer to the player; place setup and study tools behind a small disclosure | Implemented; live YouTube screenshot and narrow-player tests |
| Overlay placement/readability | User request and our own layout review, not a counted competitor complaint | Caption layer follows the video bounds; saved left/right placement remains available; comfortable/large text and timing controls stay under disclosure | Implemented; player resize, small-player, scroll and real YouTube checks |

## Primary pages

- [Language Reactor recent English store reviews](https://chromewebstore.google.com/detail/language-reactor/hoombieeljmmljlkjmnheibnpciblicm/reviews)
- [Trancy recent English store reviews](https://chromewebstore.google.com/detail/trancy-ai-translator-dual/mjdbhokoopacimoekfgkcoogikbfgngb/reviews)
- [eJOY recent English store reviews](https://chromewebstore.google.com/detail/ejoy-ai-dictionary/amfojhdiedpdnlijjbhjnhokbnohfdfb/reviews)
- [Language Reactor annotated UI and setup](https://dev.languagereactor.com/help/basic)
- [Trancy shadowing and sentence workflow](https://www.trancy.org/blog/youtube-shadowing-ab-loop-speak-along-with-trancy-bdf3d4e721a41930391f0494a2a2f980)

## Honest remaining limits

No universal YouTube transcript retrieval, Netflix, automatic audio transcription, verified karaoke word timing, cloud vocabulary sync, or additional target languages. Google/Apple browser login remains configuration-gated. Import matching subtitles you have permission to use. Caption colors indicate selection and notebook state, not inferred CEFR word difficulty, accuracy or mastery. AI explanations can be wrong. We addressed the relevant friction in our supported French flow; we did not claim every competitor complaint or platform is solved.
