"""Authoring helpers and renderer for the ParleSprint A1 book.

Chapters are plain Python data written by hand in chapters/*.py. Each chapter
file defines CHAPTER = chapter(...). build_book.py collects them, renders one
HTML document and prints it to PDF with Chrome. The same data later feeds the
app lesson files, so the book and the app can never disagree.
"""
import html
import re
import unicodedata

# ---------------------------------------------------------------- authoring


def chapter(cid, label, title, blocks, can_do="", situation="", canada=None, part="", badge=""):
    return dict(id=cid, label=label, title=title, blocks=blocks, can_do=can_do,
                situation=situation, canada=canada or [], part=part, badge=badge)


def H(text): return ("h2", text)
def H3(text): return ("h3", text)
def P(text): return ("p", text)
def LIST(*items): return ("list", list(items))
def TIP(text): return ("note", "tip", text)
def CANADA(text): return ("note", "canada", text)
def WATCH(text): return ("note", "watch", text)
def TABLE(headers, rows, caption=""): return ("table", headers, rows, caption)


def WORDS(rows, title=""):
    """rows: (french, sound, english, example_fr, example_en)."""
    return ("words", rows, title)


def DIALOGUE(title, setting, lines):
    """lines: (speaker, french, english)."""
    return ("dialogue", title, setting, lines)


def STORY(title, title_en, sentences, notes=None):
    """sentences: (french, english). notes: optional {index: text}."""
    return ("story", title, title_en, sentences, notes or {})


def EXERCISE(eid, title, instruction, items):
    """items: (question, answer). Answers go to the answer key."""
    return ("exercise", eid, title, instruction, items)


def MCQ(eid, title, kind, intro, items):
    """kind: 'listening' or 'reading'. items: dict(q, options, answer, explain,
    script (listening) or text (reading))."""
    return ("mcq", eid, title, kind, intro, items)


def WRITE(eid, title, prompt, model, checklist=None):
    return ("write", eid, title, prompt, model, checklist or [])


def SPEAK(eid, title, prompt, model, tips=None):
    return ("speak", eid, title, prompt, model, tips or [])


def TEXT(text): return ("text", text)
def PAGEBREAK(): return ("pagebreak",)


# ---------------------------------------------------------------- rendering


def esc(s):
    return html.escape(str(s), quote=False)


def md(s):
    """Tiny markup: **bold**, *italic*, line breaks as <br>."""
    s = esc(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", s)
    return s.replace("\n", "<br>")


def sort_key(fr):
    t = unicodedata.normalize("NFD", fr.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    t = re.sub(r"^(le |la |les |l'|un |une |des |se |s')", "", t)
    return t


LETTERS = "ABCD"


def render_blocks(ch, blocks, key):
    out = []
    for b in blocks:
        kind = b[0]
        if kind == "h2":
            out.append(f"<h2>{md(b[1])}</h2>")
        elif kind == "h3":
            out.append(f"<h3>{md(b[1])}</h3>")
        elif kind == "p":
            out.append(f"<p>{md(b[1])}</p>")
        elif kind == "list":
            out.append("<ul>" + "".join(f"<li>{md(i)}</li>" for i in b[1]) + "</ul>")
        elif kind == "note":
            label = {"tip": "Tip", "canada": "In Canada", "watch": "Watch out"}[b[1]]
            out.append(f'<div class="note {b[1]}"><b>{label}</b> {md(b[2])}</div>')
        elif kind == "table":
            _, headers, rows, caption = b
            t = '<table class="tbl">'
            if caption:
                t += f"<caption>{md(caption)}</caption>"
            t += "<tr>" + "".join(f"<th>{md(h)}</th>" for h in headers) + "</tr>"
            for r in rows:
                t += "<tr>" + "".join(f"<td>{md(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</table>")
        elif kind == "words":
            _, rows, title = b
            t = '<table class="words">'
            if title:
                t += f"<caption>{md(title)}</caption>"
            t += "<tr><th>French</th><th>Say it</th><th>English</th><th>In a sentence</th></tr>"
            for fr, snd, en, exf, exe in rows:
                ex = f"<span class='exfr'>{md(exf)}</span><br><span class='exen'>{md(exe)}</span>" if exf else ""
                t += (f"<tr><td class='fr'>{md(fr)}</td><td class='snd'>{md(snd)}</td>"
                      f"<td>{md(en)}</td><td>{ex}</td></tr>")
            out.append(t + "</table>")
        elif kind == "dialogue":
            _, title, setting, lines = b
            d = f'<div class="dlg"><div class="dlgtitle">{md(title)}</div>'
            if setting:
                d += f'<div class="dlgset">{md(setting)}</div>'
            for who, fr, en in lines:
                d += (f'<div class="line"><span class="who">{md(who)}</span>'
                      f'<span class="fr">{md(fr)}</span><span class="en">{md(en)}</span></div>')
            out.append(d + "</div>")
        elif kind == "story":
            _, title, title_en, sents, notes = b
            d = (f'<div class="story"><div class="eyebrow">STORY</div><div class="stitle">{md(title)}</div>'
                 f'<div class="stitle-en">{md(title_en)}</div>')
            for i, (fr, en) in enumerate(sents):
                d += f'<div class="sent"><div class="sfr">{md(fr)}</div><div class="sen">{md(en)}</div>'
                if i in notes:
                    d += f'<div class="snote">{md(notes[i])}</div>'
                d += "</div>"
            out.append(d + "</div>")
        elif kind == "exercise":
            _, eid, title, instr, items = b
            d = f'<div class="ex"><div class="eyebrow">EXERCISE {esc(eid)}</div><div class="extitle">{md(title)}</div>'
            d += f'<div class="exinstr">{md(instr)}</div><ol>'
            for q, a in items:
                d += f"<li>{md(q)}</li>"
            d += "</ol></div>"
            out.append(d)
            key.append(("exercise", ch, eid, title, items))
        elif kind == "mcq":
            _, eid, title, qkind, intro, items = b
            label = "LISTENING" if qkind == "listening" else "READING"
            d = f'<div class="ex mcq"><div class="eyebrow">{label} {esc(eid)}</div><div class="extitle">{md(title)}</div>'
            if intro:
                d += f'<div class="exinstr">{md(intro)}</div>'
            for n, it in enumerate(items, 1):
                d += '<div class="q">'
                if qkind == "reading" and it.get("text"):
                    d += f'<div class="rtext">{md(it["text"])}</div>'
                d += f'<div class="qt"><b>{n}.</b> {md(it["q"])}</div><div class="opts">'
                for i, o in enumerate(it["options"]):
                    d += f'<span class="opt"><b>{LETTERS[i]}</b> {md(o)}</span>'
                d += "</div></div>"
            out.append(d + "</div>")
            key.append(("mcq", ch, eid, title, qkind, items))
        elif kind == "write":
            _, eid, title, prompt, model, checklist = b
            d = (f'<div class="ex wr"><div class="eyebrow">WRITING {esc(eid)}</div><div class="extitle">{md(title)}</div>'
                 f'<div class="exinstr">{md(prompt)}</div><div class="lines"></div>')
            if checklist:
                d += "<div class='chk'><b>Check your text:</b><ul>" + "".join(f"<li>{md(c)}</li>" for c in checklist) + "</ul></div>"
            out.append(d + "</div>")
            key.append(("write", ch, eid, title, model))
        elif kind == "speak":
            _, eid, title, prompt, model, tips = b
            d = (f'<div class="ex sp"><div class="eyebrow">SPEAKING {esc(eid)}</div><div class="extitle">{md(title)}</div>'
                 f'<div class="exinstr">{md(prompt)}</div>')
            if tips:
                d += "<ul>" + "".join(f"<li>{md(t)}</li>" for t in tips) + "</ul>"
            out.append(d + "</div>")
            key.append(("speak", ch, eid, title, model))
        elif kind == "text":
            out.append(f'<div class="rtext" style="margin:6pt 0">{md(b[1])}</div>')
        elif kind == "pagebreak":
            out.append('<div class="pb"></div>')
    return "\n".join(out)


def render_key(entries):
    out = []
    current = None
    for e in entries:
        ch = e[1]
        if current != ch["id"]:
            current = ch["id"]
            out.append(f'<h3 class="keych">{md(ch["label"])}: {md(ch["title"])}</h3>')
        kind = e[0]
        if kind == "exercise":
            _, _, eid, title, items = e
            out.append(f'<div class="kh">Exercise {esc(eid)}: {md(title)}</div><ol class="ka">')
            for q, a in items:
                out.append(f"<li>{md(a)}</li>")
            out.append("</ol>")
        elif kind == "mcq":
            _, _, eid, title, qkind, items = e
            out.append(f'<div class="kh">{"Listening" if qkind == "listening" else "Reading"} {esc(eid)}: {md(title)}</div>')
            for n, it in enumerate(items, 1):
                script = ""
                if qkind == "listening" and it.get("script"):
                    script = f'<span class="scr">Audio: {md(it["script"])}</span> '
                out.append(f'<div class="kq">{script}<b>{n}. {LETTERS[it["answer"]]}</b> {md(it["options"][it["answer"]])}. {md(it.get("explain", ""))}</div>')
        elif kind in ("write", "speak"):
            _, _, eid, title, model = e
            out.append(f'<div class="kh">{"Writing" if kind == "write" else "Speaking"} {esc(eid)}: {md(title)} (model)</div><div class="model">{md(model)}</div>')
    return "\n".join(out)


def vocab_index(chapters):
    seen = {}
    for ch in chapters:
        for b in ch["blocks"]:
            if b[0] == "words":
                for fr, snd, en, _, _ in b[1]:
                    seen.setdefault(fr, (en, ch["label"]))
    return sorted(seen.items(), key=lambda kv: sort_key(kv[0]))


CSS = """
@page { size: A4; margin: 18mm 16mm 20mm 16mm; }
@page :first { margin: 0; }
* { box-sizing: border-box; }
body { font-family: Inter, -apple-system, Helvetica, Arial, sans-serif; font-size: 10.4pt; line-height: 1.5; color: #14171C; margin: 0; }
b { font-weight: 700; }
h1 { font-size: 30pt; letter-spacing: -1px; margin: 0 0 6pt; }
h2 { font-size: 15pt; letter-spacing: -.3px; margin: 20pt 0 6pt; padding-bottom: 4pt; border-bottom: 2px solid #2563EB; break-after: avoid; }
h3 { font-size: 12pt; margin: 14pt 0 4pt; break-after: avoid; }
p { margin: 5pt 0; }
ul, ol { margin: 5pt 0 5pt 16pt; padding: 0; } li { margin: 2pt 0; }
.pb { break-after: page; }
.cover { height: 257mm; display: flex; flex-direction: column; justify-content: flex-end; break-after: page; }
.cover .big { font-size: 58pt; font-weight: 800; letter-spacing: -2.5px; line-height: .98; color: #fff; }
.cover .small { color: rgba(255,255,255,.85); font-size: 12pt; margin-top: 14pt; max-width: 120mm; line-height: 1.45; }
.coverbg { background: linear-gradient(145deg, #2563EB, #172554); padding: 18mm 16mm 22mm; height: 297mm; }
.eyebrow { font-size: 8pt; font-weight: 700; letter-spacing: 1.8px; color: #2563EB; margin-bottom: 3pt; }
.opener { break-before: page; break-after: page; padding-top: 50mm; }
.opener .num { font-size: 80pt; font-weight: 800; letter-spacing: -4px; color: #2563EB; line-height: 1; }
.opener .ttl { font-size: 28pt; font-weight: 800; letter-spacing: -1px; margin: 6pt 0 14pt; line-height: 1.1; }
.box { background: #E8EFFE; border-radius: 10pt; padding: 10pt 14pt; margin: 8pt 0; }
.box .eyebrow { margin-bottom: 4pt; }
.note { border-radius: 8pt; padding: 7pt 11pt; margin: 8pt 0; font-size: 9.8pt; break-inside: avoid; }
.note.tip { background: #E8EFFE; } .note.canada { background: #FFF4E0; } .note.watch { background: #FDE8E8; }
.note > b:first-child { margin-right: 4pt; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0; }
caption { text-align: left; font-weight: 700; padding: 4pt 0; }
th { text-align: left; font-size: 8pt; letter-spacing: 1px; text-transform: uppercase; color: #5F6673; padding: 4pt 6pt; border-bottom: 1.5px solid #14171C; }
td { padding: 5pt 6pt; border-bottom: 1px solid #E1E4EA; vertical-align: top; }
tr { break-inside: avoid; }
table.words td.fr { font-weight: 700; font-size: 11pt; white-space: nowrap; }
table.words td.snd { color: #2563EB; font-size: 9.2pt; white-space: nowrap; }
.exfr { font-weight: 500; } .exen { color: #5F6673; font-size: 9pt; }
.dlg { border: 1px solid #E1E4EA; border-radius: 10pt; padding: 10pt 14pt; margin: 10pt 0; break-inside: avoid; }
.dlgtitle { font-weight: 800; font-size: 11.5pt; } .dlgset { color: #5F6673; font-size: 9.2pt; margin-bottom: 6pt; }
.line { display: grid; grid-template-columns: 20mm 1fr; column-gap: 8pt; margin: 4pt 0; }
.line .who { font-weight: 700; color: #2563EB; grid-row: 1 / span 2; }
.line .en { color: #5F6673; font-size: 9.2pt; }
.story { border-left: 4px solid #2563EB; padding: 2pt 0 2pt 14pt; margin: 12pt 0; }
.stitle { font-size: 17pt; font-weight: 800; letter-spacing: -.5px; } .stitle-en { color: #5F6673; margin-bottom: 8pt; }
.sent { margin: 7pt 0; break-inside: avoid; } .sfr { font-size: 11.5pt; font-weight: 500; } .sen { color: #5F6673; font-size: 9.4pt; }
.snote { font-size: 8.8pt; color: #2563EB; margin-top: 1pt; }
.ex { border: 1.5px solid #14171C; border-radius: 10pt; padding: 9pt 14pt 10pt; margin: 14pt 0; }
.extitle { font-size: 12pt; font-weight: 800; } .exinstr { color: #5F6673; margin: 2pt 0 4pt; }
.q { margin: 8pt 0; break-inside: avoid; } .qt { margin-bottom: 2pt; } .rtext { background: #F5F6F8; border-radius: 8pt; padding: 7pt 10pt; margin-bottom: 4pt; }
.opts { display: grid; grid-template-columns: 1fr 1fr; gap: 2pt 14pt; } .opt b { color: #2563EB; margin-right: 3pt; }
.lines { height: 135pt; background: repeating-linear-gradient(#fff, #fff 17pt, #CBD0D8 17pt, #CBD0D8 18pt); margin: 6pt 0; }
.chk { font-size: 9.2pt; color: #5F6673; }
.keych { margin-top: 18pt; border-bottom: 1px solid #E1E4EA; } .kh { font-weight: 700; margin: 8pt 0 2pt; }
.kq { font-size: 9.4pt; margin: 2pt 0; break-inside: avoid; } .scr { color: #2563EB; font-style: italic; }
.ka { font-size: 9.4pt; columns: 2; } .model { background: #F5F6F8; border-radius: 8pt; padding: 7pt 10pt; font-size: 9.6pt; }
.toc li { margin: 3pt 0; } .toc .part { font-weight: 800; margin-top: 10pt; list-style: none; margin-left: -16pt; }
.vindex { columns: 2; column-gap: 14mm; font-size: 9.2pt; } .vindex div { break-inside: avoid; margin: 1pt 0; }
.vindex b { font-weight: 700; } .vindex span { color: #5F6673; }
"""


def render_chapter(ch, key):
    h = (f'<div class="opener"><div class="eyebrow">{md(ch["label"]).upper()}</div>'
         f'<div class="num">{md(ch["badge"])}</div>'
         f'<div class="ttl">{md(ch["title"])}</div>')
    if ch["can_do"]:
        h += f'<div class="box"><div class="eyebrow">AFTER THIS UNIT YOU CAN</div>{md(ch["can_do"])}</div>'
    if ch["situation"]:
        h += f'<div class="box"><div class="eyebrow">THE SITUATION</div>{md(ch["situation"])}</div>'
    for c in ch["canada"]:
        h += f'<div class="note canada"><b>In Canada</b> {md(c)}</div>'
    h += "</div>"
    h += render_blocks(ch, ch["blocks"], key)
    return h


def render_book(front, chapters, back_title="A1 vocabulary index"):
    key = []
    body = []
    toc = ['<ul class="toc">']
    last_part = None
    for ch in chapters:
        if ch["part"] and ch["part"] != last_part:
            toc.append(f'<li class="part">{md(ch["part"])}</li>')
            last_part = ch["part"]
        toc.append(f'<li>{md(ch["label"])}: {md(ch["title"])}</li>')
    toc.append("</ul>")
    body.append(front.replace("{{TOC}}", "".join(toc)))
    for ch in chapters:
        body.append(render_chapter(ch, key))
    body.append('<div class="opener" style="padding-top:20mm"><div class="eyebrow">ANSWER KEY</div><div class="ttl">Answers, audio scripts and model texts</div>'
                '<p>Do the exercise first. Then check. Read the audio scripts only after you answered the listening questions.</p></div>')
    body.append(render_key(key))
    idx = vocab_index(chapters)
    body.append(f'<div class="opener" style="padding-top:20mm"><div class="eyebrow">INDEX</div><div class="ttl">{md(back_title)}</div>'
                f'<p>{len(idx)} vocabulary entries, including fixed phrases, A to Z, with the unit where you meet them.</p></div>')
    body.append('<div class="vindex">' + "".join(
        f"<div><b>{md(fr)}</b> <span>{md(en)} ({md(lab)})</span></div>" for fr, (en, lab) in idx) + "</div>")
    return (f"<!doctype html><meta charset='utf-8'><style>@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');{CSS}</style>"
            + "\n".join(body)), len(idx), len(key)
