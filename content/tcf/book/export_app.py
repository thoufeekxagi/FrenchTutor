#!/usr/bin/env python3
"""Turns the hand-written book chapters into the app's lesson and story files.

  python3 content/tcf/book/export_app.py

The book is the source of truth. This script only changes the FORMAT:
 - words / phrases / grammar / dialogues / listening / reading / writing /
   speaking / TCF corner / checkpoint sections become lessons
 - every story becomes a story file (with a meaning for each word)
 - exercises become multiple-choice questions only when real distractors exist
It writes into flutter_app/assets/content/tcf/ and rewrites course.json and
stories.json. Nothing here invents French: the only generated questions are
"what does this word mean" and "which word did you hear", built from the
authored word lists, and each one states its answer.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from check_book import load, load_all  # noqa: E402
from story_gloss import COMMON_GLOSS, STORY_META, STORY_GLOSS  # noqa: E402
from listening_story_extensions import LISTENING_GLOSS, LISTENING_STORIES  # noqa: E402

APP = HERE.parents[2] / "flutter_app" / "assets" / "content" / "tcf"
LESSONS = APP / "lessons"
STORIES = APP / "stories"
STOP = {"the", "and", "you", "your", "for", "with", "not", "from", "that", "this", "are", "has", "have", "was"}
report = {"skipped_exercises": [], "missing_story_tokens": {}, "lessons": 0, "steps": 0, "checks": 0}


def clean(s):
    return re.sub(r"\s+", " ", str(s).replace("**", "").replace("*", "").replace("\u00a0", " ")).strip()


def clean_block(s):
    return "\n".join(clean(line) for line in str(s).split("\n")).strip()


def nogcode(s):
    return re.sub(r"\s*\(g\d+[ab]?\)", "", s).strip()


def strip_paren(s):
    return re.sub(r"\s*\([^)]*\)", "", s).strip()


def say_of(fr):
    s = strip_paren(clean(fr))
    s = s.replace(" / ", ", ").replace("...", "").strip(" ,")
    return s


def tokens_en(s):
    return {w for w in re.findall(r"[a-z]+", s.lower()) if len(w) > 2 and w not in STOP}


class Lesson:
    def __init__(self, lid, chapter, title, subtitle=None):
        self.id = lid
        self.chapter = chapter
        self.title = title
        self.subtitle = subtitle
        self.steps = []
        self.n = {"e": 0, "w": 0, "p": 0, "c": 0, "l": 0, "t": 0}
        self.buf = []
        self.h3 = None
        self.pending_text = None

    def sid(self, k):
        self.n[k] += 1
        return f"{k}{self.n[k]}"

    def flush(self):
        if self.buf:
            body = "\n\n".join(self.buf)
            self.steps.append({"type": "explain", "id": self.sid("e"), "title": self.h3 or self.title, "body": body})
            self.buf = []

    def explain(self, title, body, examples=None):
        self.flush()
        st = {"type": "explain", "id": self.sid("e"), "title": title, "body": body}
        if examples:
            st["examples"] = examples
        self.steps.append(st)

    def add(self, step):
        self.flush()
        self.steps.append(step)

    def json(self):
        self.flush()
        ch = self.chapter
        minutes = max(3, round(len(self.steps) * 0.45))
        d = {
            "id": self.id,
            "unit": ch["id"] if ch["id"] != "s0" else "s0",
            "unitTitle": ch["title"],
            "title": self.title,
            "subtitle": self.subtitle or f"{ch['label']}: {ch['title']}",
            "minutes": minutes,
            "steps": self.steps,
        }
        return d


# ------------------------------------------------------------------ builders


def word_steps(lesson, rows, make_checks=True, phrases=False):
    usable = []
    for fr, snd, en, exf, exe in rows:
        step = {"type": "phrase" if phrases else "word", "id": lesson.sid("p" if phrases else "w"),
                "fr": clean(fr), "en": clean(en)}
        spoken = say_of(fr)
        if spoken and spoken != clean(fr):
            step["say"] = spoken
        if phrases:
            step["tip"] = f"Say it: {clean(snd)}"
        else:
            step["sound"] = clean(snd)
            if exf:
                step["exampleFr"] = clean(exf)
                step["exampleEn"] = clean(exe)
        lesson.add(step)
        if "..." not in fr and "…" not in fr:
            usable.append((spoken or clean(fr), clean(en), clean(fr)))
    if make_checks:
        meaning_checks(lesson, usable, 4 if phrases else 6)
        if not phrases:
            hear_checks(lesson, usable, 2)


def distractors(pool, i, count=3):
    en = pool[i][1]
    bad = tokens_en(en)
    out = []
    for k in range(1, len(pool)):
        cand = pool[(i + k * 3) % len(pool)][1]
        if cand == en or cand in out:
            continue
        if tokens_en(cand) & bad:
            continue
        out.append(cand)
        if len(out) == count:
            return out
    for k in range(1, len(pool)):
        cand = pool[(i + k) % len(pool)][1]
        if cand != en and cand not in out and not (tokens_en(cand) & bad):
            out.append(cand)
            if len(out) == count:
                return out
    return None


def meaning_checks(lesson, pool, want):
    if len(pool) < 5:
        return
    step = max(1, len(pool) // want)
    picked = list(range(0, len(pool), step))[:want]
    for i in picked:
        d = distractors(pool, i)
        if not d:
            continue
        spoken, en, fr = pool[i]
        opts = d + [en]
        pos = (i * 2 + 1) % 4
        opts = opts[:3]
        opts.insert(pos, en)
        lesson.add({"type": "choose", "id": lesson.sid("c"), "prompt": "What does this mean?", "promptFr": fr,
                    "options": opts, "answer": pos, "explain": f"{fr} means {en}."})
        report["checks"] += 1


def hear_checks(lesson, pool, want):
    singles = [p for p in pool if len(p[0].split()) <= 2 and "," not in p[0]]
    if len(singles) < 5:
        return
    step = max(1, len(singles) // (want + 1))
    for n in range(want):
        i = (n * step + 1) % len(singles)
        spoken, en, fr = singles[i]
        opts = []
        for k in range(1, len(singles)):
            cand = singles[(i + k * 2) % len(singles)][0]
            if cand != spoken and cand not in opts and cand.lower() != spoken.lower():
                opts.append(cand)
            if len(opts) == 3:
                break
        if len(opts) < 3:
            continue
        pos = (i + n) % 4
        opts.insert(pos, spoken)
        lesson.add({"type": "listen", "id": lesson.sid("l"), "fr": spoken, "question": "Which word did you hear?",
                    "options": opts, "answer": pos, "explain": f"You heard {spoken}: {en}."})
        report["checks"] += 1


def table_step(lesson, b):
    _, headers, rows, caption = b
    lesson.flush()
    hear = -1
    for i, h in enumerate(headers):
        if "example" in h.lower():
            hear = i
    st = {"type": "table", "id": lesson.sid("t"), "title": clean(caption) or lesson.h3 or lesson.title,
          "headers": [clean(h) for h in headers], "rows": [[clean(c) for c in r] for r in rows]}
    if hear >= 0:
        st["hear"] = hear
    lesson.steps.append(st)


def exercise_steps(lesson, b, siblings_pool):
    _, eid, title, instr, items = b
    answers = [clean(a) for _, a in items]
    distinct = list(dict.fromkeys(answers))
    if len(items) < 4 or len(distinct) < 4 or max(len(a) for a in answers) > 30:
        report["skipped_exercises"].append(f"{lesson.id} {eid} {clean(title)}")
        return
    for q, a in items:
        a = clean(a)
        pool = [x for x in distinct if x != a]
        opts = pool[:3] if len(pool) >= 3 else None
        if not opts:
            continue
        pos = (len(a) + len(q)) % 4
        opts = opts[:3]
        opts.insert(pos, a)
        lesson.add({"type": "choose", "id": lesson.sid("c"), "prompt": f"{clean(instr)}  {clean(q)}",
                    "options": opts, "answer": pos, "explain": f"The answer is {a}."})
        report["checks"] += 1


def mcq_steps(lesson, b):
    _, eid, title, qkind, intro, items = b
    for it in items:
        opts = [clean(o) for o in it["options"]]
        ans = it["answer"]
        if qkind == "listening":
            lesson.add({"type": "listen", "id": lesson.sid("l"), "fr": clean(it["script"]), "question": clean(it["q"]),
                        "options": opts, "answer": ans, "explain": clean(it.get("explain", ""))})
        else:
            text = it.get("text") or lesson.pending_text
            step = {"type": "choose", "id": lesson.sid("c"), "prompt": clean(it["q"]), "options": opts,
                    "answer": ans, "explain": clean(it.get("explain", ""))}
            if text:
                step["promptFr"] = clean_block(text).replace("\n", " · ") if "\n" in text else clean(text)
            lesson.add(step)


def dialogue_step(lesson, b):
    _, title, setting, lines = b
    ex = [{"fr": clean(fr), "en": f"{clean(who)}: {clean(en)}"} for who, fr, en in lines]
    lesson.explain(clean(title), clean(setting) or "Listen to each line, then read the English.", ex)


def write_speak(lesson, b):
    if b[0] == "write":
        _, eid, title, prompt, model, checklist = b
        body = clean(prompt) + "\n\nWrite it on paper or in your notes app. Then compare with the model on the next card. You can tap Ask Marie to have her read your text and give one correction."
        lesson.explain("Writing: " + clean(title), body)
        extra = ("\n\nCheck:\n" + "\n".join("• " + clean(c) for c in checklist)) if checklist else ""
        lesson.explain("Model answer", clean(model) + extra)
    else:
        _, eid, title, prompt, model, tips = b
        body = clean(prompt)
        if tips:
            body += "\n\n" + "\n".join("• " + clean(t) for t in tips)
        lesson.explain("Speaking: " + clean(title), body)
        sentences = re.split(r"(?<=[.!?])\s+", clean(model))
        chunks, cur = [], ""
        for sent in sentences:
            if cur and len(cur) + len(sent) > 190:
                chunks.append(cur)
                cur = sent
            else:
                cur = (cur + " " + sent).strip()
        if cur:
            chunks.append(cur)
        for n, chunk in enumerate(chunks, 1):
            lesson.add({"type": "phrase", "id": lesson.sid("p"), "fr": chunk,
                        "en": f"Model answer, part {n} of {len(chunks)}." if len(chunks) > 1 else "Model answer. Say it in your own words after.",
                        "tip": "Listen, then say it out loud. Tap Ask Marie to have her listen to you."})


def add_blocks(lesson, blocks, siblings):
    for b in blocks:
        k = b[0]
        if k == "h3":
            lesson.flush()
            lesson.h3 = nogcode(clean(b[1]))
        elif k == "p":
            lesson.buf.append(clean(b[1]))
        elif k == "list":
            lesson.buf.append("\n".join("• " + clean(i) for i in b[1]))
        elif k == "note":
            label = {"tip": "Tip", "canada": "In Canada", "watch": "Watch out"}[b[1]]
            lesson.explain(label, clean(b[2]))
        elif k == "table":
            table_step(lesson, b)
        elif k == "words":
            lesson.flush()
            word_steps(lesson, b[1], make_checks=len(b[1]) >= 6)
        elif k == "dialogue":
            dialogue_step(lesson, b)
        elif k == "exercise":
            exercise_steps(lesson, b, siblings)
        elif k == "mcq":
            mcq_steps(lesson, b)
            lesson.pending_text = None
        elif k == "text":
            lesson.flush()
            lesson.pending_text = b[1]
        elif k in ("write", "speak"):
            write_speak(lesson, b)
        # story and pagebreak are handled elsewhere


def sections(ch):
    out, cur = [], None
    for b in ch["blocks"]:
        if b[0] == "h2":
            cur = {"title": clean(b[1]), "blocks": []}
            out.append(cur)
        elif cur is not None:
            cur["blocks"].append(b)
    return out


def sec_num(title):
    m = re.match(r"^(\d+)\.(\d+)", title)
    return (int(m.group(1)), int(m.group(2))) if m else None


def lesson_title_from(group):
    g = clean(group or "")
    return g.split(":", 1)[1].strip() if ":" in g else g


# ------------------------------------------------------------------ chapters


def build_chapter(ch):
    lessons = []
    is_s0 = ch["id"] == "s0"
    for sec in sections(ch):
        num = sec_num(sec["title"])
        if not num:
            continue  # checklists
        k = num[1]
        blocks = sec["blocks"]
        title = re.sub(r"^\d+\.\d+\s*", "", sec["title"])
        base = f"{ch['id']}-{k:02d}" if is_s0 else None
        if is_s0:
            L = Lesson(f"s0-{k:02d}", ch, title, f"Stage 0, lesson {k}")
            add_blocks(L, blocks, None)
            lessons.append(L)
            continue
        u = ch["id"]
        if k == 0 and u.startswith(("b1-", "b2-")):
            level = u.split("-", 1)[0].upper()
            L = Lesson(f"{u}-diagnostic", ch, f"{level} readiness check", "Four-skill baseline before Unit 1")
            add_blocks(L, blocks, None)
            lessons.append(L)
        elif k == 1:  # words: one lesson per WORDS block, notes ride along
            idx = 0
            L = None
            for b in blocks:
                if b[0] == "words":
                    idx += 1
                    L = Lesson(f"{u}-words-{idx}", ch, "Words: " + (lesson_title_from(b[2]) or f"group {idx}"))
                    word_steps(L, b[1], make_checks=len(b[1]) >= 6)
                    lessons.append(L)
                elif L is not None:
                    add_blocks(L, [b], None)
        elif k == 2:
            L = Lesson(f"{u}-phrases", ch, "Phrases")
            for b in blocks:
                if b[0] == "words":
                    L.flush()
                    L.explain("Say the whole block", "Learn these as blocks, exactly as you hear them. Say each one out loud. Tap the speaker to hear it.")
                    word_steps(L, b[1], make_checks=True, phrases=True)
                else:
                    add_blocks(L, [b], None)
            lessons.append(L)
        elif k == 3:  # grammar: one lesson per H3 section
            groups, cur = [], None
            pre = []
            for b in blocks:
                if b[0] == "h3":
                    cur = {"title": clean(b[1]), "blocks": []}
                    groups.append(cur)
                elif cur is None:
                    pre.append(b)
                else:
                    cur["blocks"].append(b)
            if not groups:
                groups = [{"title": "Grammar", "blocks": blocks}]
            else:
                groups[0]["blocks"] = pre + groups[0]["blocks"]
            for gi, g in enumerate(groups):
                letter = chr(ord("a") + gi)
                name = nogcode(re.sub(r"^[A-Z]\.\s*", "", g["title"]))
                L = Lesson(f"{u}-grammar-{letter}", ch, "Grammar: " + name)
                L.h3 = name
                add_blocks(L, g["blocks"], None)
                lessons.append(L)
        elif k == 4:
            L = Lesson(f"{u}-dialogues", ch, "Dialogues")
            add_blocks(L, blocks, None)
            lessons.append(L)
        elif k == 5:
            continue  # story: exported separately
        elif k == 6:
            L = Lesson(f"{u}-listening", ch, "Listening practice")
            L.explain("Listen once", "In the real test you hear each recording once. Tap the speaker, listen, then choose. Do not replay. Never leave a question empty.")
            add_blocks(L, [b for b in blocks if b[0] in ("mcq", "text")], None)
            lessons.append(L)
        elif k == 7:
            L = Lesson(f"{u}-reading", ch, "Reading practice")
            add_blocks(L, [b for b in blocks if b[0] in ("mcq", "text")], None)
            lessons.append(L)
        elif k in (8, 9):
            L = next((x for x in lessons if x.id == f"{u}-write-speak"), None)
            if L is None:
                L = Lesson(f"{u}-write-speak", ch, "Write and speak")
                lessons.append(L)
            add_blocks(L, [b for b in blocks if b[0] in ("write", "speak")], None)
        elif k == 10:
            Lt = Lesson(f"{u}-tcf", ch, "TCF corner")
            Lc = Lesson(f"{u}-checkpoint", ch, "Checkpoint")
            Lt.explain("Exam style", "These questions look like the real TCF Canada: one play, four options, one answer. A wrong and a blank answer both score zero, so always choose.")
            for b in blocks:
                if b[0] == "p":
                    continue
                if b[0] == "mcq" and b[1].endswith("C"):
                    add_blocks(Lc, [b], None)
                else:
                    add_blocks(Lt, [b], None)
            lessons += [Lt, Lc]
    return lessons


# ------------------------------------------------------------------ stories


def lexicon_upto(chapters, last):
    lex = {}
    art = re.compile(r"^(le|la|les|l'|un|une|des)\s*")
    for ch in chapters:
        for b in ch["blocks"]:
            if b[0] != "words":
                continue
            for fr, snd, en, _, _ in b[1]:
                fr_c = strip_paren(clean(fr))
                frs = [x.strip() for x in fr_c.split(" / ")]
                snds = [x.strip() for x in clean(snd).split(" / ")]
                ens = [x.strip() for x in strip_paren(clean(en)).split(" / ")]
                for i, f in enumerate(frs):
                    forms = {f.lower()}
                    forms.add(art.sub("", f.lower()))
                    if f.lower().startswith("l'"):
                        forms.add(f.lower())
                    for form in forms:
                        if not form or " " in form:
                            continue
                        e = ens[i] if len(ens) == len(frs) else clean(en)
                        sd = snds[i] if len(snds) == len(frs) else (snds[0] if len(frs) == 1 else "")
                        lex.setdefault(form, (strip_paren(e), sd if " " not in sd else sd))
        if ch is last:
            break
    return lex


STRIP = "«»\"“”‘’'.,!?;:()—–…"


def story_key(raw):
    s = raw.replace("\u2019", "'").strip()
    return s.strip(STRIP).lower()


def build_story(ch, chapters):
    sec = next((s for s in sections(ch) if (sec_num(s["title"]) or (0, 0))[1] == 5), None)
    if not sec:
        return None
    sb = next((b for b in sec["blocks"] if b[0] == "story"), None)
    q = next((b for b in sec["blocks"] if b[0] == "mcq"), None)
    meta = ch.get("story_meta") or STORY_META.get(ch["id"])
    if not (sb and q and meta):
        return None
    _, title, title_en, sents, notes = sb
    gloss = {**STORY_GLOSS.get(meta["id"], {}), **ch.get("story_gloss", {})}
    lex = lexicon_upto(chapters, ch)
    words, missing = {}, []
    for fr, en in sents:
        for raw in clean(fr).split():
            t = story_key(raw)
            if not t or t in words:
                continue
            if t in gloss:
                g = gloss[t]
                words[t] = {"en": g[0], **({"pos": g[1]} if len(g) > 1 and g[1] else {}), **({"sound": g[2]} if len(g) > 2 and g[2] else {})}
            elif t in lex:
                e, sd = lex[t]
                w = {"en": e}
                if sd and " " not in sd:
                    w["sound"] = sd
                words[t] = w
            elif t in COMMON_GLOSS:
                g = COMMON_GLOSS[t]
                words[t] = {"en": g[0], **({"pos": g[1]} if len(g) > 1 and g[1] else {})}
            elif "'" in t and t.split("'", 1)[1] in lex:
                # Resolve elided articles and pronouns through the lexical
                # token (for example l'itinéraire -> itinéraire) so the story
                # reader can still explain every tap.
                e, sd = lex[t.split("'", 1)[1]]
                w = {"en": e}
                if sd and " " not in sd:
                    w["sound"] = sd
                words[t] = w
            elif re.fullmatch(r"\d+(?:[,.]\d+)*", t):
                words[t] = {"en": f"number {t}"}
            else:
                missing.append(t)
    if missing:
        report["missing_story_tokens"][meta["id"]] = sorted(set(missing))
    return {
        "id": meta["id"], "title": clean(title), "titleEn": clean(title_en),
        "level": ch["id"].split("-", 1)[0].upper(), "minutes": meta.get("minutes", 3),
        "summary": meta["summary"], "unit": ch["id"],
        "sentences": [{"fr": clean(fr), "en": clean(en), **({"note": clean(notes[i])} if i in notes else {})} for i, (fr, en) in enumerate(sents)],
        "words": words, "keywords": meta["keywords"],
        "quiz": [{"prompt": clean(it["q"]), "options": [clean(o) for o in it["options"]], "answer": it["answer"], "explain": clean(it.get("explain", ""))} for it in q[5]],
    }


def course_word_details(chapters):
    """Gender/number metadata recoverable from the authored word tables."""
    details = {}
    for ch in chapters:
        for block in ch["blocks"]:
            if block[0] != "words":
                continue
            for fr, *_ in block[1]:
                raw_forms = clean(fr).split(" / ")
                for raw_form in raw_forms:
                    lower = raw_form.lower()
                    gender = ""
                    number = ""
                    if re.search(r"\(\s*m\.\s*\)", lower) or re.match(r"\s*(le|un)\s+", lower):
                        gender = "masculine"
                    elif re.search(r"\(\s*f\.\s*\)", lower) or re.match(r"\s*(la|une)\s+", lower):
                        gender = "feminine"
                    elif re.match(r"\s*(les|des)\s+", lower):
                        number = "plural"
                    term = strip_paren(raw_form)
                    term = re.sub(r"^(le|la|les|un|une|des)\s+", "", term, flags=re.I)
                    key = story_key(term)
                    if not key:
                        continue
                    if gender:
                        details[key] = {
                            "pos": "noun",
                            "gender": gender,
                            "number": number or "singular",
                            "lemma": key,
                        }
                    elif number:
                        details[key] = {"pos": "noun", "number": "plural", "lemma": key}
    return details


def build_listening_story(source, chapters):
    """Export one fixed listening story and a complete contextual glossary."""
    lex = lexicon_upto(chapters, chapters[-1])
    source_details = course_word_details(chapters)
    story_lexicon = {}
    for entries in STORY_GLOSS.values():
        story_lexicon.update(entries)
    words, missing = {}, []

    def authored_gloss(token):
        gloss = LISTENING_GLOSS.get(token)
        if gloss:
            return gloss
        if token.endswith("s"):
            singular = LISTENING_GLOSS.get(token[:-1])
            if singular and len(singular) > 3 and singular[1] == "noun":
                en, pos, gender, _, lemma, note = singular
                plural_en = en if en.endswith("s") else f"{en}s"
                return (plural_en, pos, gender, "plural", lemma or token[:-1], note or f"Plural of {token[:-1]}.")
        if "'" in token:
            suffix = token.split("'", 1)[1]
            gloss = LISTENING_GLOSS.get(suffix)
            if gloss:
                return gloss
        return None

    def lexical_form(token):
        if token in lex:
            return token
        if token.endswith("s") and token[:-1] in lex:
            candidate = token[:-1]
            if source_details.get(candidate, {}).get("pos") == "noun":
                return candidate
        if "'" in token and token.split("'", 1)[1] in lex:
            return token.split("'", 1)[1]
        return None

    for fr, _ in source["sentences"]:
        for raw in clean(fr).split():
            token = story_key(raw)
            if not token or token in words:
                continue
            custom = authored_gloss(token)
            detail = {}
            if custom:
                en, pos, gender, number, lemma, note = custom
                detail = {"en": en}
                if pos: detail["pos"] = pos
                if gender: detail["gender"] = gender
                if number: detail["number"] = number
                if lemma: detail["lemma"] = lemma
                if note: detail["note"] = note
            else:
                gloss = story_lexicon.get(token) or COMMON_GLOSS.get(token)
                if gloss:
                    detail["en"] = gloss[0]
                    if len(gloss) > 1 and gloss[1]: detail["pos"] = gloss[1]
                    if len(gloss) > 2 and gloss[2]: detail["sound"] = gloss[2]
                else:
                    form = lexical_form(token)
                    if form is None:
                        missing.append(token)
                        continue
                    detail["en"] = lex[form][0]
                    if lex[form][1]: detail["sound"] = lex[form][1]
                morph = source_details.get(token)
                if morph is None and token.endswith("s"):
                    singular = token[:-1]
                    if source_details.get(singular, {}).get("pos") == "noun":
                        morph = {
                            **source_details[singular],
                            "number": "plural",
                            "lemma": singular,
                        }
                        detail["lemma"] = singular
                if morph:
                    detail.setdefault("pos", morph.get("pos", ""))
                    detail.setdefault("gender", morph.get("gender", ""))
                    detail.setdefault("number", morph.get("number", ""))
                    detail.setdefault("lemma", morph.get("lemma", ""))
            words[token] = {key: value for key, value in detail.items() if value}

    if missing:
        report["missing_story_tokens"][source["id"]] = sorted(set(missing))
    keyword_list = source["keywords"]
    return {
        "id": source["id"], "title": source["title"], "titleEn": source["titleEn"],
        "level": source["level"], "mode": "listening", "minutes": source["minutes"],
        "summary": source["summary"], "unit": source["unit"],
        "sentences": [
            {"fr": fr, "en": en, **({"note": note} if note else {})}
            for row in source["sentences"]
            for fr, en, *rest in [row]
            for note in [rest[0] if rest else ""]
        ],
        "words": words,
        "keywords": keyword_list,
        "quiz": [
            {"prompt": prompt, "options": options, "answer": answer, "explain": explain}
            for prompt, options, answer, explain in source["quiz"]
        ],
    }


# ------------------------------------------------------------------ main


def main():
    a2_only = "--a2-only" in sys.argv[1:]
    b1_only = "--b1-only" in sys.argv[1:]
    b2_only = "--b2-only" in sys.argv[1:]
    listening_only = "--listening-only" in sys.argv[1:]
    if sum((a2_only, b1_only, b2_only, listening_only)) > 1:
        raise SystemExit("Choose one scoped stage: --a2-only, --b1-only or --b2-only")
    # A2 stories need the preceding Stage 0/A1/A2 vocabulary ledger, not later
    # levels. Keep the scoped A2 export independent of downstream source data.
    chapters = load() if a2_only else load_all()
    scoped_stage = "a2" if a2_only else "b1" if b1_only else "b2" if b2_only else None
    export_chapters = [] if listening_only else [ch for ch in chapters if ch["id"].startswith(f"{scoped_stage}-")] if scoped_stage else chapters
    LESSONS.mkdir(parents=True, exist_ok=True)
    STORIES.mkdir(parents=True, exist_ok=True)
    # A listening-only content export must never touch the lesson directory.
    # Scoped full exports also preserve lessons from every other stage.
    if not listening_only and not scoped_stage:
        for f in LESSONS.glob("*.json"):
            if f.name != "dev_sample.json":
                f.unlink()
    order, story_files = [], []
    for ch in export_chapters:
        for L in build_chapter(ch):
            d = L.json()
            if not d["steps"]:
                continue
            (LESSONS / f"{L.id}.json").write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            order.append(f"{L.id}.json")
            report["lessons"] += 1
            report["steps"] += len(d["steps"])
        st = build_story(ch, chapters)
        if st:
            (STORIES / f"{st['id']}.json").write_text(json.dumps(st, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            story_files.append(f"{st['id']}.json")
    listening_story_files = []
    if not scoped_stage:
        counts = {level: 0 for level in ("A1", "A2", "B1", "B2")}
        for source in LISTENING_STORIES:
            counts[source["level"]] += 1
            st = build_listening_story(source, chapters)
            filename = f"{st['id']}.json"
            (STORIES / filename).write_text(json.dumps(st, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            listening_story_files.append(filename)
        if counts != {level: 5 for level in ("A1", "A2", "B1", "B2")}:
            raise SystemExit(f"Listening stories must have exactly five per level; found {counts}")
    if listening_only:
        stories_path = APP / "stories.json"
        old_stories = json.loads(stories_path.read_text(encoding="utf-8"))
        stories = old_stories.get("stories", [])
        listening_stories = listening_story_files
    elif scoped_stage:
        # Scoped exports update only one authored stage and merge its ordered
        # IDs into the app indexes, leaving every other generated stage intact.
        def merge_stage(existing, generated, stage_prefixes):
            keep = [name for name in existing
                    if name != "dev_sample.json"
                    and not Path(name).stem.startswith(f"{scoped_stage}-")]
            insert_at = next(
                (i for i, name in enumerate(keep)
                 if Path(name).stem.split("-", 1)[0] in stage_prefixes),
                len(keep),
            )
            return keep[:insert_at] + generated + keep[insert_at:]

        course_path = APP / "course.json"
        old_course = json.loads(course_path.read_text(encoding="utf-8"))
        downstream = {"b1", "b2"} if scoped_stage == "a2" else {"b2"} if scoped_stage == "b1" else set()
        lessons = merge_stage(old_course.get("lessons", []), order, downstream)
        lessons.append("dev_sample.json")
        stories_path = APP / "stories.json"
        old_stories = json.loads(stories_path.read_text(encoding="utf-8"))
        stories = merge_stage(old_stories.get("stories", []), story_files, downstream)
        listening_stories = old_stories.get("listeningStories", [])
    else:
        lessons = order + ["dev_sample.json"]
        stories = story_files
        listening_stories = listening_story_files
    if not listening_only:
        (APP / "course.json").write_text(json.dumps({"version": 2, "lessons": lessons}, indent=2) + "\n")
    (APP / "stories.json").write_text(json.dumps({"version": 3, "stories": stories, "listeningStories": listening_stories}, indent=2) + "\n")
    print(f"{report['lessons']} lessons, {report['steps']} steps, {report['checks']} generated checks, {len(story_files)} stories")
    for s in report["skipped_exercises"]:
        print("  exercise kept on paper (no safe distractors):", s)
    for sid, miss in report["missing_story_tokens"].items():
        print(f"  MISSING meanings in {sid}: {miss}")
    sys.exit(1 if report["missing_story_tokens"] else 0)


if __name__ == "__main__":
    main()
