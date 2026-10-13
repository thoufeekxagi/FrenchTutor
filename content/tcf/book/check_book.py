#!/usr/bin/env python3
"""Quality checks for the A1 book.

  python3 content/tcf/book/check_book.py

1. Ledger: every French word in a dialogue, story, listening script or reading
   text must already have been taught (a word table, a grammar table, a phrase,
   an example sentence) earlier in the book, or be a proper name.
2. Structure: every question has 4 options (listening/reading), a valid answer
   index, distinct options and an explanation; exercises have answers.
Run after every chapter. Exit code 1 on structural errors; ledger gaps are
listed as WARN so you can decide: teach the word, or change the sentence.
"""
import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
STRIP = "«»\"“”‘’'.,!?;:()—–…·/"
PROPER = {"sam", "marc", "léa", "anna", "nadia", "julie", "karim", "priya", "awa", "samira", "diallo",
          "haddad", "tremblay", "gagnon", "karine", "wei", "montréal", "ottawa", "toronto", "gatineau",
          "québec", "vancouver", "lyon", "sainte-anne", "paris", "dakar", "rabat", "mallette", "ahmed",
          "fatou", "luc", "jean", "marie", "sophie", "ali", "omar", "chen", "li", "singh", "tran"}


def toks(text):
    out = []
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
    chapters = []
    for path in sorted((HERE / "chapters").glob("[0-9][0-9]_*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        chapters.append(mod.CHAPTER)
    return chapters


def main():
    chapters = load()
    known, errors, warns = set(PROPER), [], []

    def teach(text):
        for t in toks(text):
            for p in split_elision(t):
                known.add(p)

    def need(text, where):
        if where.startswith('Stage 0'):
            return  # Stage 0 listening is about sounds; unknown words are expected
        missing = []
        for t in toks(text):
            if re.fullmatch(r"[\d,.%$ ]+", t) or not re.search(r"[a-zà-ÿœ]", t):
                continue
            if not any(p in known for p in split_elision(t)):
                missing.append(t)
        if missing:
            warns.append(f"{where}: not taught yet: {', '.join(sorted(set(missing)))}")

    seen_ids = set()
    for ch in chapters:
        if ch["id"] in seen_ids:
            errors.append(f"duplicate chapter id {ch['id']}")
        seen_ids.add(ch["id"])
        for b in ch["blocks"]:
            k = b[0]
            where = f"{ch['label']}"
            if k == "words":
                for fr, snd, en, exf, exe in b[1]:
                    teach(fr)
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
    for w in warns:
        print("WARN :", w)
    for e in errors:
        print("ERROR:", e)
    print(f"{len(chapters)} chapters, {len(known)} known tokens, {len(warns)} ledger warning(s), {len(errors)} error(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
