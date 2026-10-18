#!/usr/bin/env python3
"""Build a dated draft challenge calendar from authored course questions.

Generated packages are drafts. A human TCF editor must review each one and
record review_status=approved, reviewed_by and reviewed_at before production
publishing. This script does not add generated packages to the Flutter bundle.
"""

from __future__ import annotations

import argparse
import copy
import csv
import json
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COURSE_DIR = ROOT / "flutter_app/assets/content/tcf/lessons"
OUTPUT_ROOT = ROOT / "content/tcf/daily_challenges"
LEVELS = ("a1", "a2", "b1", "b2")


def read_lesson(level: str, unit: int, mode: str) -> dict:
    lesson_id = f"{level}-u{unit:02d}-{mode}"
    path = COURSE_DIR / f"{lesson_id}.json"
    try:
        lesson = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot load authored source {path}: {error}") from error
    lesson["_source_lesson_id"] = lesson_id
    return lesson


def questions(lesson: dict, kind: str) -> list[dict]:
    return [
        step
        for step in lesson.get("steps", [])
        if isinstance(step, dict)
        and step.get("type") == kind
        and isinstance(step.get("options"), list)
        and len(step["options"]) >= 2
        and isinstance(step.get("answer"), int)
        and 0 <= step["answer"] < len(step["options"])
    ]


def select_source(level: str, day_index: int) -> tuple[dict, str, str]:
    # Three-day blocks keep a single unit topic together: listen, read, then
    # use the matching TCF-corner items. The TCF skill alternates by unit.
    block = day_index // 3
    unit = block + 1
    mode = ("listening", "reading", "tcf")[day_index % 3]
    lesson = read_lesson(level, unit, mode)
    if mode == "listening":
        kind = "listen"
    elif mode == "reading":
        kind = "choose"
    else:
        kind = "choose" if unit % 2 == 1 else "listen"
    if len(questions(lesson, kind)) < 2:
        kind = "listen" if kind == "choose" else "choose"
    if len(questions(lesson, kind)) < 2:
        raise ValueError(
            f"{lesson['_source_lesson_id']} has fewer than two supported "
            "questions of either type."
        )
    skill = "Listening" if kind == "listen" else "Reading"
    return lesson, kind, skill


def topic_for(lesson: dict) -> str:
    topic = lesson.get("unitTitle") or lesson.get("unit_title") or lesson.get("unit")
    if not isinstance(topic, str) or not topic.strip():
        topic = lesson.get("title", "French practice")
    return topic.strip()


def package_for(level: str, day: date, day_index: int) -> dict:
    source, kind, skill = select_source(level, day_index)
    topic = topic_for(source)
    mode = ("listening", "reading", "tcf")[day_index % 3]
    prefix = {
        "listening": "Listen",
        "reading": "Read",
        "tcf": "TCF practice",
    }[mode]
    title = f"{prefix}: {topic}"
    lower_topic = topic[0].lower() + topic[1:] if topic else "this topic"
    summary = {
        "Listening": f"Listen for two key details about {lower_topic}.",
        "Reading": f"Read for two key details about {lower_topic}.",
    }[skill]
    selected = copy.deepcopy(questions(source, kind)[:2])
    for index, step in enumerate(selected, start=1):
        step["id"] = f"question-{index}"
    labels = (
        ["Listen for a detail", "Listen for one more detail"]
        if kind == "listen"
        else ["Read the text", "Check what you understood"]
    )
    challenge_id = f"{level}-{day.isoformat()}-{mode}-u{day_index // 3 + 1:02d}"
    return {
        "id": challenge_id,
        "revision": 1,
        "available_on": day.isoformat(),
        "author": "ParleSprint Editorial · draft schedule",
        "review_status": "needs_human_review",
        "review_note": (
            "Composed from existing authored course questions. A TCF editor "
            "must verify the task, distractors, language level, answer key, "
            "and Canadian context before production."
        ),
        "level": level,
        "primary_skill": skill,
        "title": title,
        "summary": summary,
        "minutes": 3 if level in ("a1", "a2") else 4,
        "steps": labels,
        "source_lesson_ids": [source["_source_lesson_id"]],
        "lesson": {
            "id": f"daily-{challenge_id}",
            "title": title,
            "subtitle": f"{level.upper()} · {skill} · {3 if level in ('a1', 'a2') else 4} min",
            "minutes": 3 if level in ("a1", "a2") else 4,
            "steps": selected,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--start-date",
        type=date.fromisoformat,
        default=date.today() + timedelta(days=1),
        help="First learner-local availability date (default: tomorrow).",
    )
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument(
        "--levels",
        default=",".join(LEVELS),
        help="Comma-separated CEFR levels (default: a1,a2,b1,b2).",
    )
    args = parser.parse_args()
    levels = tuple(level.strip().lower() for level in args.levels.split(","))
    if args.days < 1 or args.days > 90:
        parser.error("--days must be between 1 and 90")
    if not levels or any(level not in LEVELS for level in levels):
        parser.error("--levels must contain a1, a2, b1, or b2")

    end_date = args.start_date + timedelta(days=args.days - 1)
    output_dir = OUTPUT_ROOT / f"schedule_{args.start_date.isoformat()}"
    if output_dir.exists() and any(output_dir.iterdir()):
        parser.error(f"Refusing to overwrite existing schedule: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, str]] = []
    for day_index in range(args.days):
        available_on = args.start_date + timedelta(days=day_index)
        for level in levels:
            package = package_for(level, available_on, day_index)
            path = output_dir / f"{package['id']}.json"
            path.write_text(
                json.dumps(package, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            rows.append(
                {
                    "available_on": available_on.isoformat(),
                    "level": level,
                    "primary_skill": package["primary_skill"],
                    "title": package["title"],
                    "source_lesson_id": package["source_lesson_ids"][0],
                    "review_status": package["review_status"],
                    "package": path.name,
                }
            )

    with (output_dir / "schedule.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (output_dir / "README.md").write_text(
        f"# Daily TCF challenge drafts: {args.start_date} to {end_date}\n\n"
        f"This schedule has {args.days} dated packages per level ({len(rows)} total) "
        "built from existing authored course questions. Every package is marked "
        "`needs_human_review`; none is approved or published. A TCF editor must "
        "review the content and record reviewer metadata before production. "
        "The validator and GitHub workflow check package shape and dates, while "
        "the Supabase Edge Function keeps answer keys private and records "
        "signed-in learner answers.\n",
        encoding="utf-8",
    )
    print(f"Created {len(rows)} draft packages in {output_dir}")
    print(f"Dates: {args.start_date} through {end_date}")
    print("Review status: needs_human_review for every package")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
