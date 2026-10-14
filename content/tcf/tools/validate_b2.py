#!/usr/bin/env python3
"""B2-specific checks for syllabus/source-to-app wiring.

Run after `python3 content/tcf/book/export_app.py`:
  python3 content/tcf/tools/validate_b2.py

The general content validator checks all app lesson schemas and question keys.
This additional gate ensures the complete 14-unit B2 source is represented in
the app index, that grammar is introduced in order, and that sample writing
models respect the assigned official task ranges.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / "book"
APP = ROOT.parent.parent / "flutter_app" / "assets" / "content" / "tcf"
sys.path.insert(0, str(BOOK))
sys.path.insert(0, str(BOOK / "chapters"))

from b2_source import B2_ENTRY_DIAGNOSTIC, UNITS, build_unit  # noqa: E402


def main():
    errors = []
    source_only = "--source-only" in sys.argv
    syllabus = json.loads((ROOT / "syllabus" / "b2.json").read_text(encoding="utf-8"))
    grammar = json.loads((ROOT / "syllabus" / "grammar_b2.json").read_text(encoding="utf-8"))
    units = syllabus.get("units", [])
    points = grammar.get("points", [])
    point_ids = [p.get("id") for p in points]
    if len(units) != 14:
        errors.append(f"b2.json: expected 14 units, found {len(units)}")
    if len(point_ids) != len(set(point_ids)):
        errors.append("grammar_b2.json: duplicate grammar ids")
    if len(UNITS) != len(units):
        errors.append(f"B2 source: {len(UNITS)} authored units do not match the {len(units)}-unit syllabus")
    if syllabus.get("new_focus_word_target") != 420:
        errors.append("B2 syllabus must state the 420-term authored focus-bank target")

    entry = build_unit(1)["blocks"]
    entry_sections = [b for b in entry if b[0] == "h2" and ".0 B2 readiness check" in b[1]]
    if len(entry_sections) != 1:
        errors.append("B2 Unit 1 must contain exactly one entry readiness check")
    if set(B2_ENTRY_DIAGNOSTIC) != {"listening", "reading", "write", "speak"}:
        errors.append("B2 entry diagnostic must cover listening, reading, writing and speaking")
    baseline_words = len(re.findall(r"\b[\wÀ-ÿœŒ’'-]+\b", B2_ENTRY_DIAGNOSTIC["write"]["model"]))
    if not 80 <= baseline_words <= 100:
        errors.append(f"B2 entry writing model has {baseline_words} words; expected 80–100")

    for unit_index in range(1, len(UNITS) + 1):
        for block in build_unit(unit_index)["blocks"]:
            if block[0] != "mcq":
                continue
            answers = [item.get("answer") for item in block[5]]
            if len(answers) >= 3 and len(set(answers)) < 2:
                errors.append(f"{block[1]}: correct answers are concentrated in one option position")

    introduced = set()
    required = ("id", "title", "situation", "can_do", "grammar_new", "grammar_review",
                "word_themes", "canada_context", "transfer_check", "tcf_corner")
    for index, unit in enumerate(units, 1):
        uid = f"b2-u{index:02d}"
        if unit.get("id") != uid:
            errors.append(f"b2.json: unit {index} must have id {uid}")
        if unit.get("core_focus_words_target") != 30:
            errors.append(f"{uid}: syllabus target must match the 30 authored focus terms")
        if unit.get("reusable_chunks_target") != 8:
            errors.append(f"{uid}: syllabus target must match the eight authored chunks")
        for field in required:
            value = unit.get(field)
            if field not in unit or value is None or (isinstance(value, str) and not value.strip()):
                errors.append(f"{uid}: missing syllabus field {field}")
        for gid in unit.get("grammar_new", []):
            if gid not in point_ids:
                errors.append(f"{uid}: unknown grammar id {gid}")
            if gid in introduced:
                errors.append(f"{uid}: grammar point {gid} is introduced more than once")
            introduced.add(gid)
        for gid in unit.get("grammar_review", []):
            if gid not in point_ids:
                errors.append(f"{uid}: unknown grammar review {gid}")
            elif gid not in introduced:
                errors.append(f"{uid}: reviews {gid} before introduction")
        for skill in ("listening", "reading", "speaking", "writing"):
            if skill not in unit.get("tcf_corner", {}):
                errors.append(f"{uid}: TCF corner missing {skill}")
        if index <= len(UNITS):
            source = UNITS[index - 1]
            vocab = [row[0].strip().casefold() for row in source.get("vocab", [])]
            if len(vocab) != 30:
                errors.append(f"{uid}: expected 30 contextual focus terms, found {len(vocab)}")
            if len(set(vocab)) != len(vocab):
                errors.append(f"{uid}: duplicate focus words in the same unit")
            for row in source.get("vocab", []):
                if len(row) != 5 or not all(isinstance(value, str) and value.strip() for value in row):
                    errors.append(f"{uid}: each focus word needs French, sound guide, meaning and a bilingual example")
            for field, expected in (("chunks", 8), ("dialogues", 2), ("listening", 3),
                                    ("reading", 3), ("grammar_q", 3), ("checkpoint", 5)):
                actual = len(source.get(field, []))
                if actual < expected:
                    errors.append(f"{uid}: expected at least {expected} {field} items, found {actual}")
            if len(source.get("grammar_rows", [])) < 3:
                errors.append(f"{uid}: grammar table needs at least three meaning-to-form examples")
            for dialogue in source.get("dialogues", []):
                if len(dialogue) != 3 or len(dialogue[2]) < 5 or any(
                    len(line) != 3 or not line[1].strip() or not line[2].strip()
                    for line in dialogue[2]
                ):
                    errors.append(f"{uid}: each dialogue needs at least five bilingual turns")
            question_groups = (("listening", 2, 3), ("reading", 2, 3),
                               ("grammar_q", 1, 2), ("checkpoint", 1, 2))
            for field, options_at, answer_at in question_groups:
                for question in source.get(field, []):
                    options, answer = question[options_at], question[answer_at]
                    explanation = question[answer_at + 1]
                    if len(options) != 4 or len(set(options)) != 4:
                        errors.append(f"{uid}: {field} question must have four distinct choices")
                    if not isinstance(answer, int) or not 0 <= answer < 4:
                        errors.append(f"{uid}: {field} question has invalid answer index {answer!r}")
                    if not explanation.strip():
                        errors.append(f"{uid}: {field} question needs an explanation")
            for field in ("write", "speak"):
                assignment = source.get(field, {})
                if not assignment.get("prompt", "").strip() or not assignment.get("model", "").strip():
                    errors.append(f"{uid}: {field} task needs a prompt and model")
            for assignment in [source.get("write", {}), *source.get("write_extra", [])]:
                kind = str(assignment.get("kind", ""))
                limits = {"1": (60, 120), "2": (120, 150), "3": (120, 180)}
                if kind not in limits:
                    errors.append(f"{uid}: unknown writing task kind {kind!r}")
                    continue
                count = len(re.findall(r"\b[\wÀ-ÿœŒ’'-]+\b", assignment.get("model", "")))
                lo, hi = limits[kind]
                if not lo <= count <= hi:
                    errors.append(f"{uid}: Task {kind} model has {count} words; expected {lo}–{hi}")

    missing_grammar = set(point_ids) - introduced
    if missing_grammar:
        errors.append("B2 grammar never introduced: " + ", ".join(sorted(missing_grammar)))

    indexed_b2 = []
    if not source_only:
        course_path = APP / "course.json"
        if not course_path.exists():
            errors.append("app course.json is missing; export the authored chapters first")
            files = []
        else:
            files = json.loads(course_path.read_text(encoding="utf-8")).get("lessons", [])
        indexed_b2 = [name for name in files if name.startswith("b2-u")]
        if not indexed_b2:
            errors.append("no B2 lesson files are indexed in app course.json; run export_app.py")
        for index, unit in enumerate(units, 1):
            prefix = f"b2-u{index:02d}-"
            found = [name for name in indexed_b2 if name.startswith(prefix)]
            if index == 1:
                diagnostic = f"{prefix}diagnostic.json"
                if diagnostic not in found:
                    errors.append(f"b2-u01: app index is missing the four-skill entry diagnostic")
                elif not (APP / "lessons" / diagnostic).exists():
                    errors.append(f"course.json lists missing app lesson {diagnostic}")
            expected_kinds = ("words-1", "words-2", "words-3", "words-4", "words-5", "phrases", "grammar-a", "dialogues",
                              "listening", "reading", "write-speak", "tcf", "checkpoint")
            for kind in expected_kinds:
                name = f"{prefix}{kind}.json"
                if name not in found:
                    errors.append(f"{prefix[:-1]}: app index is missing {name}")
                elif not (APP / "lessons" / name).exists():
                    errors.append(f"course.json lists missing app lesson {name}")
        if len(indexed_b2) != 14 * 13 + 1:
            errors.append(f"expected 183 indexed B2 lessons, found {len(indexed_b2)}")
        for index in range(1, 15):
            for group in range(1, 6):
                name = f"b2-u{index:02d}-words-{group}.json"
                if not (APP / "lessons" / name).exists():
                    continue
                data = json.loads((APP / "lessons" / name).read_text(encoding="utf-8"))
                steps = data.get("steps", [])
                if sum(step.get("type") == "word" for step in steps) != 6:
                    errors.append(f"{name}: each short vocabulary set must teach six terms")
                if sum(step.get("type") == "choose" for step in steps) != 6:
                    errors.append(f"{name}: each vocabulary set must include six retrieval checks")

        # Authored quiz distractors must not leave every correct response in
        # the first answer slot. Validate the same bundled JSON the app reads.
        for name in indexed_b2:
            if not name.endswith(("-diagnostic.json", "-grammar-a.json", "-listening.json",
                                  "-reading.json", "-tcf.json", "-checkpoint.json")):
                continue
            data = json.loads((APP / "lessons" / name).read_text(encoding="utf-8"))
            answers = [step.get("answer") for step in data.get("steps", [])
                       if step.get("type") in {"choose", "listen"}]
            if len(answers) >= 3 and len(set(answers)) < 2:
                errors.append(f"{name}: correct answers are concentrated in one option position")
            for answer in answers:
                if not isinstance(answer, int) or not 0 <= answer < 4:
                    errors.append(f"{name}: invalid four-choice answer index {answer!r}")

    for error in errors:
        print("ERROR:", error)
    if not errors:
        suffix = "source" if source_only else f"{len(indexed_b2)} app lessons"
        print(f"B2 {suffix} check: {len(units)} units, 30 focus terms per unit, {len(point_ids)} grammar targets; writing model ranges pass")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
