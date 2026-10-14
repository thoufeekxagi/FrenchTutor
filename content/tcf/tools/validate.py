#!/usr/bin/env python3
"""Content gate for content/tcf. Exit 1 on any error.

Checks (syllabus, runs today):
  - grammar ids unique; every id used by a unit exists
  - a grammar point is introduced exactly once and never reviewed before it
    is introduced (teaching order is law)
  - unit ids unique and sequential; required fields present; word targets sum
  - every mini_mock references a real unit
  - Stage 0 lesson ids unique and complete

Checks (unit files, when content/tcf/units/**/unit.json exist):
  - six lessons in the fixed template order
  - words_a and words_b contain exactly 5 words each
  - cumulative vocabulary: every French token must be known from earlier units,
    this unit's new words, or the function-word allowlist (warnings, not errors,
    until the lexicon ledger is complete)
  - audio.json lists every French string that appears in the unit

Usage: python3 content/tcf/tools/validate.py [--strict-ledger]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SYL = ROOT / "syllabus"
UNITS = ROOT / "units"
errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def load(path):
    try:
        return json.loads(path.read_text())
    except Exception as e:  # noqa: BLE001
        err(f"{path.relative_to(ROOT)}: cannot parse JSON ({e})")
        return None


def check_syllabus():
    grammar = load(SYL / "grammar.json")
    a1 = load(SYL / "a1.json")
    s0 = load(SYL / "stage0.json")
    grammar_a2 = load(SYL / "grammar_a2.json")
    a2 = load(SYL / "a2.json")
    if not (grammar and a1 and s0 and grammar_a2 and a2):
        return None
    ids = [p["id"] for p in grammar["points"]]
    if len(ids) != len(set(ids)):
        err("grammar.json: duplicate grammar ids")
    order = {gid: i for i, gid in enumerate(ids)}

    seen_intro = {}
    unit_ids = []
    total = 0
    required = ["id", "title", "situation", "can_do", "grammar_new", "grammar_review",
                "new_words_target", "word_themes", "canada_context", "canada_vs_france", "tcf_corner"]
    for idx, unit in enumerate(a1["units"], start=1):
        uid = unit.get("id", f"#{idx}")
        for field in required:
            if field not in unit or unit[field] in (None, ""):
                err(f"{uid}: missing field '{field}'")
        if uid != f"a1-u{idx:02d}":
            err(f"{uid}: unit ids must be sequential (expected a1-u{idx:02d})")
        unit_ids.append(uid)
        total += unit.get("new_words_target", 0)
        for gid in unit.get("grammar_new", []):
            if gid not in order:
                err(f"{uid}: unknown grammar id {gid}")
            elif gid in seen_intro:
                err(f"{uid}: {gid} already introduced in {seen_intro[gid]}")
            else:
                seen_intro[gid] = uid
        for gid in unit.get("grammar_review", []):
            if gid not in order:
                err(f"{uid}: unknown grammar id {gid} in review")
            elif gid not in seen_intro:
                err(f"{uid}: reviews {gid} before it is introduced")
        tc = unit.get("tcf_corner", {})
        for k in ("listening", "reading", "speaking", "writing"):
            if k not in tc:
                err(f"{uid}: tcf_corner missing '{k}'")
    for gid in ids:
        if gid not in seen_intro:
            err(f"grammar {gid} is never introduced in A1")
    if total != a1.get("word_target_total"):
        warn(f"a1.json: word_target_total {a1.get('word_target_total')} != sum of units {total}")
    for mock in a1.get("mini_mocks", []):
        if mock["after_unit"] not in unit_ids:
            err(f"mini mock {mock['id']}: unknown unit {mock['after_unit']}")
    mock_ids = {m["id"] for m in a1.get("mini_mocks", [])}
    for unit in a1["units"]:
        ref = unit.get("mini_mock_after")
        if ref and ref not in mock_ids:
            err(f"{unit['id']}: mini_mock_after {ref} not defined")

    # A2 extends the A1 grammar and vocabulary ledger. Reviews may use A1
    # grammar at the start, then only A2 points introduced in an earlier unit.
    a1_grammar_ids = set(ids)
    a2_ids = [p.get("id") for p in grammar_a2.get("points", [])]
    if len(a2_ids) != len(set(a2_ids)):
        err("grammar_a2.json: duplicate grammar ids")
    overlap = a1_grammar_ids & set(a2_ids)
    if overlap:
        err(f"grammar_a2.json: ids overlap A1 grammar: {', '.join(sorted(overlap))}")
    if a2.get("stage") != "A2":
        err("a2.json: stage must be A2")
    if a2.get("a1_cumulative_words") != a1.get("word_target_total"):
        err("a2.json: a1_cumulative_words must match the A1 cumulative target")
    a2_required = required + ["learning_loop", "transfer_check"]
    introduced_a2 = set()
    a2_unit_ids = []
    a2_word_total = 0
    for idx, unit in enumerate(a2.get("units", []), start=1):
        uid = unit.get("id", f"#{idx}")
        for field in a2_required:
            if field not in unit or unit[field] in (None, ""):
                err(f"{uid}: missing field '{field}'")
        if uid != f"a2-u{idx:02d}":
            err(f"{uid}: unit ids must be sequential (expected a2-u{idx:02d})")
        a2_unit_ids.append(uid)
        a2_word_total += unit.get("new_words_target", 0)
        for gid in unit.get("grammar_new", []):
            if gid not in a2_ids:
                err(f"{uid}: unknown A2 grammar id {gid}")
            elif gid in introduced_a2:
                err(f"{uid}: {gid} already introduced in an earlier A2 unit")
            else:
                introduced_a2.add(gid)
        prior_grammar = a1_grammar_ids | introduced_a2
        for gid in unit.get("grammar_review", []):
            if gid not in a1_grammar_ids and gid not in a2_ids:
                err(f"{uid}: unknown grammar id {gid} in review")
            elif gid not in prior_grammar:
                err(f"{uid}: reviews {gid} before it is introduced")
        tc = unit.get("tcf_corner", {})
        for k in ("listening", "reading", "speaking", "writing"):
            if k not in tc:
                err(f"{uid}: tcf_corner missing '{k}'")
    if len(a2.get("units", [])) != 12:
        err(f"a2.json: expected 12 planned units, found {len(a2.get('units', []))}")
    if a2_word_total != a2.get("new_word_target"):
        err(f"a2.json: new_word_target {a2.get('new_word_target')} != sum of units {a2_word_total}")
    if a2.get("cumulative_word_target") != a2.get("a1_cumulative_words", 0) + a2_word_total:
        err("a2.json: cumulative_word_target must equal A1 target plus A2 new words")
    for gid in a2_ids:
        if gid not in introduced_a2:
            err(f"A2 grammar {gid} is never introduced")

    s0_ids = [lesson["id"] for lesson in s0["lessons"]]
    if len(s0_ids) != len(set(s0_ids)):
        err("stage0.json: duplicate lesson ids")
    slots = [t["kind"] for t in a1["unit_template"]]
    return {"a1": a1, "a2": a2, "slots": slots, "total": total,
            "a2_total": a2_word_total, "s0": len(s0_ids)}


FUNCTION_WORDS = set(
    "le la les l un une des de du d à au aux et ou mais est sont suis es ai as a ce c cet cette ces je j tu il elle on nous vous ils elles "
    "me m te t se s mon ma mes ton ta tes son sa ses notre votre leur leurs ne n pas que qu qui où en y dans sur sous chez avec sans pour par "
    "oui non merci bonjour".split()
)
FR_KEYS = {"fr", "french", "target", "sentence", "line", "partner_french", "prompt", "text_fr", "example_fr"}


def collect_french(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in FR_KEYS and isinstance(v, str):
                out.append(v)
            else:
                collect_french(v, out)
    elif isinstance(node, list):
        for v in node:
            collect_french(v, out)


def tokens(text):
    return [t.lower() for t in re.findall(r"[a-zA-ZÀ-ÿœŒ]+", text)]


def check_units(info, strict):
    if not UNITS.exists():
        return 0
    files = sorted(UNITS.rglob("unit.json"))
    known = set()
    for f in files:
        rel = f.relative_to(ROOT)
        unit = load(f)
        if not unit:
            continue
        lessons = unit.get("lessons", [])
        kinds = [x.get("kind") for x in lessons]
        if kinds != info["slots"]:
            err(f"{rel}: lessons must be {info['slots']}, got {kinds}")
        for lesson in lessons:
            if lesson.get("kind") in ("words_a", "words_b"):
                words = lesson.get("words", [])
                if len(words) != 5:
                    err(f"{rel}: {lesson.get('id')} must have exactly 5 words, has {len(words)}")
        new_words = {w["fr"].lower() for w in unit.get("new_words", []) if "fr" in w}
        allowed = known | new_words | FUNCTION_WORDS
        french = []
        collect_french(lessons, french)
        unknown = sorted({t for s in french for t in tokens(s)} - allowed)
        if unknown:
            msg = f"{rel}: {len(unknown)} words used before taught: {', '.join(unknown[:15])}"
            (err if strict else warn)(msg)
        audio = f.parent / "audio.json"
        if not audio.exists():
            err(f"{rel}: audio.json missing (bake list)")
        else:
            manifest = load(audio) or {}
            listed = {c["text"] for c in manifest.get("clips", [])}
            missing = sorted({s.strip() for s in french if s.strip()} - listed)
            if missing:
                err(f"{rel}: {len(missing)} French strings not in audio.json, e.g. {missing[:3]}")
        known |= new_words
    return len(files)



APP_CONTENT = ROOT.parent.parent / "flutter_app" / "assets" / "content" / "tcf"
STEP_TYPES = {"explain", "word", "phrase", "choose", "listen", "table"}


def _need(step, key, where):
    v = step.get(key)
    if not (isinstance(v, str) and v.strip()):
        err(f"{where}: missing or empty '{key}'")
        return ""
    return v


def check_lessons():
    """Validates the lesson files the app plays (same rules as V3Lesson.fromJson)
    and returns (lesson_count, french_line_count)."""
    index_path = APP_CONTENT / "course.json"
    if not index_path.exists():
        return 0, 0
    index = load(index_path) or {}
    files = index.get("lessons", [])
    seen_ids, lines = set(), 0
    for name in files:
        path = APP_CONTENT / "lessons" / name
        if not path.exists():
            err(f"course.json lists {name} but the file does not exist")
            continue
        lesson = load(path)
        if not lesson:
            continue
        lid = lesson.get("id", name)
        where = f"lesson {lid}"
        if lid in seen_ids:
            err(f"{where}: duplicate lesson id")
        seen_ids.add(lid)
        _need(lesson, "title", where)
        if not lesson.get("dev"):
            _need(lesson, "unit", where)
            _need(lesson, "unitTitle", where)
        steps = lesson.get("steps")
        if not isinstance(steps, list) or not steps:
            err(f"{where}: has no steps")
            continue
        ids = set()
        for step in steps:
            sid = step.get("id")
            sw = f"{where} step {sid}"
            if not sid or sid in ids:
                err(f"{sw}: missing or duplicate step id")
            ids.add(sid)
            kind = step.get("type")
            if kind not in STEP_TYPES:
                err(f"{sw}: unknown type {kind!r}")
                continue
            fr = []
            if kind == "explain":
                _need(step, "title", sw); _need(step, "body", sw)
                for ex in step.get("examples", []):
                    fr.append(_need(ex, "fr", sw)); _need(ex, "en", sw)
            elif kind == "word":
                fr.append(_need(step, "fr", sw)); _need(step, "en", sw)
                if step.get("exampleFr"):
                    fr.append(step["exampleFr"])
                    _need(step, "exampleEn", sw)
            elif kind == "phrase":
                fr.append(_need(step, "fr", sw)); _need(step, "en", sw)
            elif kind == "table":
                _need(step, "title", sw)
                hdr = step.get("headers")
                rows = step.get("rows")
                if not (isinstance(hdr, list) and len(hdr) >= 2 and isinstance(rows, list) and rows):
                    err(f"{sw}: table needs headers (2+) and rows")
                else:
                    for r in rows:
                        if not (isinstance(r, list) and len(r) == len(hdr)):
                            err(f"{sw}: a table row has the wrong number of cells")
                            break
                    hear = step.get("hear", -1)
                    if hear != -1 and not (isinstance(hear, int) and 0 <= hear < len(hdr)):
                        err(f"{sw}: bad hear column")
                    elif isinstance(hear, int) and hear >= 0 and isinstance(rows, list):
                        for r in rows:
                            if isinstance(r, list) and len(r) > hear:
                                fr.append(r[hear])
            elif kind in ("choose", "listen"):
                if kind == "choose":
                    _need(step, "prompt", sw)
                    if step.get("promptFr"):
                        fr.append(step["promptFr"])
                else:
                    fr.append(_need(step, "fr", sw)); _need(step, "question", sw)
                opts = step.get("options")
                if not (isinstance(opts, list) and len(opts) >= 2 and all(isinstance(o, str) and o.strip() for o in opts)):
                    err(f"{sw}: needs at least 2 non-empty options")
                elif len(set(opts)) != len(opts):
                    err(f"{sw}: options must be different from each other")
                ans = step.get("answer")
                if not (isinstance(ans, int) and isinstance(opts, list) and 0 <= ans < len(opts)):
                    err(f"{sw}: answer must be a valid option index")
                if not step.get("explain"):
                    warn(f"{sw}: no 'explain' text for the feedback bar")
            for text in fr:
                lines += 1
                # A B2 reading item can carry a short original passage in
                # promptFr. Keep ordinary voiced examples compact, but allow
                # a bounded passage here so the learner can read and hear the
                # full text before answering its comprehension question.
                limit = 1200 if kind == "choose" and step.get("promptFr") == text else 220
                if len(text) > limit:
                    err(f"{sw}: French line is over {limit} characters")
        if lesson.get("dev"):
            warn(f"{where}: is marked dev (hidden in release builds)")
    return len(seen_ids), lines


STRIP = "«»\"“”‘’'.,!?;:()—–…"


def story_tokens(text):
    """Word tokens of a French sentence, exactly as the reader makes them:
    split on spaces, trim punctuation from the ends, lowercase."""
    out = []
    for raw in text.replace("\u2019", "'").split():
        t = raw.strip(STRIP).lower()
        if t:
            out.append(t)
    return out


def check_stories():
    """Validates authored reading/listening stories and their tap glosses."""
    index_path = APP_CONTENT / "stories.json"
    if not index_path.exists():
        return 0, 0
    index = load(index_path) or {}
    seen, lines = set(), 0
    for catalog_key in ("stories", "listeningStories"):
        catalog = index.get(catalog_key, [])
        level_counts = {level: 0 for level in ("A1", "A2", "B1", "B2")}
        for name in catalog:
            path = APP_CONTENT / "stories" / name
            if not path.exists():
                err(f"stories.json lists {name} but the file does not exist")
                continue
            st = load(path)
            if not st:
                continue
            sid = st.get("id", name)
            w = f"story {sid}"
            if sid in seen:
                err(f"{w}: duplicate story id")
            seen.add(sid)
            for key in ("title", "titleEn", "summary"):
                _need(st, key, w)
            if st.get("level") not in ("A1", "A2", "B1", "B2"):
                err(f"{w}: level must be A1, A2, B1 or B2")
            elif catalog_key == "listeningStories":
                level_counts[st["level"]] += 1
                if st.get("mode") != "listening":
                    err(f"{w}: listening catalog entry must declare mode=\"listening\"")
            if not isinstance(st.get("minutes"), int):
                err(f"{w}: minutes must be a whole number")
            sents = st.get("sentences", [])
            if st.get("level") == "A1" and not 6 <= len(sents) <= 12:
                warn(f"{w}: A1 stories are usually 6 to 12 sentences (has {len(sents)})")
            words = st.get("words", {})
            used = set()
            for i, sent in enumerate(sents, 1):
                fr, en = sent.get("fr", ""), sent.get("en", "")
                if not fr.strip() or not en.strip():
                    err(f"{w} sentence {i}: needs both fr and en")
                    continue
                lines += 1
                toks = story_tokens(fr)
                if st.get("level") == "A1" and len(toks) > 12:
                    warn(f"{w} sentence {i}: {len(toks)} words is long for A1")
                for t in toks:
                    used.add(t)
                    if t not in words:
                        err(f"{w} sentence {i}: word '{t}' has no meaning in 'words'")
            for t, entry in words.items():
                if not (isinstance(entry, dict) and str(entry.get("en", "")).strip()):
                    err(f"{w}: word '{t}' has an empty meaning")
                if t not in used:
                    warn(f"{w}: word '{t}' is not used in any sentence")
            kws = st.get("keywords", [])
            if not 4 <= len(kws) <= 8:
                warn(f"{w}: keywords usually 4 to 8 (has {len(kws)})")
            for k in kws:
                if k not in words:
                    err(f"{w}: keyword '{k}' is not in 'words'")
            quiz = st.get("quiz", [])
            if len(quiz) < 3:
                err(f"{w}: needs at least 3 quiz questions")
            for j, q in enumerate(quiz, 1):
                qw = f"{w} quiz {j}"
                _need(q, "prompt", qw)
                _need(q, "explain", qw)
                opts = q.get("options")
                if not (
                    isinstance(opts, list)
                    and len(opts) >= 2
                    and all(isinstance(o, str) and o.strip() for o in opts)
                ):
                    err(f"{qw}: needs at least 2 non-empty options")
                    continue
                if len(opts) != 4:
                    warn(f"{qw}: TCF questions have 4 options (has {len(opts)})")
                if len(set(opts)) != len(opts):
                    err(f"{qw}: options must be different from each other")
                ans = q.get("answer")
                if not (isinstance(ans, int) and 0 <= ans < len(opts)):
                    err(f"{qw}: answer must be a valid option index")
        if catalog_key == "listeningStories" and level_counts != {level: 5 for level in level_counts}:
            err(f"listeningStories must contain five stories per CEFR level; found {level_counts}")
    return len(seen), lines

def main():
    strict = "--strict-ledger" in sys.argv
    info = check_syllabus()
    n_units = check_units(info, strict) if info else 0
    n_lessons, n_lines = check_lessons()
    n_stories, n_story_lines = check_stories()
    for w in warnings:
        print("warn :", w)
    for e in errors:
        print("ERROR:", e)
    if info:
        print(f"syllabus: stage0 {info['s0']} lessons, A1 {len(info['a1']['units'])} units, "
              f"{info['total']} target words; A2 {len(info['a2']['units'])} planned units, "
              f"{info['a2_total']} new-word target; {n_units} legacy authored unit file(s)")
    print(f"lessons: {n_lessons} file(s), {n_lines} French lines to voice")
    print(f"stories: {n_stories} file(s), {n_story_lines} sentences")
    print(f"content validation: {len(errors)} error(s), {len(warnings)} warning(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
