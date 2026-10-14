#!/usr/bin/env python3
"""Quality gate for the authored B1 syllabus, source and exported app lessons.

Run after `python3 content/tcf/book/export_app.py`:
  python3 content/tcf/tools/validate_b1.py

Use --source-only to check the hand-authored source without an app export.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / "book"
APP = ROOT.parent.parent / "flutter_app" / "assets" / "content" / "tcf"
sys.path.insert(0, str(BOOK))

from b1_source import B1_ENTRY_DIAGNOSTIC, GRAMMAR_BY_UNIT, UNITS, build_unit  # noqa: E402


WORD = re.compile(r"\b[\wÀ-ÿœŒ’'-]+\b")
WRITE_RANGES = {"1": (60, 120), "2": (120, 150), "3": (120, 180)}


def count_words(text):
    return len(WORD.findall(text or ""))


def question_errors(errors, uid, field, items, options_at, answer_at):
    for number, item in enumerate(items, 1):
        try:
            options, answer, explanation = item[options_at], item[answer_at], item[answer_at + 1]
        except (IndexError, TypeError):
            errors.append(f"{uid}: malformed {field} item {number}")
            continue
        if len(options) != 4 or len(set(options)) != 4:
            errors.append(f"{uid}: {field} item {number} needs four distinct options")
        if not isinstance(answer, int) or not 0 <= answer < 4:
            errors.append(f"{uid}: {field} item {number} has invalid answer {answer!r}")
        if not isinstance(explanation, str) or not explanation.strip():
            errors.append(f"{uid}: {field} item {number} needs an evidence-based explanation")


def main():
    errors = []
    source_only = "--source-only" in sys.argv
    syllabus_path = ROOT / "syllabus" / "b1.json"
    grammar_path = ROOT / "syllabus" / "grammar_b1.json"
    syllabus = json.loads(syllabus_path.read_text(encoding="utf-8"))
    grammar = json.loads(grammar_path.read_text(encoding="utf-8"))
    units = syllabus.get("units", [])
    points = grammar.get("points", [])
    point_ids = [p.get("id") for p in points]
    if len(units) != 12:
        errors.append(f"b1.json: expected 12 units, found {len(units)}")
    if len(UNITS) != len(units):
        errors.append(f"B1 source has {len(UNITS)} units; syllabus has {len(units)}")
    if len(point_ids) != len(set(point_ids)):
        errors.append("grammar_b1.json: duplicate grammar ids")
    if len(GRAMMAR_BY_UNIT) != len(units):
        errors.append("B1 source grammar map does not match the syllabus length")

    introduced = set()
    required = ("id", "title", "situation", "can_do", "grammar_new", "grammar_review",
                "word_themes", "canada_context", "learning_loop", "transfer_check", "tcf_corner")
    for index, unit in enumerate(units, 1):
        uid = f"b1-u{index:02d}"
        if unit.get("id") != uid:
            errors.append(f"b1.json: unit {index} must have id {uid}")
        for field in required:
            value = unit.get(field)
            if field not in unit or value is None or value == "" or (value == [] and field != "grammar_new"):
                errors.append(f"{uid}: missing syllabus field {field}")
        if unit.get("core_focus_words_target") != 30:
            errors.append(f"{uid}: B1 focus vocabulary target must match the 30 authored terms")
        if index <= len(GRAMMAR_BY_UNIT) and unit.get("grammar_new") != GRAMMAR_BY_UNIT[index - 1]:
            errors.append(f"{uid}: syllabus grammar_new does not match the authored source order")
        for gid in unit.get("grammar_new", []):
            if gid not in point_ids:
                errors.append(f"{uid}: unknown grammar id {gid}")
            if gid in introduced:
                errors.append(f"{uid}: grammar point {gid} is introduced more than once")
            introduced.add(gid)
        for gid in unit.get("grammar_review", []):
            if gid in point_ids and gid not in introduced:
                errors.append(f"{uid}: reviews {gid} before it is introduced")
        for skill in ("listening", "reading", "speaking", "writing"):
            if skill not in unit.get("tcf_corner", {}):
                errors.append(f"{uid}: TCF corner missing {skill}")
        if index > len(UNITS):
            continue
        source = UNITS[index - 1]
        vocab = [row[0].strip().casefold() for row in source.get("vocab", [])]
        if len(vocab) != 30 or len(set(vocab)) != 30:
            errors.append(f"{uid}: expected 30 distinct contextual focus terms")
        for row in source.get("vocab", []):
            if len(row) != 5 or not all(isinstance(x, str) and x.strip() for x in row):
                errors.append(f"{uid}: each vocabulary row needs French, sound, meaning and bilingual context")
        chunks = [row[0].strip().casefold() for row in source.get("chunks", [])]
        if len(chunks) != 8 or len(set(chunks)) != 8:
            errors.append(f"{uid}: expected eight distinct reusable chunks")
        for field, expected in (("dialogues", 2), ("listening", 3), ("reading", 3),
                                ("grammar_q", 3), ("checkpoint", 5)):
            if len(source.get(field, [])) < expected:
                errors.append(f"{uid}: expected at least {expected} {field} items")
        if len(source.get("grammar_rows", [])) < 3:
            errors.append(f"{uid}: grammar needs at least three meaning-to-form examples")
        for dialogue in source.get("dialogues", []):
            if len(dialogue) != 3 or len(dialogue[2]) < 5:
                errors.append(f"{uid}: each dialogue needs a setting and at least five bilingual turns")
            elif any(len(line) != 3 or not line[1].strip() or not line[2].strip() for line in dialogue[2]):
                errors.append(f"{uid}: dialogue turns need speaker and bilingual lines")
        question_errors(errors, uid, "grammar_q", source.get("grammar_q", []), 1, 2)
        question_errors(errors, uid, "checkpoint", source.get("checkpoint", []), 1, 2)
        question_errors(errors, uid, "listening", source.get("listening", []), 2, 3)
        question_errors(errors, uid, "reading", source.get("reading", []), 2, 3)
        write_tasks = [source.get("write", {}), *source.get("write_extra", [])]
        for task in write_tasks:
            kind = str(task.get("kind", ""))
            if kind not in WRITE_RANGES:
                errors.append(f"{uid}: unknown writing task kind {kind!r}")
                continue
            length = count_words(task.get("model", ""))
            lo, hi = WRITE_RANGES[kind]
            if not lo <= length <= hi:
                errors.append(f"{uid}: Task {kind} model has {length} words; expected {lo}–{hi}")
            if not task.get("prompt", "").strip() or not task.get("checklist"):
                errors.append(f"{uid}: writing task needs a prompt and checklist")
        for task in [source.get("speak", {}), *source.get("speak_extra", [])]:
            if not task.get("prompt", "").strip() or not task.get("model", "").strip() or not task.get("tips"):
                errors.append(f"{uid}: speaking practice needs prompt, model and guidance")
        if index <= 11 and len(GRAMMAR_BY_UNIT[index - 1]) == 1 and not source.get("grammar_body", "").strip():
            errors.append(f"{uid}: missing plain-language grammar explanation")

    never_introduced = set(point_ids) - introduced
    if never_introduced:
        errors.append("B1 grammar never introduced: " + ", ".join(sorted(never_introduced)))
    if not (60 <= count_words(B1_ENTRY_DIAGNOSTIC["write"]["model"]) <= 120):
        errors.append("B1 entry writing diagnostic should be a 60–120-word Task 1 baseline")
    for field in ("listening", "reading"):
        if len(B1_ENTRY_DIAGNOSTIC.get(field, [])) < 3:
            errors.append(f"B1 entry diagnostic needs at least three {field} items")
        question_errors(errors, "B1 entry diagnostic", field,
                        B1_ENTRY_DIAGNOSTIC.get(field, []), 2, 3)
    capstone_speaking = " ".join(
        " ".join([x.get("prompt", ""), *x.get("tips", [])]) for x in UNITS[-1].get("speak_extra", [])
    )
    if "not a comparison" not in capstone_speaking or "4 minutes 30" not in capstone_speaking:
        errors.append("B1 capstone must distinguish the short oral Task 3 practice from the official format")

    indexed_b1 = []
    if not source_only:
        course_path = APP / "course.json"
        if not course_path.exists():
            errors.append("app course.json is missing; export the authored chapters first")
            files = []
        else:
            files = json.loads(course_path.read_text(encoding="utf-8")).get("lessons", [])
        indexed_b1 = [name for name in files if name.startswith("b1-u")]
        expected_count = 12 * 13 + 1
        if len(indexed_b1) != expected_count:
            errors.append(f"expected {expected_count} indexed B1 lessons including entry diagnostic, found {len(indexed_b1)}")
        positions = {
            level: [i for i, name in enumerate(files) if name.startswith(level + "-")]
            for level in ("a1", "a2", "b1", "b2")
        }
        for level, indices in positions.items():
            if not indices:
                errors.append(f"course.json is missing {level.upper()} lessons")
        for earlier, later in (("a1", "a2"), ("a2", "b1"), ("b1", "b2")):
            if positions[earlier] and positions[later] and max(positions[earlier]) > min(positions[later]):
                errors.append(f"course order must place {earlier.upper()} before {later.upper()}")
        if not files or not any(name.startswith("b2-u") for name in files):
            errors.append("B2 lesson index is missing from the course")
        elif max((i for i, name in enumerate(files) if name.startswith("b1-u")), default=-1) > min(
                (i for i, name in enumerate(files) if name.startswith("b2-u")), default=-1):
            errors.append("B1 lessons must be ordered before B2 lessons")
        for index in range(1, 13):
            prefix = f"b1-u{index:02d}-"
            found = [name for name in indexed_b1 if name.startswith(prefix)]
            if index == 1 and f"{prefix}diagnostic.json" not in found:
                errors.append("b1-u01: missing four-skill entry diagnostic")
            for kind in ("words-1", "words-2", "words-3", "words-4", "words-5", "phrases", "grammar-a", "dialogues",
                         "listening", "reading", "write-speak", "tcf", "checkpoint"):
                name = f"{prefix}{kind}.json"
                if name not in found:
                    errors.append(f"{prefix[:-1]}: app index is missing {name}")
                elif not (APP / "lessons" / name).exists():
                    errors.append(f"course.json lists missing B1 app lesson {name}")
        for name in indexed_b1:
            path = APP / "lessons" / name
            if not path.exists():
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            for step in data.get("steps", []):
                if step.get("type") not in {"choose", "listen"}:
                    continue
                options, answer = step.get("options", []), step.get("answer")
                if len(options) != 4 or len(set(options)) != 4 or not isinstance(answer, int) or not 0 <= answer < 4:
                    errors.append(f"{name} {step.get('id')}: invalid four-choice item")
        for index in range(1, 13):
            for group in range(1, 6):
                name = f"b1-u{index:02d}-words-{group}.json"
                if not (APP / "lessons" / name).exists():
                    continue
                data = json.loads((APP / "lessons" / name).read_text(encoding="utf-8"))
                steps = data.get("steps", [])
                if sum(step.get("type") == "word" for step in steps) != 6:
                    errors.append(f"{name}: each short vocabulary set must teach six terms")
                if sum(step.get("type") == "choose" for step in steps) != 6:
                    errors.append(f"{name}: each vocabulary set must include six retrieval checks")
        for index in range(1, 13):
            data = json.loads((APP / "lessons" / f"b1-u{index:02d}-write-speak.json").read_text(encoding="utf-8"))
            text = "\n".join(
                " ".join([step.get("title", ""), step.get("body", "")])
                for step in data.get("steps", []) if step.get("type") == "explain"
            )
            # The exact authored word-range is enforced at source level; exported
            # content must still expose every prompt and model.
            if "Writing: TCF Task" not in text or "Model answer" not in text:
                errors.append(f"b1-u{index:02d}: exported writing lesson is missing prompt or model")

    for error in errors:
        print("ERROR:", error)
    if errors:
        return 1
    suffix = "source" if source_only else f"{len(indexed_b1)} app lessons"
    print(f"B1 {suffix} check: 12 units, 30 focus terms per unit, {len(point_ids)} grammar targets, Task 1/2 models in range")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
