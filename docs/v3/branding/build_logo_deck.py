#!/usr/bin/env python3
"""Generate the ParleSprint logo exploration deck.

Outputs:
  marks/NN-name-icon.svg   - app icon (squircle tile)
  marks/NN-name-mark.svg   - standalone mark (transparent)
  logo-deck.html           - 16:9 keynote-style deck (print to PDF via Chrome)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MARKS = os.path.join(HERE, "marks")

INK = "#17130D"      # warm near-black
INK2 = "#221C11"     # tile gradient end
CANVAS = "#FBFAF7"   # ivory
DIM = "#F4F0E6"
MUTED = "#8A8478"
GOLD = "#F2B84B"
DEEP = "#B97823"
SOFT = "#FFF1CC"
GREEN = "#2D8A5B"
CORAL = "#C95757"
COBALT = "#2563EB"
IVORY = "#F7F5F0"


def star(cx, cy, r, fill):
    """4-point sparkle centered at (cx,cy), r = half height."""
    q = r * 0.22
    return (
        f'<path d="M{cx} {cy - r} Q{cx + q} {cy - q} {cx + r} {cy} '
        f'Q{cx + q} {cy + q} {cx} {cy + r} Q{cx - q} {cy + q} {cx - r} {cy} '
        f'Q{cx - q} {cy - q} {cx} {cy - r} Z" fill="{fill}"/>'
    )


def svg(body, tile=None, size=240):
    t = ""
    if tile:
        t = f'<rect width="240" height="240" rx="54" fill="{tile}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" '
        f'__SIZE__>{t}{body}</svg>'
    )


# ---------------------------------------------------------------- marks
def c_momentum(m1, m2):
    return (
        f'<rect x="54" y="58" width="132" height="102" rx="30" fill="{m1}"/>'
        f'<path d="M76 150 L76 196 L118 154 Z" fill="{m1}"/>'
        f'<path d="M92 136 L150 90" stroke="{m2}" stroke-width="15" '
        f'stroke-linecap="round" fill="none"/>'
        f'<path d="M122 90 H150 V118" stroke="{m2}" stroke-width="15" '
        f'stroke-linecap="round" stroke-linejoin="round" fill="none"/>'
    )


def c_northstar(m1, m2):
    return star(116, 122, 80, m1) + star(186, 58, 22, m2)


def c_parle(m1, m2):
    return (
        f'<rect x="80" y="76" width="20" height="100" rx="10" fill="{m1}"/>'
        f'<circle cx="133" cy="104" r="32" stroke="{m1}" stroke-width="19" fill="none"/>'
        f'<rect x="140" y="44" width="36" height="13" rx="6.5" fill="{m2}" '
        f'transform="rotate(-32 158 50)"/>'
    )


def c_crescendo(m1, m2):
    bars = [(64, 42), (96, 68), (128, 94), (160, 122)]
    out = []
    for i, (x, h) in enumerate(bars):
        c = m2 if i == 3 else m1
        out.append(
            f'<rect x="{x}" y="{178 - h}" width="18" height="{h}" rx="9" fill="{c}"/>'
        )
    return "".join(out)


def c_path(m_path, m_dot, hole):
    return (
        f'<path d="M58 186 C98 184 104 152 128 136 C152 120 152 94 180 78" '
        f'stroke="{m_path}" stroke-width="6" stroke-linecap="round" fill="none"/>'
        f'<circle cx="88" cy="172" r="7" fill="{hole}" stroke="{m_dot}" stroke-width="5"/>'
        f'<circle cx="120" cy="142" r="7" fill="{hole}" stroke="{m_dot}" stroke-width="5"/>'
        f'<circle cx="150" cy="106" r="7" fill="{hole}" stroke="{m_dot}" stroke-width="5"/>'
        + star(182, 72, 27, m_dot)
    )


def c_bubblep(m1, hole):
    return (
        f'<rect x="80" y="72" width="20" height="106" rx="10" fill="{m1}"/>'
        f'<circle cx="135" cy="104" r="37" fill="{m1}"/>'
        f'<path d="M146 132 L162 174 L174 130 Z" fill="{m1}"/>'
        f'<circle cx="135" cy="104" r="14" fill="{hole}"/>'
    )


def c_sprint(m1, m2):
    return (
        f'<rect x="52" y="72" width="88" height="20" rx="10" fill="{m1}"/>'
        f'<rect x="52" y="108" width="104" height="20" rx="10" fill="{m2}"/>'
        f'<path d="M148 98 L190 118 L148 138 Z" fill="{m2}"/>'
        f'<rect x="52" y="144" width="64" height="20" rx="10" fill="{m1}"/>'
    )


def c_ring(m1, m2):
    return (
        f'<path d="M74 162 A58 58 0 1 1 166 162" stroke="{m1}" stroke-width="14" '
        f'stroke-linecap="round" fill="none"/>'
        f'<path d="M86 168 L92 202 L120 174 Z" fill="{m1}"/>'
        f'<circle cx="120" cy="108" r="14" fill="{m2}"/>'
    )


def c_twovoices(m1, m2, m3):
    return (
        f'<rect x="98" y="92" width="94" height="70" rx="24" fill="{m2}"/>'
        f'<path d="M158 160 L176 194 L136 160 Z" fill="{m2}"/>'
        f'<rect x="48" y="62" width="94" height="70" rx="24" fill="{m1}"/>'
        f'<path d="M74 132 L68 166 L104 132 Z" fill="{m1}"/>'
        + star(154, 110, 24, m3)
    )


def c_heritage(m1, m2):
    """Refined version of the current P + bolt: thinner bolt, optical bowl."""
    return (
        f'<rect x="72" y="56" width="24" height="128" rx="6" fill="{m1}"/>'
        f'<path d="M84 56 h46 a52 52 0 0 1 0 88 h-46 v-20 h44 a32 32 0 0 0 0 -48 h-44 Z" '
        f'fill="{m1}"/>'
        f'<path d="M144 110 L100 198 L116 150 L94 150 L124 110 Z" fill="{m2}"/>'
    )


# Each concept: icon variant + two standalone variants (on-light, on-dark).
CONCEPTS = [
    {
        "num": "01", "key": "momentum", "name": "Momentum",
        "idea": "A speech bubble carrying an arrow. Conversation that moves you forward.",
        "bullets": [
            "Reads instantly at 18 px; one shape, one direction.",
            "The arrow points up-right: progress, immigration, the next checkpoint.",
            "Ownable double meaning: the send-arrow of a chat becomes forward motion.",
        ],
        "colors": [GOLD, INK],
        "icon": svg(c_momentum(GOLD, INK), tile="#1B1610"),
        "mark_dark": svg(c_momentum(GOLD, INK)),
        "mark_light": svg(c_momentum(DEEP, CANVAS)),
    },
    {
        "num": "02", "key": "northstar", "name": "Northstar",
        "idea": "A four-point star with a companion spark. The guide that always knows what is next.",
        "bullets": [
            "Named for the product palette itself: Northstar Studio.",
            "Star = the goal; the smaller spark = Marie or the learner beside it.",
            "Premium, calm, and works in one color at any size.",
        ],
        "colors": [GOLD, IVORY, INK],
        "icon": svg(c_northstar(GOLD, IVORY), tile="#1B1610"),
        "mark_dark": svg(c_northstar(GOLD, IVORY)),
        "mark_light": svg(c_northstar(DEEP, MUTED)),
    },
    {
        "num": "03", "key": "parle", "name": "Parle Accent",
        "idea": "A geometric lowercase p topped by a flying acute accent. French through typography, not props.",
        "bullets": [
            "The accent recalls parle and a spark of momentum at once.",
            "Lowercase keeps the brand warm; the gold accent keeps it sharp.",
            "Wordmark option: parlesprint with the accent over the e.",
        ],
        "colors": [IVORY, GOLD, INK],
        "icon": svg(c_parle(IVORY, GOLD), tile="#1B1610"),
        "mark_dark": svg(c_parle(IVORY, GOLD)),
        "mark_light": svg(c_parle(INK, DEEP)),
    },
    {
        "num": "04", "key": "crescendo", "name": "Crescendo",
        "idea": "Four voice bars rising, the last one gold. Speaking practice that compounds.",
        "bullets": [
            "Voice-first identity: the bars are Marie's waveform.",
            "Ascending steps = the daily path; the gold bar = mastery unlocked.",
            "Animates beautifully: bars can pulse during a live session.",
        ],
        "colors": [IVORY, GOLD, INK],
        "icon": svg(c_crescendo(IVORY, GOLD), tile="#1B1610"),
        "mark_dark": svg(c_crescendo(IVORY, GOLD)),
        "mark_light": svg(c_crescendo(INK, DEEP)),
    },
    {
        "num": "05", "key": "path", "name": "The Path",
        "idea": "Checkpoints on a rising path ending at a star. The governed daily journey to the exam.",
        "bullets": [
            "Literal picture of the product promise: today to checkpoint to goal.",
            "Dots map to New, Building, Ready; the star is TCF day.",
            "Different from every language app on the store shelf.",
        ],
        "colors": [GOLD, MUTED, INK],
        "icon": svg(c_path("#8A8478", GOLD, INK), tile="#1B1610"),
        "mark_dark": svg(c_path("#8A8478", GOLD, INK)),
        "mark_light": svg(c_path("#A79E8B", DEEP, CANVAS)),
    },
    {
        "num": "06", "key": "bubblep", "name": "Bubble P",
        "idea": "The bowl of the P is a speech bubble. One color, one idea, endlessly reproducible.",
        "bullets": [
            "Initials plus category in a single glyph: ParleSprint, spoken.",
            "Survives embroidery, favicons, and watch complications.",
            "The counter-dot can carry state: gold for live, ivory for idle.",
        ],
        "colors": [GOLD, INK],
        "icon": svg(c_bubblep(GOLD, INK), tile="#1B1610"),
        "mark_dark": svg(c_bubblep(GOLD, "#14100A")),
        "mark_light": svg(c_bubblep(DEEP, CANVAS)),
    },
    {
        "num": "07", "key": "sprint", "name": "Sprint Lines",
        "idea": "Three lesson lines, the middle one breaks into an arrow. Content in motion.",
        "bullets": [
            "Gold tile is a bold shelf presence next to Duolingo and Babbel.",
            "The arrow-lane is the sprint; the quiet bars are structured lessons.",
            "Inverts cleanly for dark mode and marketing use.",
        ],
        "colors": [INK, GOLD],
        "icon": svg(c_sprint(INK, INK), tile=GOLD),
        "mark_dark": svg(c_sprint(IVORY, GOLD)),
        "mark_light": svg(c_sprint(INK, DEEP)),
    },
    {
        "num": "08", "key": "voicering", "name": "Voice Ring",
        "idea": "An open listening ring with a mic at the center. Marie, always there when you speak.",
        "bullets": [
            "The gap in the ring becomes the speech tail: a call you can enter.",
            "Feels like a live session indicator, which is the product's peak moment.",
            "Calm and circular; pairs with the Today screen's one-action layout.",
        ],
        "colors": [IVORY, GOLD, INK],
        "icon": svg(c_ring(IVORY, GOLD), tile="#1B1610"),
        "mark_dark": svg(c_ring(IVORY, GOLD)),
        "mark_light": svg(c_ring(INK, DEEP)),
    },
    {
        "num": "09", "key": "twovoices", "name": "Two Voices",
        "idea": "Learner bubble meets Marie's gold bubble. A spark appears where they overlap.",
        "bullets": [
            "The product story in one mark: dialogue with a live tutor.",
            "Spark only exists when both voices meet; progress through conversation.",
            "Warm and human without drifting into mascot territory.",
        ],
        "colors": [IVORY, GOLD, INK],
        "icon": svg(c_twovoices(IVORY, GOLD, IVORY), tile="#1B1610"),
        "mark_dark": svg(c_twovoices(IVORY, GOLD, INK)),
        "mark_light": svg(c_twovoices(INK, GOLD, INK)),
    },
    {
        "num": "10", "key": "heritage", "name": "Heritage Bolt",
        "idea": "The shipping icon, refined. Slimmer bolt, corrected bowl, calmer geometry.",
        "bullets": [
            "Evolution, not revolution: keeps earned recognition.",
            "Bolt reads as the 'sprint' and as the accent-like cut through the P.",
            "Zero rebrand cost: same colors, same silhouette family.",
        ],
        "colors": [GOLD, INK],
        "icon": svg(c_heritage(GOLD, INK), tile="#1B1610"),
        "mark_dark": svg(c_heritage(GOLD, INK)),
        "mark_light": svg(c_heritage(DEEP, CANVAS)),
    },
]




# ---------------------------------------------------------------- write marks
os.makedirs(MARKS, exist_ok=True)
for c in CONCEPTS:
    with open(os.path.join(MARKS, f"{c['num']}-{c['key']}-icon.svg"), "w") as f:
        f.write(c["icon"].replace("__SIZE__", 'width="240" height="240"'))
    with open(os.path.join(MARKS, f"{c['num']}-{c['key']}-mark.svg"), "w") as f:
        f.write(c["mark_dark"].replace("__SIZE__", 'width="240" height="240"'))


# ---------------------------------------------------------------- deck html
def lockup(mark_svg, text=IVORY, sub=MUTED):
    return f"""
    <div class="lockup">
      {mark_svg.replace('__SIZE__', 'style="width:46px;height:46px"')}
      <div class="lockup-text">
        <div class="wordmark" style="color:{text}">ParleSprint</div>
        <div class="tagline" style="color:{sub}">FRENCH FOR TCF CANADA</div>
      </div>
    </div>"""


def swatches(colors):
    dots = "".join(
        f'<span class="sw"><i style="background:{c}"></i>{c}</span>' for c in colors
    )
    return f'<div class="swatches">{dots}</div>'


slides = []
cover_minis = "".join(
    c["icon"].replace('__SIZE__', 'style="width:92px;height:92px"')
    for c in CONCEPTS
)
slides.append(f"""
<section class="slide cover">
  <div class="cover-top">
    <div class="kicker">IDENTITY EXPLORATION · V1</div>
    <h1>Parle<span>Sprint</span></h1>
    <p class="sub">Ten logo directions for the TCF Canada coach.<br/>
    Built on the Northstar system: warm ink, earned gold, ivory light.<br/>
    One idea per mark. No flags, no mascots, no props.</p>
  </div>
  <div class="cover-grid">{cover_minis}</div>
  <div class="cover-foot">Prepared {__import__('datetime').date.today():%B %d, %Y} · for review and direction selection</div>
</section>""")

for c in CONCEPTS:
    bullets = "".join(f"<li>{b}</li>" for b in c["bullets"])
    sizes = "".join(
        f'<div class="sz"><div class="szwrap" style="width:{s}px;height:{s}px">'
        + c["icon"].replace('__SIZE__', f'style="width:{s}px;height:{s}px"')
        + f'</div><em>{s}px</em></div>'
        for s in (148, 72, 44, 28)
    )
    slides.append(f"""
<section class="slide">
  <div class="left">
    <div class="big">{c['icon'].replace('__SIZE__', 'style="width:300px;height:300px"')}</div>
    <div class="sizerow">{sizes}</div>
    <div class="chips">
      <div class="chip light">{c['mark_light'].replace('__SIZE__', 'style="width:72px;height:72px"')}</div>
      <div class="chip dark">{c['mark_dark'].replace('__SIZE__', 'style="width:72px;height:72px"')}</div>
    </div>
  </div>
  <div class="right">
    <div class="num">{c['num']}</div>
    <h2>{c['name']}</h2>
    <p class="idea">{c['idea']}</p>
    <ul>{bullets}</ul>
    {swatches(c['colors'])}
    <div class="lockrow">{lockup(c['mark_dark'])}</div>
  </div>
</section>""")

recap = "".join(
    f'<div class="rc"><div class="rcicon">'
    + c["icon"].replace('__SIZE__', 'style="width:150px;height:150px"')
    + f'</div><div class="rcname">{c["num"]} · {c["name"]}</div></div>'
    for c in CONCEPTS
)
slides.append(f"""
<section class="slide">
  <div class="recap">
    <div class="kicker">RECAP</div>
    <h2 class="rctitle">Ten directions, one decision</h2>
    <div class="rgrid">{recap}</div>
    <p class="rfoot">Recommendation: shortlist by silhouette first (which shape is
    unmistakable in the Dock?), then by story (which idea would you defend in one
    sentence?). Approved direction gets a full type, color and usage pass next.</p>
  </div>
</section>""")

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
@page {{ size: 1280px 800px; margin: 0; }}
* {{ margin:0; padding:0; box-sizing:border-box; }}
body {{ font-family:-apple-system,'SF Pro Text','SF Pro Display',Inter,Helvetica,Arial,sans-serif;
       background:#12100C; color:{IVORY}; }}
.slide {{ width:1280px; height:800px; page-break-after:always; display:flex;
          background:radial-gradient(1200px 700px at 75% 15%, #1C1810 0%, #12100C 60%);
          overflow:hidden; position:relative; }}
.cover {{ flex-direction:column; justify-content:space-between; padding:72px 84px 48px; }}
.kicker {{ font-size:13px; letter-spacing:3px; color:{GOLD}; font-weight:600; }}
.cover h1 {{ font-size:120px; font-weight:800; letter-spacing:-4px; margin-top:18px; color:{IVORY}; }}
.cover h1 span {{ color:{GOLD}; }}
.cover .sub {{ font-size:19px; line-height:1.6; color:#B9B2A4; margin-top:22px; }}
.cover-grid {{ display:flex; gap:22px; flex-wrap:wrap; }}
.cover-grid svg {{ border-radius:22px; }}
.cover-foot {{ font-size:13px; color:{MUTED}; }}
.left {{ width:44%; display:flex; flex-direction:column; align-items:center;
         justify-content:center; gap:34px; }}
.big svg {{ border-radius:70px; box-shadow:0 30px 80px rgba(0,0,0,.55),0 0 0 1px rgba(255,255,255,.06); }}
.sizerow {{ display:flex; align-items:flex-end; gap:30px; }}
.sz {{ display:flex; flex-direction:column; align-items:center; gap:8px; }}
.sz em {{ font-size:11px; color:{MUTED}; font-style:normal; letter-spacing:1px; }}
.szwrap svg {{ border-radius:22%; display:block; }}
.chips {{ display:flex; gap:18px; }}
.chip {{ width:132px; height:92px; border-radius:16px; display:flex; align-items:center;
         justify-content:center; }}
.chip.light {{ background:{CANVAS}; }}
.chip.dark {{ background:#000; border:1px solid #2A251C; }}
.right {{ width:56%; padding:96px 90px 64px 20px; display:flex; flex-direction:column; }}
.num {{ font-size:15px; font-weight:700; letter-spacing:4px; color:{GOLD}; }}
.right h2 {{ font-size:56px; font-weight:800; letter-spacing:-2px; margin:10px 0 14px; }}
.idea {{ font-size:20px; line-height:1.5; color:#DDD6C8; max-width:520px; }}
.right ul {{ margin:26px 0 0 18px; }}
.right li {{ font-size:15.5px; line-height:1.55; color:#A79E8B; margin-bottom:11px;
             max-width:520px; }}
.swatches {{ display:flex; gap:22px; margin-top:26px; }}
.sw {{ font-size:12px; color:{MUTED}; letter-spacing:.5px; display:flex;
       align-items:center; gap:7px; }}
.sw i {{ width:15px; height:15px; border-radius:50%; display:inline-block;
        border:1px solid rgba(255,255,255,.15); }}
.lockrow {{ margin-top:auto; padding-top:24px; border-top:1px solid #2A251C; }}
.lockup {{ display:flex; align-items:center; gap:16px; }}
.wordmark {{ font-size:30px; font-weight:800; letter-spacing:-1px; color:{IVORY}; }}
.tagline {{ font-size:11px; letter-spacing:2.5px; color:{MUTED}; margin-top:3px; font-weight:600; }}
.recap {{ padding:80px 84px; width:100%; display:flex; flex-direction:column; }}
.rctitle {{ font-size:44px; font-weight:800; letter-spacing:-1.5px; margin:12px 0 40px; }}
.rgrid {{ display:grid; grid-template-columns:repeat(5,1fr); gap:34px 30px; }}
.rc {{ text-align:center; }}
.rcicon svg {{ border-radius:34px; box-shadow:0 14px 40px rgba(0,0,0,.4); }}
.rcname {{ margin-top:12px; font-size:13px; color:#B9B2A4; letter-spacing:.5px; }}
.rfoot {{ margin-top:auto; font-size:14px; color:{MUTED}; max-width:900px; line-height:1.6; }}
</style></head><body>{''.join(slides)}</body></html>"""

with open(os.path.join(HERE, "logo-deck.html"), "w") as f:
    f.write(html)
print("wrote", len(CONCEPTS), "concepts +", os.path.join(HERE, "logo-deck.html"))
