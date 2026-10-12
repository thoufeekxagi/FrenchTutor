#!/usr/bin/env python3
"""Builds ParleSprint_V3_Design_Document.pdf from HTML (Chrome headless).

Run: python3 docs/v3/design/build_design_doc.py
Reference frames live in docs/v3/design/_frames (local only, gitignored).
"""
import base64, subprocess, html
from pathlib import Path

D = Path(__file__).resolve().parent
FR = D / "_frames"
OUT_HTML = D / "_design_doc.html"
OUT_PDF = D / "ParleSprint_V3_Design_Document.pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

C = dict(canvas="#F5F6F8", surface="#FFFFFF", raised="#ECEEF2", text="#14171C", muted="#5F6673",
         line="#E1E4EA", blue="#2563EB", blueDeep="#1D4ED8", soft="#E8EFFE", green="#15803D",
         greenSoft="#E7F6EC", red="#C62828", gold="#B97823", goldSoft="#FFF1CC",
         dCanvas="#08090B", dSurf="#151619", dRaised="#1D1E21", dText="#F7F5F0", dBlue="#6B9BFF")


def img(name):
    p = FR / f"{name}.jpg"
    b = base64.b64encode(p.read_bytes()).decode()
    return f"data:image/jpeg;base64,{b}"


def ref(name, caption):
    app, n = name.split("_")
    return f'<figure><img src="{img(name)}"><figcaption>{app} #{n}<br>{html.escape(caption)}</figcaption></figure>'


def phone(inner, bg=None, dark=False):
    bg = bg or (C["dCanvas"] if dark else C["canvas"])
    return f'<div class="phone" style="background:{bg}">{inner}<div class="home"></div></div>'


def tabbar(active, dark=False):
    items = [("Learn", "&#9632;"), ("Marie", "&#9679;"), ("Tests", "&#9650;"), ("Me", "&#9733;")]
    s = ""
    for name, ico in items:
        on = name == active
        s += f'<div class="tab {"on" if on else ""}"><span>{ico}</span>{name}</div>'
    return f'<div class="tabbar">{s}</div>'


def btn(label, kind="primary"):
    return f'<div class="btn {kind}">{label}</div>'


def card(inner, extra=""):
    return f'<div class="card" style="{extra}">{inner}</div>'


def opt(title, sub="", sel=False):
    cls = "opt sel" if sel else "opt"
    s = f'<div class="{cls}"><b>{title}</b>' + (f"<small>{sub}</small>" if sub else "") + "</div>"
    return s


def page(title, step, refs, wire, change_now, change_new, notes=None):
    refs_html = "".join(refs)
    cn = "".join(f"<li>{x}</li>" for x in change_now)
    nw = "".join(f"<li>{x}</li>" for x in change_new)
    extra = f'<div class="note">{notes}</div>' if notes else ""
    return f"""<section class="page">
<header><span class="step">{step}</span><h2>{title}</h2></header>
<div class="cols">
  <div class="refs"><h4>Reference screens</h4>{refs_html}</div>
  <div class="mock"><h4>ParleSprint v3</h4>{wire}</div>
  <div class="text"><h4>Today in the app</h4><ul>{cn}</ul><h4>V3 decision</h4><ul class="new">{nw}</ul>{extra}</div>
</div></section>"""


pages = []

# ---- Cover
pages.append(f"""<section class="page cover"><div class="coverin">
<div class="eyebrow">DESIGN DOCUMENT  |  V3  |  DRAFT FOR APPROVAL</div>
<h1>ParleSprint v3</h1><p class="lead">A calm, simple, TCF-only French app. This document fixes every screen, the colors and the flow before any code is written.</p>
<div class="three">
<div><b>Who</b><br>Adults preparing for TCF Canada, most starting at A1 or A2, many with a Canadian immigration deadline.</div>
<div><b>Promise</b><br>One clear next step every day, from the first French word to exam day.</div>
<div><b>Feel</b><br>Babbel's calm structure plus Speak's clean lesson screens. Light, spacious, minimal.</div></div>
<p class="small">Reference apps: Speak, Babbel, Vocabulary.com. Frames cited by number come from the screenshot sets in <code>references/</code>. The app name and logo are decided separately.</p>
</div></section>""")

# ---- Principles
pages.append(f"""<section class="page"><header><span class="step">01</span><h2>What we are changing and why</h2></header>
<div class="two">
<div><h4>The problem with the current app</h4><ul>
<li>Home carries a photo hero, three quick-start tiles, a streak card, a course list and explore chips. Five things compete, so the user has to decide.</li>
<li>Navigation has four tabs including "Photo tutor", which has nothing to do with TCF.</li>
<li>Onboarding is eight screens built for a general French learner: goals like travel and culture, six skill focuses, a schedule wheel.</li>
<li>Black and gold. No mention of TCF, NCLC or the exam anywhere.</li></ul></div>
<div><h4>Rules for v3</h4><ul class="new">
<li><b>One question or one action per screen.</b> Speak and Babbel both do this.</li>
<li><b>Four tabs, not five:</b> Learn, Marie, Tests, Me. Babbel uses three, Speak five. We stay between.</li>
<li><b>TCF only.</b> No goal question. Only level and (optionally) exam date.</li>
<li><b>Real data only.</b> No fake progress. Level estimates come from real answers.</li>
<li><b>Reuse existing code:</b> same bundle id, same screens re-skinned and re-ordered, same services (Marie, SRS, sync, RevenueCat). A restructure, not a new app.</li>
<li><b>Light default with a Dark toggle.</b> Babbel's Appearance screen (#175) is the pattern.</li></ul></div></div></section>""")

# ---- Palette
sw = lambda name, hexv, use, light=True: f'<div class="sw"><div class="chip" style="background:{hexv};{"color:#fff" if not light else ""}"></div><b>{name}</b><br><code>{hexv}</code><br><small>{use}</small></div>'
pages.append(f"""<section class="page"><header><span class="step">02</span><h2>Color palette</h2></header>
<div class="two"><div>
<h4>Light (default)</h4><div class="swrow">
{sw("Canvas", C["canvas"], "screen background")}{sw("Surface", C["surface"], "cards, sheets")}{sw("Raised", C["raised"], "inputs, chips")}
{sw("Text", C["text"], "headings, body", False)}{sw("Muted", C["muted"], "secondary text", False)}{sw("Line", C["line"], "dividers")}</div>
<div class="swrow">
{sw("Action blue", C["blue"], "buttons, links, progress", False)}{sw("Blue soft", C["soft"], "selected row")}{sw("Correct green", C["green"], "correct, done", False)}
{sw("Fix red", C["red"], "errors", False)}{sw("Goal gold", C["gold"], "target level only", False)}{sw("Gold soft", C["goldSoft"], "goal tint")}</div>
<h4>Dark (toggle)</h4><div class="swrow">
{sw("Canvas", C["dCanvas"], "black", False)}{sw("Surface", C["dSurf"], "cards", False)}{sw("Raised", C["dRaised"], "inputs", False)}{sw("Text", C["dText"], "on dark")}{sw("Action blue", C["dBlue"], "lighter for contrast")}</div>
</div><div>
<h4>Why these colors (measured)</h4><ul>
<li><b>Speak:</b> almost all white and light gray with one royal blue (#0050FF range) for every action. Its Correct bar is green.</li>
<li><b>Babbel:</b> warm cream canvas, orange primary, black pill buttons, serif headlines.</li>
<li><b>Research:</b> a 2026 study (100 participants; healthcare, finance, education apps) found cool blue/green interfaces gave higher trust, calm and comfort than warm red/orange. TCF is a high-stakes exam.</li></ul>
<h4>Decision</h4><ul class="new"><li>Speak's blue on a neutral white/gray canvas. Babbel's black pill for the secondary action.</li>
<li>Green only for correct. Red only for fix. <b>Gold only for the exam target</b> (continuity with today's brand), never for a button.</li>
<li>Black only appears as text, the secondary pill and Dark mode. Contrast for body text is 4.5:1 or better.</li></ul>
<h4>Type</h4><p>Headings: Plus Jakarta Sans. Body and controls: Inter. Large, calm, plenty of space. (Option: Babbel-style serif for the big onboarding questions only.)</p>
<div class="comp"><div class="btn primary">Primary action</div><div class="btn dark">Secondary</div><div class="btn ghost">Tertiary</div></div>
</div></div></section>""")

# ---- Flow map
steps = ["Launch", "Welcome", "Your level", "Meet Marie (3 min, optional)", "Daily plan", "Plan ready", "Create account", "Free trial", "Learn"]
flow = "".join(f'<div class="fl"><span>{i+1}</span>{s}</div>' for i, s in enumerate(steps))
pages.append(f"""<section class="page"><header><span class="step">03</span><h2>End-to-end flow</h2></header>
<div class="flow">{flow}</div>
<div class="two"><div><h4>Onboarding: 6 screens before the account</h4><ol>
<li>Launch splash</li><li>Welcome: "Pass the TCF Canada."</li><li>Your level (A1 to B2, or "Not sure")</li><li>Meet Marie: optional 3-minute conversation that sets your starting point</li><li>Daily plan: minutes, days, reminder time on one screen</li><li>Plan ready: what you will do first</li></ol>
<p><b>Removed:</b> goal question, skill focus, "when will French fit your life" wheel, separate tutor-pick page (voice moves into Marie's first screen).</p></div>
<div><h4>Main app: four tabs</h4><ul><li><b>Learn</b> (Today + Path)</li><li><b>Marie</b> (live tutor)</li><li><b>Tests</b> (TCF mock exams and results)</li><li><b>Me</b> (progress, review stats, settings, dark mode)</li></ul>
<p>Review lives on Learn as a card ("Time to review"), as Babbel does, not as its own tab.</p>
<h4>Existing code that is reused</h4><ul><li>Auth gate order: onboarding, AI consent, sign-in, main (same logic, new screens).</li><li>Marie Live, lesson renderers, SRS, sync, RevenueCat, settings storage.</li></ul></div></div></section>""")

# ---- 1 Launch
w = phone(f'<div style="height:100%;background:{C["blue"]};display:flex;align-items:center;justify-content:center;flex-direction:column;color:#fff"><div style="font:700 30px Inter">ParleSprint</div><div style="font:500 13px Inter;opacity:.85;margin-top:8px">TCF Canada prep</div></div>', bg=C["blue"])
pages.append(page("Launch screen", "04", [ref("Speak_0", "solid blue, one wordmark"), ref("Babbel_0", "type-only splash")], w,
  ["Dark splash with logo tile and tagline."], ["One solid action-blue screen, white wordmark, 'TCF Canada prep' under it. About one second, then Welcome.", "Logo and final name are separate work; the layout works with any wordmark."]))

# ---- 2 Welcome
w = phone(f'''<div class="pad" style="display:flex;flex-direction:column;height:100%;padding-top:48px">
<div class="eyebrow2">PARLESPRINT</div><h3 style="font:700 30px/1.1 Inter;margin:14px 0 10px">Pass the<br>TCF Canada.</h3>
<p class="muted" style="font-size:14px;line-height:1.45">A clear daily plan from your first French word to exam day.</p>
<div class="chips"><span>Listening</span><span>Reading</span><span>Writing</span><span>Speaking</span></div>
<div style="flex:1"></div>{btn("Get started")}<div class="link">I already have an account</div></div>''')
pages.append(page("Welcome", "05", [ref("Babbel_0", "big confident headline"), ref("Speak_18", "tutor greeting, single button")], w,
  ["'French for real conversations', 'Build my plan', Speak/Listen/Read/Write line."],
  ["Headline names the exam. The four chips are the four real TCF tests.", "One button. 'I already have an account' goes to sign-in."]))

# ---- 3 Level
w = phone(f'''<div class="pad" style="padding-top:40px"><div class="prog"><i style="width:30%"></i></div>
<h3 class="q">How much French do you know?</h3><p class="muted s">We will start you in the right place.</p>
{opt("A1  Starting from zero","I can say hello and a few words", True)}{opt("A2  I know the basics","Simple phrases and daily needs")}{opt("B1  I can hold a conversation","Familiar topics, some mistakes")}{opt("B2  I am close to exam level","I need TCF practice and speed")}
<div class="link" style="margin-top:6px">Not sure? Let Marie check</div>
<div style="position:absolute;left:18px;right:18px;bottom:30px">{btn("Continue")}</div></div>''')
pages.append(page("Your level", "06", [ref("Speak_156", "level picker with plain A1 line"), ref("Speak_12", "list + sticky Continue")], w,
  ["Level was step 4 of 8, after goal and focus questions."],
  ["This is the only required question. Four cards with plain-English descriptions. 'Not sure' jumps to Marie's 3-minute check.", "Selecting A1 skips nothing; it only sets where Learn starts."]))

# ---- 4 Meet Marie
w = phone(f'''<div class="pad" style="padding-top:40px"><div class="prog"><i style="width:55%"></i></div>
<div class="bot"><div class="av"></div><div class="bubble">Bonjour! I am Marie. Want a quick 3-minute chat so I can find your level?</div></div>
<div style="margin-top:18px">{opt("Yes, 3 minutes", "Speak with Marie. No pressure.", True)}{opt("Skip for now","Start from the level I picked")}</div>
<div class="muted s" style="margin-top:14px">Your voice is sent to Google to run the conversation. You can change tutors later.</div>
<div style="position:absolute;left:18px;right:18px;bottom:30px">{btn("Start")}</div></div>''')
pages.append(page("Meet Marie (optional, 3 minutes)", "07", [ref("Speak_18", "tutor bubble opens the chat"), ref("Speak_84", "warm-up conversation with hints")], w,
  ["Eight-step flow had a separate tutor page and a separate '3 minute' page."],
  ["One screen offers the 3-minute check; it opens the existing Marie Live calibration. Skippable.", "Voice choice (Marie, Julien, Camille, Mathieu) appears inside the call and in Me, not as its own onboarding step.", "AI consent text stays and names Google (App Review requirement)."]))

# ---- 5 Daily plan
w = phone(f'''<div class="pad" style="padding-top:40px"><div class="prog"><i style="width:75%"></i></div>
<h3 class="q">Set your study rhythm</h3><p class="muted s">Short and regular beats long and rare.</p>
<div class="lab">Minutes per day</div><div class="row3">{"".join(f'<div class="pill {"on" if m=="15" else ""}">{m}</div>' for m in ["5","10","15","20"])}</div>
<div class="lab">Days</div><div class="row7">{"".join(f'<div class="day {"on" if d in "MTWTF" else ""}">{d}</div>' for d in "MTWTFSS")}</div>
<div class="lab">Reminder</div><div class="field">7:00 PM</div>
<div class="lab">Exam date (optional)</div><div class="field muted">Add date</div>
<div style="position:absolute;left:18px;right:18px;bottom:30px">{btn("Continue")}</div></div>''')
pages.append(page("Daily plan", "08", [ref("Babbel_65", "days + time + one Confirm")], w,
  ["Separate screens for session length, preferred days and a reminder wheel."],
  ["One screen: minutes, days, reminder time, optional exam date. The exam date powers the countdown on Learn.", "Notification permission is requested here, in context."]))

# ---- 6 Plan ready
w = phone(f'''<div class="pad" style="padding-top:60px;text-align:center"><div class="ring">&#10003;</div>
<h3 class="q" style="text-align:center">Your plan is ready</h3>
{card('<div class="kv"><span>Starting level</span><b>A1</b></div><div class="kv"><span>Target</span><b style="color:#B97823">NCLC 7</b></div><div class="kv"><span>Daily</span><b>15 min, 5 days</b></div><div class="kv"><span>First lesson</span><b>Sounds and spelling</b></div>')}
<p class="muted s" style="margin-top:12px">Everything is fixed and in order. No surprises.</p>
<div style="position:absolute;left:18px;right:18px;bottom:30px">{btn("Create my account")}</div></div>''')
pages.append(page("Plan ready", "09", [ref("Speak_102", "'creating your lessons' moment"), ref("Babbel_50", "course + first lesson")], w,
  ["'Creating your first lessons...' spinner with a summary card."],
  ["A calm confirmation with four real facts. Target shows NCLC 7 in gold (the common immigration bar) and can be changed in Me.", "Button leads to account creation. The lessons are authored, so there is no generation wait."]))

# ---- 7 Account
w = phone(f'''<div class="pad" style="padding-top:60px"><h3 class="q">Save your progress</h3><p class="muted s">Create an account to keep your plan on every device.</p>
<div style="margin-top:18px">{btn("Continue with Apple","dark")}<div style="height:10px"></div>{btn("Continue with Google","ghost")}<div style="height:10px"></div>{btn("Continue with email")}</div>
<p class="muted s" style="margin-top:16px;text-align:center">By continuing you agree to the Terms and Privacy Policy.</p></div>''')
pages.append(page("Create account", "10", [ref("Speak_6", "email, Google, Apple stack")], w,
  ["Existing sign-in screen (kept), dark styling."],
  ["Same logic and order (consent, then sign-in). Restyled to Speak's stack: Apple and Google first on iPhone.", "Terms and Privacy links stay visible (App Review)."]))

# ---- 8 Paywall
w = phone(f'''<div class="pad" style="padding-top:34px"><h3 class="q" style="font-size:22px">Reach your TCF target</h3>
{card('<div class="kv"><span>Full A1 to B2 course</span><b>&#10003;</b></div><div class="kv"><span>TCF mock exams</span><b>&#10003;</b></div><div class="kv"><span>Marie live tutor</span><b>&#10003;</b></div><div class="kv"><span>Your level estimate</span><b>&#10003;</b></div>')}
<div class="plans"><div class="plan">Monthly<b>$24.99</b></div><div class="plan on">Annual<b>$79.99</b><small>billed yearly</small></div></div>
<div class="tl"><div><i></i>Today: free trial starts</div><div><i></i>Day 5: reminder before it ends</div><div><i></i>Day 7: billed $79.99/yr, cancel anytime</div></div>
<div style="position:absolute;left:18px;right:18px;bottom:30px">{btn("Start 7-day free trial")}<div class="link">Restore purchase | Terms | Privacy</div></div></div>''')
pages.append(page("Free trial and plans", "11", [ref("Speak_30", "feature checklist + 'No payment due now'"), ref("Babbel_40", "plan cards, big price"), ref("Vocabulary_16", "trial timeline")], w,
  ["Existing paywall: total price dominant (passed review). Black and gold."],
  ["Keep what passed review: total billed amount shown prominently, trial wording subordinate, Restore, Terms, Privacy.", "Add Vocabulary.com's three-step trial timeline for trust. Prices shown are placeholders to be tested in RevenueCat.", "Free tier: Stage 0 sounds, A1 Unit 1, one TCF listening set and a first level estimate. The paywall appears after the first win, not before."]))

# ---- 9 Learn
w = phone(f'''<div class="pad" style="padding-top:34px"><div class="top"><b style="font-size:20px">Hi, Thoufeek</b><span class="lvl">A1</span></div>
<div class="seg"><span class="on">Today</span><span>Path</span></div>
{card('<div class="muted s">EXAM IN 64 DAYS</div><div class="bar"><i style="width:18%"></i></div><div class="s">Reading A1 &#8594; target NCLC 7</div>',"margin-top:12px")}
<div class="hero"><div class="s" style="opacity:.9">Next | 8 min</div><h3 style="margin:6px 0 4px;font:700 20px Inter">Unit 1: Introduce yourself</h3><div class="s" style="opacity:.9">Lesson 3 of 6: Words</div><div class="btn white" style="margin-top:14px">Start lesson</div></div>
{card('<b>Time to review</b><div class="muted s">12 words due</div>',"margin-top:10px")}
</div>{tabbar("Learn")}''')
pages.append(page("Learn (home)", "12", [ref("Babbel_70", "one hero lesson card"), ref("Babbel_90", "review reuses the same card"), ref("Speak_78", "level chip + active lesson")], w,
  ["Photo hero, three quick tiles, streak card, course list, explore chips."],
  ["One hero card: the next lesson, how long, why. Below it a quiet review card. That is the whole screen.", "Header: greeting, level chip. Top of Today shows the exam countdown and level vs target (real data; hidden until set).", "Today / Path toggle as in Babbel. No streak shaming; a small weekly dot row can live in Me."]))

# ---- 10 Path
w = phone(f'''<div class="pad" style="padding-top:34px"><div class="top"><b style="font-size:20px">Hi, Thoufeek</b><span class="lvl">A1</span></div>
<div class="seg"><span>Today</span><span class="on">Path</span></div>
<div class="chiprow"><span class="on">A1</span><span>A2</span><span>B1</span><span>B2</span></div>
{card('<b>Unit 1</b> Introduce yourself<div class="muted s">6 lessons | done</div>','border-left:4px solid #15803D')}
{card('<b>Unit 2</b> Greet, be polite, spell your name<div class="muted s">6 lessons | 2 of 6</div>','border-left:4px solid #2563EB;margin-top:8px')}
{card('<b>Unit 3</b> Forms and papers<div class="muted s">locked until Unit 2</div>','margin-top:8px;opacity:.65')}
{card('<b>Unit 4</b> Family and people','margin-top:8px;opacity:.5')}
</div>{tabbar("Learn")}''')
pages.append(page("Learn: Path", "13", [ref("Babbel_50", "CEFR chip + lesson cards"), ref("Speak_36", "unit labels")], w,
  ["Course tab with a long mixed list."],
  ["Stages as chips (S0, A1, A2, B1, B2). Units as rows with state: done, current, locked. Tapping a unit shows its 6 lessons.", "Every unit says what you will be able to do (from the syllabus 'can_do')."]))

# ---- 11 Lesson player
w = phone(f'''<div class="pad" style="padding-top:38px"><div class="lessontop"><span>&#10005;</span><div class="prog" style="flex:1"><i style="width:45%"></i></div></div>
<p class="muted s" style="margin-top:20px">Choose the meaning</p><h3 style="font:700 26px Inter;margin:6px 0 14px">&#128266; Bonjour</h3>
{opt("Goodbye")}{opt("Hello", "", True)}{opt("Thank you")}
<div class="fb"><div class="ok">Correct!</div><div class="s">Bonjour = hello, any time before evening.</div>{btn("Continue")}</div></div>''')
pages.append(page("Lesson player", "14", [ref("Speak_144", "green Correct panel + Continue"), ref("Speak_150", "Check button"), ref("Babbel_80", "halfway card"), ref("Babbel_75", "picture choice")], w,
  ["Many lesson screens, each with its own look."],
  ["One shared player: thin blue progress bar and X, one instruction, big answer cards, bottom feedback bar (green Correct, red Not quite with the answer).", "Speaker button on every French line plays the baked tutor audio. 'Ask Marie' is always one tap away.", "A 'You are halfway' card appears mid-lesson (Babbel #80), no confetti."]))

# ---- 12 Lesson result
w = phone(f'''<div class="pad" style="padding-top:60px;text-align:center"><div class="muted s">Lesson complete</div><h3 style="font:700 44px Inter;margin:6px 0">8 / 10</h3>
{card('<b style="color:#C62828">Review these</b><div class="s">Bonsoir | Enchanté</div>',"text-align:left;margin-top:14px")}
{card('<b style="color:#15803D">Got it</b><div class="s">Bonjour | Salut | Merci | ...</div>',"text-align:left;margin-top:8px")}
<div style="position:absolute;left:18px;right:18px;bottom:30px">{btn("Next: Words (2 of 2)")}</div></div>''')
pages.append(page("Lesson result", "15", [ref("Babbel_120", "answered correctly, lists")], w,
  ["Generic completion screen."],
  ["Score plus two lists: review these, got it. Missed items go into Review automatically. One button to the next lesson."]))

# ---- 13 Marie
w = phone(f'''<div style="height:100%;background:linear-gradient(#1b2a52,#08090B);color:#fff;padding:40px 16px 20px;position:relative">
<div style="display:flex;justify-content:space-between;font-size:12px;opacity:.85"><span>&#10005;</span><span>Unit 1 | Introduce yourself</span><span>&#9881;</span></div>
<div class="av big"></div><div style="text-align:center;font:600 13px Inter;margin-top:6px">Marie</div>
<div class="sub">Bonjour! Comment vous appelez-vous?<small>Hello! What is your name?</small></div>
<div class="hint">Say: Je m'appelle ...</div>
<div class="mic"></div><div style="text-align:center;font-size:11px;opacity:.8;margin-top:8px">Tap and speak</div></div>''', bg="#08090B")
pages.append(page("Marie (live tutor)", "16", [ref("Speak_180", "tutor full-screen, subtitles, mic"), ref("Speak_186", "hint pill"), ref("Speak_96", "Beginner Mode sheet"), ref("Speak_120", "tap a word for meaning")], w,
  ["Several separate live entry points and tutor screens."],
  ["One Marie screen with three modes: Practise this lesson, Exam examiner (TCF speaking tasks), Ask anything.", "Beginner Mode, translations and slow audio live in a settings sheet (Speak #96). Tapping a word opens a meaning sheet (Speak #120).", "Corrections appear as cards after a turn: what you said, the better version, why."]))

# ---- 14 Review
w = phone(f'''<div class="pad" style="padding-top:34px"><div class="top"><b style="font-size:22px">Review</b></div>
<div class="hero" style="background:#2563EB"><h3 style="font:700 20px Inter">Time to review</h3><div class="s" style="opacity:.9">12 words due | 4 min</div><div class="btn white" style="margin-top:12px">Start review</div></div>
{card('<b>Your words</b><div class="muted s">86 learned | 12 due</div>',"margin-top:10px")}
{card('<b>Mistakes</b><div class="muted s">14 to fix</div>',"margin-top:8px")}
</div>{tabbar("Learn")}''')
pages.append(page("Review", "17", [ref("Speak_210", "review ready + mastery"), ref("Babbel_110", "your vocabulary + collections"), ref("Babbel_115", "flashcard")], w,
  ["Review mixed into several labs."],
  ["Not a tab: a card on Learn plus this screen. One 'Start review' button. Spaced repetition decides what is due.", "Words card lists everything learned. Mistakes lists items you missed in lessons and mocks."]))

# ---- 15 Tests
w = phone(f'''<div class="pad" style="padding-top:34px"><div class="top"><b style="font-size:22px">TCF mock tests</b></div>
{card('<b>Full mock</b><div class="muted s">Listening, Reading, Writing, Speaking | 2h47</div><div class="btn primary sm">Start</div>',"margin-top:10px")}
{card('<b>Listening</b> 39 questions, 35 min<div class="muted s">One play. No going back.</div>',"margin-top:8px")}
{card('<b>Reading</b> 39 questions, 60 min',"margin-top:8px")}
{card('<b>Writing</b> 3 tasks, 60 min',"margin-top:8px")}
{card('<b>Speaking</b> 3 tasks, 12 min | with Marie',"margin-top:8px")}
</div>{tabbar("Tests")}''')
pages.append(page("Tests (mock exams)", "18", [ref("Vocabulary_88", "test score screen"), ref("Babbel_120", "results lists")], w,
  ["Speaking mock only, inside exam readiness."],
  ["New tab. Format is exact TCF Canada: 39 questions in 35 min (listening, one play), 39 in 60 (reading), 3 writing tasks in 60, 3 speaking tasks in 12.", "During a test: timer, question X of 39, no hints. Results screen: estimated level per skill, weak topics, a 'fix plan' that adds lessons to Learn.", "Free users get a short sample set. A level estimate is labelled an estimate."]))

# ---- 16 Me
w = phone(f'''<div class="pad" style="padding-top:34px"><div class="top"><b style="font-size:22px">Me</b></div>
{card('<b>Estimated level</b><div class="bars"><div><span>Listening</span><i style="width:25%"></i></div><div><span>Reading</span><i style="width:30%"></i></div><div><span>Writing</span><i style="width:15%"></i></div><div><span>Speaking</span><i style="width:20%"></i></div></div><div class="s" style="color:#B97823">Target NCLC 7</div>',"margin-top:10px")}
{card('<div class="kv"><span>Weekly goal</span><b>3 of 5 days</b></div><div class="kv"><span>Review score</span><b>82%</b></div>',"margin-top:8px")}
{card('<div class="kv"><span>Dark mode</span><span class="tog"></span></div><div class="kv"><span>Tutor voice</span><b>Marie</b></div><div class="kv"><span>Membership</span><b>&#8250;</b></div>',"margin-top:8px")}
</div>{tabbar("Me")}''')
pages.append(page("Me: progress and settings", "19", [ref("Babbel_155", "weekly goal + reviews"), ref("Babbel_160", "simple settings list"), ref("Babbel_175", "Appearance: Light / Dark"), ref("Speak_96", "tutor settings")], w,
  ["Separate profile, progress, history and settings screens."],
  ["One tab: estimated level per skill against target (real data only), weekly goal, review score, then settings.", "Dark mode toggle lives here, as a row (key 'settings.darkMode', already built).", "Account, membership, privacy and AI, delete account stay (App Review)."]))

# ---- Build/risk page
pages.append(f"""<section class="page"><header><span class="step">20</span><h2>Build plan and App Review safety</h2></header>
<div class="two"><div><h4>Order of work (after you approve this document)</h4><ol>
<li>Theme: palette and toggle (already started in code, light default).</li>
<li>Shell: four-tab navigation and the launch screen.</li>
<li>Onboarding: six screens, reusing the existing profile save, consent and auth gate.</li>
<li>Learn: Today and Path using the authored syllabus.</li>
<li>Lesson player: one shared player, speaker button, Ask Marie.</li>
<li>Marie, Review, Tests, Me, Paywall.</li>
<li>Each step proven on the iPhone with the probe and screenshots.</li></ol></div>
<div><h4>How we avoid rejection</h4><ul class="new">
<li>Same bundle id, same subscription products, same sign-in and consent order.</li>
<li>Keep: Restore purchase, Terms, Privacy, account deletion, AI consent naming Google, support contact.</li>
<li>Paywall keeps the total price as the dominant number.</li>
<li>Review notes will list exactly what changed: refocused on TCF Canada exam prep, new onboarding and navigation, mock exams.</li>
<li>Store screenshots and subtitle must match these screens. No "official", no score guarantees.</li></ul>
<h4>Decisions needed from you</h4><ul><li>Accent: Speak-style blue (proposed) or another.</li><li>Four tabs as drawn (Learn, Marie, Tests, Me)?</li><li>Keep the optional Marie 3-minute check in onboarding?</li><li>Show NCLC 7 as the default target?</li></ul></div></div></section>""")

CSS = f"""
@page {{ size: 1123px 794px; margin:0 }}
*{{box-sizing:border-box}} body{{margin:0;font-family:Inter,-apple-system,Helvetica,Arial,sans-serif;color:{C['text']};background:#fff}}
.page{{width:1123px;height:794px;padding:34px 42px;page-break-after:always;overflow:hidden;position:relative}}
header{{display:flex;align-items:center;gap:14px;margin-bottom:14px}} header h2{{font-size:26px;margin:0}}
.step{{background:{C['blue']};color:#fff;border-radius:8px;padding:4px 10px;font-weight:700;font-size:14px}}
h4{{font-size:11px;letter-spacing:.8px;text-transform:uppercase;color:{C['muted']};margin:10px 0 6px}}
.cols{{display:grid;grid-template-columns:230px 300px 1fr;gap:26px;height:690px}}
.refs{{display:flex;flex-wrap:wrap;gap:8px;align-content:flex-start}} .refs h4{{width:100%;margin-top:0}}
figure{{margin:0;width:105px}} figure img{{width:105px;border-radius:8px;border:1px solid {C['line']}}} figcaption{{font-size:9px;color:{C['muted']};line-height:1.25;margin-top:3px}}
.refs:has(figure:nth-of-type(3)) figure{{width:105px}}
.mock{{display:flex;flex-direction:column;align-items:center}}
.phone{{width:270px;height:560px;border-radius:34px;border:8px solid #111;position:relative;overflow:hidden;box-shadow:0 8px 24px rgba(0,0,0,.18)}}
.home{{position:absolute;bottom:6px;left:50%;margin-left:-45px;width:90px;height:4px;border-radius:3px;background:#111;opacity:.5}}
.pad{{padding:0 18px;position:relative;height:100%}} .muted{{color:{C['muted']}}} .s{{font-size:12px;line-height:1.4}} small{{font-size:11px;color:{C['muted']}}}
.q{{font:700 24px/1.15 Inter;margin:18px 0 6px}} .eyebrow2{{font:700 11px Inter;letter-spacing:2px;color:{C['blue']}}}
.btn{{border-radius:14px;padding:14px;text-align:center;font:600 14px Inter}} .btn.primary{{background:{C['blue']};color:#fff}}
.btn.dark{{background:#111;color:#fff}} .btn.ghost{{background:#fff;border:1px solid {C['line']};color:{C['text']}}} .btn.white{{background:#fff;color:{C['text']};display:inline-block;padding:9px 18px;border-radius:20px}}
.btn.sm{{display:inline-block;padding:8px 18px;margin-top:8px;border-radius:20px}}
.link{{text-align:center;color:{C['blue']};font:600 12px Inter;margin-top:10px}}
.card{{background:#fff;border-radius:16px;padding:12px 14px;border:1px solid {C['line']};font-size:13px}}
.opt{{background:#fff;border:1.5px solid {C['line']};border-radius:14px;padding:12px 14px;margin-top:9px;font-size:13px}} .opt b{{display:block}} .opt.sel{{border-color:{C['blue']};background:{C['soft']}}}
.prog{{height:5px;border-radius:3px;background:{C['raised']};overflow:hidden}} .prog i{{display:block;height:100%;background:{C['blue']}}}
.chips{{margin-top:16px;display:flex;flex-wrap:wrap;gap:6px}} .chips span{{background:{C['soft']};color:{C['blue']};border-radius:20px;padding:5px 11px;font:600 11px Inter}}
.lab{{font:700 11px Inter;margin:14px 0 6px;color:{C['muted']}}} .row3{{display:flex;gap:6px}} .pill{{flex:1;text-align:center;background:#fff;border:1px solid {C['line']};border-radius:10px;padding:8px;font-size:13px}} .pill.on,.day.on{{background:{C['blue']};color:#fff;border-color:{C['blue']}}}
.row7{{display:flex;gap:5px}} .day{{flex:1;text-align:center;background:#fff;border:1px solid {C['line']};border-radius:8px;padding:7px 0;font-size:12px}} .field{{background:#fff;border:1px solid {C['line']};border-radius:10px;padding:10px;font-size:13px}}
.kv{{display:flex;justify-content:space-between;padding:6px 0;font-size:13px;border-bottom:1px solid {C['line']}}} .kv:last-child{{border:0}}
.ring{{width:60px;height:60px;border-radius:30px;background:{C['greenSoft']};color:{C['green']};font:700 28px/60px Inter;margin:0 auto}}
.bot{{display:flex;gap:10px;margin-top:20px}} .av{{width:40px;height:40px;border-radius:20px;background:{C['blue']};flex:none}} .av.big{{width:90px;height:90px;border-radius:45px;margin:26px auto 0;background:#4d79d6}}
.bubble{{background:#fff;border:1px solid {C['line']};border-radius:14px;padding:10px 12px;font-size:13px;line-height:1.4}}
.plans{{display:flex;gap:8px;margin-top:12px}} .plan{{flex:1;background:#fff;border:1.5px solid {C['line']};border-radius:12px;padding:10px;font-size:12px}} .plan b{{display:block;font-size:20px}} .plan.on{{border-color:{C['blue']};background:{C['soft']}}}
.tl{{font-size:11px;margin-top:12px;line-height:2}} .tl i{{display:inline-block;width:8px;height:8px;border-radius:4px;background:{C['blue']};margin-right:8px}}
.top{{display:flex;justify-content:space-between;align-items:center}} .lvl{{background:{C['soft']};color:{C['blue']};border-radius:14px;padding:3px 10px;font:700 12px Inter}}
.seg{{display:flex;gap:18px;margin-top:10px;font:600 13px Inter;color:{C['muted']}}} .seg .on{{color:{C['text']};border-bottom:2px solid {C['text']};padding-bottom:4px}}
.bar{{height:6px;border-radius:3px;background:{C['raised']};margin:8px 0;overflow:hidden}} .bar i{{display:block;height:100%;background:{C['gold']}}}
.hero{{background:{C['blue']};color:#fff;border-radius:18px;padding:16px;margin-top:10px}}
.chiprow{{display:flex;gap:6px;margin:12px 0}} .chiprow span{{background:#fff;border:1px solid {C['line']};border-radius:16px;padding:4px 12px;font:600 12px Inter}} .chiprow .on{{background:{C['text']};color:#fff}}
.tabbar{{position:absolute;bottom:0;left:0;right:0;height:62px;background:#fff;border-top:1px solid {C['line']};display:flex;padding-bottom:12px}}
.tab{{flex:1;text-align:center;font:600 10px Inter;color:{C['muted']};padding-top:8px}} .tab span{{display:block;font-size:15px}} .tab.on{{color:{C['blue']}}}
.lessontop{{display:flex;gap:12px;align-items:center;color:{C['muted']}}}
.fb{{position:absolute;left:0;right:0;bottom:0;background:{C['greenSoft']};padding:14px 18px 26px}} .fb .ok{{color:{C['green']};font:700 17px Inter}} .fb .btn{{background:{C['green']};color:#fff;margin-top:8px}}
.sub{{background:rgba(255,255,255,.14);border-radius:14px;padding:12px;margin-top:16px;font-size:14px;text-align:center}} .sub small{{display:block;color:#cdd7f5;margin-top:4px}}
.hint{{background:#fff;color:#14171C;border-radius:20px;padding:7px 12px;margin:14px auto 0;width:max-content;font-size:12px}}
.mic{{width:64px;height:64px;border-radius:32px;background:{C['blue']};margin:20px auto 0;box-shadow:0 0 0 8px rgba(37,99,235,.25)}}
.bars div{{margin:6px 0;font-size:11px}} .bars span{{display:block;margin-bottom:2px}} .bars i{{display:block;height:6px;border-radius:3px;background:{C['blue']}}}
.tog{{width:36px;height:20px;border-radius:10px;background:{C['blue']};display:inline-block}}
.text ul{{padding-left:16px;margin:0;font-size:12.5px;line-height:1.5}} .text li{{margin-bottom:6px}} ul.new li::marker{{color:{C['blue']}}} ul.new{{font-weight:500}}
.note{{margin-top:8px;background:{C['soft']};border-radius:10px;padding:8px 10px;font-size:11px}}
.two{{display:grid;grid-template-columns:1fr 1fr;gap:34px}} .two ul,.two ol{{font-size:13px;line-height:1.55;padding-left:18px}} .two li{{margin-bottom:6px}}
.swrow{{display:flex;gap:10px;margin-bottom:8px}} .sw{{width:112px;font-size:11px;line-height:1.35}} .chip{{height:54px;border-radius:10px;border:1px solid {C['line']};margin-bottom:5px}}
.comp{{display:flex;gap:10px;margin-top:10px}} .comp .btn{{padding:10px 16px}}
.cover{{background:linear-gradient(135deg,{C['blue']},#1d3fa8);color:#fff;display:flex;align-items:center}} .coverin{{max-width:760px}} .cover h1{{font-size:64px;margin:6px 0 14px}}
.cover .lead{{font-size:20px;line-height:1.45;opacity:.95}} .eyebrow{{font:700 12px Inter;letter-spacing:2px;opacity:.85}} .three{{display:grid;grid-template-columns:repeat(3,1fr);gap:22px;margin:30px 0;font-size:14px;line-height:1.5}} .small{{font-size:12px;opacity:.85}}
.flow{{display:flex;gap:8px;margin:14px 0 20px}} .fl{{flex:1;background:{C['soft']};border-radius:12px;padding:12px;font:600 12px Inter;text-align:center}} .fl span{{display:block;color:{C['blue']};font:700 18px Inter;margin-bottom:4px}}
code{{background:{C['raised']};padding:1px 5px;border-radius:4px;font-size:.92em}}
"""

import re
html_doc = f"<!doctype html><meta charset='utf-8'><style>{CSS}</style>" + "".join(pages)
html_doc = re.sub(r"(px(?:/[\d.]+)?) Inter", r"\1 -apple-system,Helvetica,Arial,sans-serif", html_doc)
OUT_HTML.write_text(html_doc)
subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                f"--print-to-pdf={OUT_PDF}", f"file://{OUT_HTML}"], check=True, capture_output=True, timeout=180)
print("wrote", OUT_PDF, OUT_PDF.stat().st_size // 1024, "KB,", len(pages), "pages")
