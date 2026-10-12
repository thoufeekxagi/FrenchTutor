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
    if not (grammar and a1 and s0):
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
    s0_ids = [lesson["id"] for lesson in s0["lessons"]]
    if len(s0_ids) != len(set(s0_ids)):
        err("stage0.json: duplicate lesson ids")
    slots = [t["kind"] for t in a1["unit_template"]]
    return {"a1": a1, "slots": slots, "total": total, "s0": len(s0_ids)}


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


def main():
    strict = "--strict-ledger" in sys.argv
    info = check_syllabus()
    n_units = check_units(info, strict) if info else 0
    for w in warnings:
        print("warn :", w)
    for e in errors:
        print("ERROR:", e)
    if info:
        print(f"syllabus: stage0 {info['s0']} lessons, A1 {len(info['a1']['units'])} units, "
              f"{info['total']} target words, {n_units} authored unit file(s)")
    print(f"content validation: {len(errors)} error(s), {len(warnings)} warning(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
