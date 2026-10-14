#!/usr/bin/env python3
"""Quality checks for the authored A1 and A2 course chapters.

  python3 content/tcf/book/check_book.py

1. Ledger: every French word in a dialogue, story, listening script or reading
   text must already have been taught (a word table, a grammar table, a phrase,
   an example sentence) earlier in the book, or be a proper name.
2. Structure: every question has 4 options (listening/reading), a valid answer
   index, distinct options and an explanation; exercises have answers.
Run after every chapter. For authored A2 units, also check the syllabus word
target and reject repeated word entries from A1 or an earlier A2 unit. Exit
code 1 on structural errors; ledger gaps are listed as WARN so you can decide:
teach the word, or change the sentence.
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
STRIP = "«»\"“”‘’'.,!?;:()—–…·/"
PROPER = {"sam", "marc", "léa", "anna", "nadia", "julie", "karim", "priya", "awa", "samira", "diallo",
          "haddad", "tremblay", "gagnon", "karine", "wei", "montréal", "ottawa", "toronto", "gatineau",
          "québec", "vancouver", "lyon", "sainte-anne", "paris", "dakar", "rabat", "mallette", "ahmed",
          "fatou", "yasmine", "patel", "moncton", "érables", "service", "canada", "luc", "jean", "marie", "sophie", "ali", "omar", "chen", "li", "singh", "tran"}


def toks(text):
    out = []
    text = text.replace('(e)', '').replace('(ne)', '')
    for raw in text.replace("\u2019", "'").replace("’", "'").split():
        t = raw.strip(STRIP).lower()
        if t:
            out.append(t)
    return out


def split_elision(t):
    """j'habite -> j', habite ; also the full token itself is accepted."""
    parts = [t]
    if "'" in t:
        a, _, b = t.partition("'")
        parts += [a + "'", b]
    if "-" in t:
        parts += t.split("-")
    return parts


def load():
    """Load Stage 0, A1 and A2 chapters for the A1/A2-only exporter callers."""
    chapters = []
    for path in sorted((HERE / "chapters").glob("[0-9][0-9]_*.py")):
        # Later stages are deliberately outside this A1/A2 ledger check.
        if "_b1_" in path.name or "_b2_" in path.name:
            continue
        spec = importlib.util.spec_from_file_location(path.stem, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        chapter = mod.CHAPTER
        if chapter["id"] == "s0" or chapter["id"].startswith(("a1-", "a2-")):
            chapters.append(chapter)
    return chapters


def load_all():
    """Load every authored stage in numeric source order for export and checks."""
    chapters = []
    for path in sorted((HERE / "chapters").glob("[0-9][0-9]_*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        chapter = mod.CHAPTER
        if chapter["id"] == "s0" or chapter["id"].split("-", 1)[0] in {"a1", "a2", "b1", "b2"}:
            chapters.append(chapter)
    return chapters


def main():
    chapters = load()
    known, errors, warns, notes = set(PROPER), [], [], []
    syllabus_path = HERE.parent / "syllabus" / "a2.json"
    a2_targets = {}
    if syllabus_path.exists():
        a2_targets = {u["id"]: u["new_words_target"]
                      for u in json.loads(syllabus_path.read_text(encoding="utf-8")).get("units", [])}
    # A2 word groups must add the planned number of genuinely new entries.
    # Phrases and grammar examples are excluded from the new-word count.
    seen_vocabulary = {
        row[0].strip().casefold()
        for ch in chapters if ch["id"].startswith("a1-")
        for b in ch["blocks"] if b[0] == "words"
        for row in b[1]
    }
    a2_authored = 0

    def teach(text):
        for t in toks(text):
            for p in split_elision(t):
                known.add(p)

    def need(text, where):
        if where.startswith('Stage 0'):
            return  # Stage 0 listening is about sounds; unknown words are expected
        missing = []
        for t in toks(text):
            if re.fullmatch(r"[\d,.%$ ]+", t) or not re.search(r"[a-zà-ÿœ]", t) or re.fullmatch(r"[a-z]\d[a-z]|\d[a-z]\d", t):
                continue
            if not any(p in known for p in split_elision(t)):
                missing.append(t)
        if missing:
            line = f"{where}: not taught yet: {', '.join(sorted(set(missing)))}"
            # Example sentences often show a verb form or a feminine form that
            # the same unit's grammar explains a few pages later. That is normal
            # teaching order, so they are reported as notes, not warnings.
            (notes if " example of " in where else warns).append(line)

    seen_ids = set()
    section = ''
    for ch in chapters:
        if ch["id"] in seen_ids:
            errors.append(f"duplicate chapter id {ch['id']}")
        seen_ids.add(ch["id"])
        for b in ch["blocks"]:
            k = b[0]
            where = f"{ch['label']}"
            if k == "h2":
                section = b[1]
            if k == "words":
                for fr, snd, en, exf, exe in b[1]:
                    teach(fr)
                    # Every word the learner studies needs a sentence that shows
                    # it in use (phrase lists are sentences already).
                    if "Phrases" not in section and not exf.strip():
                        errors.append(f"{where}: word without an example sentence: {fr}")
                    if exf.strip() and not exe.strip():
                        errors.append(f"{where}: example without English: {exf}")
                    if exf.strip() and "Phrases" not in section:
                        need(exf, f"{where} example of '{fr}'")
                    teach(exf)
                    if not snd.strip():
                        errors.append(f"{where}: word without sound guide: {fr}")
                    if not en.strip():
                        errors.append(f"{where}: word without meaning: {fr}")
            elif k == "table":
                for row in b[2]:
                    for c in row:
                        teach(c)
            elif k == "dialogue":
                for who, fr, en in b[3]:
                    need(fr, f"{where} dialogue '{b[1]}'")
                    teach(fr)
            elif k == "story":
                for fr, en in b[3]:
                    need(fr, f"{where} story '{b[1]}'")
                    teach(fr)
            elif k == "text":
                need(b[1], f"{where} text")
                teach(b[1])
            elif k == "mcq":
                _, eid, title, qkind, intro, items = b
                for n, it in enumerate(items, 1):
                    w = f"{where} {eid} q{n}"
                    opts = it.get("options", [])
                    if len(opts) != 4:
                        errors.append(f"{w}: needs 4 options (has {len(opts)})")
                    if len(set(opts)) != len(opts):
                        errors.append(f"{w}: duplicate options")
                    a = it.get("answer")
                    if not (isinstance(a, int) and 0 <= a < len(opts)):
                        errors.append(f"{w}: bad answer index")
                    if not it.get("explain", "").strip():
                        errors.append(f"{w}: no explanation")
                    if qkind == "listening":
                        if not it.get("script"):
                            errors.append(f"{w}: listening item without script")
                        else:
                            need(it["script"], f"{w} script")
                            teach(it["script"])
                    if qkind == "reading" and it.get("text"):
                        need(it["text"], f"{w} text")
                        teach(it["text"])
            elif k == "exercise":
                for q, a in b[4]:
                    if not str(a).strip():
                        errors.append(f"{where} {b[1]}: item without answer: {q}")
            elif k in ("write", "speak"):
                need(b[4], f"{where} {b[1]} model")
                teach(b[4])
        if ch["id"].startswith("a2-"):
            a2_authored += 1
            target = a2_targets.get(ch["id"])
            unit_words, section = [], ""
            for b in ch["blocks"]:
                if b[0] == "h2":
                    section = b[1]
                elif b[0] == "words" and re.match(r"^\d+\.1\s+Words\b", section):
                    unit_words.extend(row[0].strip().casefold() for row in b[1])
            if target is None:
                errors.append(f"{ch['label']}: no matching A2 syllabus target for {ch['id']}")
            elif len(unit_words) != target:
                errors.append(f"{ch['label']}: syllabus expects {target} new word entries, found {len(unit_words)}")
            if len(unit_words) != len(set(unit_words)):
                errors.append(f"{ch['label']}: duplicate new word entries within the unit")
            repeated = sorted(set(unit_words) & seen_vocabulary)
            if repeated:
                errors.append(f"{ch['label']}: word entries already taught: {', '.join(repeated[:10])}")
            seen_vocabulary.update(unit_words)
    if "--verbose" in sys.argv:
        for n in notes:
            print("NOTE :", n)
    for w in warns:
        print("WARN :", w)
    for e in errors:
        print("ERROR:", e)
    print(
        f"{len(chapters)} chapters ({a2_authored} A2 authored), {len(known)} known tokens, {len(warns)} ledger "
        f"warning(s), {len(notes)} example note(s) (--verbose to list), {len(errors)} error(s)"
    )
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
