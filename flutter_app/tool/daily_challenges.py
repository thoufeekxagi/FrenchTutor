#!/usr/bin/env python3
"""Validate and publish authored daily challenge packages.

Publish using separate Supabase project credentials in environment variables:
DAILY_CHALLENGE_STAGING_URL / DAILY_CHALLENGE_STAGING_SERVICE_ROLE_KEY or
DAILY_CHALLENGE_PRODUCTION_URL / DAILY_CHALLENGE_PRODUCTION_SERVICE_ROLE_KEY.
The service key is read only by this local tool and is never written to disk.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import date
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LEVELS = {"a1", "a2", "b1", "b2"}
SKILLS = {"Listening", "Reading", "Speaking", "Writing"}
STEP_TYPES = {"explain", "word", "phrase", "table", "choose", "listen"}


def load_package(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read package: {error}") from error
    if not isinstance(value, dict):
        raise ValueError("Package root must be an object.")
    return value


def validate(package: dict, available_on: str | None = None) -> list[str]:
    errors: list[str] = []
    for field in ("id", "level", "primary_skill", "title", "summary"):
        if not isinstance(package.get(field), str) or not package[field].strip():
            errors.append(f"{field} must be a non-empty string")
    if package.get("level") not in LEVELS:
        errors.append("level must be a1, a2, b1, or b2")
    if package.get("primary_skill") not in SKILLS:
        errors.append("primary_skill must be Listening, Reading, Speaking, or Writing")
    minutes = package.get("minutes")
    if not isinstance(minutes, int) or not 1 <= minutes <= 15:
        errors.append("minutes must be an integer from 1 to 15")
    labels = package.get("steps")
    if not isinstance(labels, list) or not 1 <= len(labels) <= 6 or any(
        not isinstance(label, str) or not label.strip() for label in labels
    ):
        errors.append("steps must contain 1 to 6 non-empty labels")
    sources = package.get("source_lesson_ids", [])
    if not isinstance(sources, list) or any(not isinstance(item, str) for item in sources):
        errors.append("source_lesson_ids must be a list of lesson ids")

    lesson = package.get("lesson")
    if not isinstance(lesson, dict):
        errors.append("lesson must be a renderer-compatible V3 lesson object")
        lesson_steps = []
    else:
        for field in ("id", "title"):
            if not isinstance(lesson.get(field), str) or not lesson[field].strip():
                errors.append(f"lesson.{field} must be a non-empty string")
        lesson_steps = lesson.get("steps")
        if not isinstance(lesson_steps, list) or not 1 <= len(lesson_steps) <= 6:
            errors.append("lesson.steps must contain 1 to 6 steps")
            lesson_steps = []
    if isinstance(labels, list) and isinstance(lesson_steps, list) and len(labels) != len(lesson_steps):
        errors.append("steps labels must match lesson.steps one-for-one")

    seen: set[str] = set()
    for index, step in enumerate(lesson_steps):
        where = f"lesson.steps[{index}]"
        if not isinstance(step, dict):
            errors.append(f"{where} must be an object")
            continue
        step_id = step.get("id")
        if not isinstance(step_id, str) or not step_id.strip():
            errors.append(f"{where}.id must be a non-empty string")
        elif step_id in seen:
            errors.append(f"duplicate step id: {step_id}")
        else:
            seen.add(step_id)
        kind = step.get("type")
        if kind not in STEP_TYPES:
            errors.append(f"{where}.type is not supported by the V3 renderer")
            continue
        if kind in {"choose", "listen"}:
            options = step.get("options")
            answer = step.get("answer")
            if not isinstance(options, list) or len(options) < 2 or any(
                not isinstance(option, str) or not option.strip() for option in options
            ):
                errors.append(f"{where}.options must contain at least two strings")
            elif not isinstance(answer, int) or not 0 <= answer < len(options):
                errors.append(f"{where}.answer must index an existing option")
        if kind == "listen" and any(
            not isinstance(step.get(field), str) or not step[field].strip()
            for field in ("fr", "question")
        ):
            errors.append(f"{where} listening steps need French audio text and a question")
        if kind == "choose" and not isinstance(step.get("prompt"), str):
            errors.append(f"{where} choose steps need a prompt")
        if kind == "explain" and any(
            not isinstance(step.get(field), str) or not step[field].strip()
            for field in ("title", "body")
        ):
            errors.append(f"{where} explain steps need a title and body")
        if kind == "word" and any(
            not isinstance(step.get(field), str) or not step[field].strip()
            for field in ("fr", "en")
        ):
            errors.append(f"{where} word steps need French and English text")
        if kind == "table":
            headers = step.get("headers")
            rows = step.get("rows")
            if not isinstance(headers, list) or len(headers) < 2 or any(
                not isinstance(value, str) for value in headers
            ):
                errors.append(f"{where} table steps need at least two string headers")
            if not isinstance(rows, list) or not rows or any(
                not isinstance(row, list)
                or len(row) != len(headers if isinstance(headers, list) else [])
                or any(not isinstance(value, str) for value in row)
                for row in (rows if isinstance(rows, list) else [])
            ):
                errors.append(f"{where} table rows must match the header count")
        if kind == "phrase" and any(
            not isinstance(step.get(field), str) or not step[field].strip()
            for field in ("fr", "en")
        ):
            errors.append(f"{where} phrase steps need French and English text")

    revision = package.get("revision", 1)
    if not isinstance(revision, int) or revision < 1:
        errors.append("revision must be a positive integer")
    day = available_on or package.get("available_on")
    if day is not None:
        try:
            if not isinstance(day, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
                raise ValueError
            date.fromisoformat(day)
        except (TypeError, ValueError):
            errors.append("available_on must use YYYY-MM-DD")
    if not package.get("author"):
        errors.append("author is required for the content record")
    return errors


def _public_content(package: dict) -> dict:
    content = {
        key: value
        for key, value in package.items()
        if key not in {"answer_key", "author", "reviewed_by", "reviewed_at", "status"}
    }
    content["lesson"] = dict(package["lesson"])
    content["lesson"]["steps"] = []
    for original in package["lesson"]["steps"]:
        step = dict(original)
        if step.get("type") in {"choose", "listen"}:
            # V3Lesson requires a bounded answer index. The Edge Function ignores
            # this placeholder and checks against answer_key_json server-side.
            step["answer"] = 0
        content["lesson"]["steps"].append(step)
    return content


def _answer_key(package: dict) -> dict:
    return {
        step["id"]: {
            "index": step["answer"],
            "explanation": step.get("explain", ""),
        }
        for step in package["lesson"]["steps"]
        if step.get("type") in {"choose", "listen"}
    }


def publish(
    package: dict, environment: str, available_on: str, dry_run: bool = False
) -> dict | None:
    prefix = f"DAILY_CHALLENGE_{environment.upper()}"
    url = os.environ.get(f"{prefix}_URL", "").rstrip("/")
    service_key = os.environ.get(f"{prefix}_SERVICE_ROLE_KEY", "")
    if not dry_run and (not url or not service_key):
        raise ValueError(
            f"Set {prefix}_URL and {prefix}_SERVICE_ROLE_KEY before publishing."
        )
    if environment == "production" and not all(
        package.get(field) for field in ("reviewed_by", "reviewed_at")
    ):
        raise ValueError("Production publishing requires reviewed_by and reviewed_at.")
    if environment == "production" and package.get("review_status") != "approved":
        raise ValueError("Production publishing requires review_status=approved.")

    errors = validate(package, available_on)
    if errors:
        raise ValueError("Package validation failed:\n- " + "\n- ".join(errors))

    payload = {
        "challenge_key": package["id"],
        "revision": package.get("revision", 1),
        "level_band": package["level"],
        "primary_skill": package["primary_skill"],
        "available_on": available_on,
        "title": package["title"],
        "summary": package["summary"],
        "minutes": package["minutes"],
        "step_labels": package["steps"],
        "source_lesson_ids": package.get("source_lesson_ids", []),
        "content_json": _public_content(package),
        "answer_key_json": _answer_key(package),
        "status": "preview" if environment == "staging" else "published",
        "scheduled_at": package.get("scheduled_at"),
        "author": package["author"],
        "reviewed_by": package.get("reviewed_by"),
        "reviewed_at": package.get("reviewed_at"),
    }
    if dry_run:
        return payload
    endpoint = (
        f"{url}/rest/v1/daily_challenge_versions"
        f"?on_conflict=challenge_key%2Crevision"
    )
    request = Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=25) as response:
            if response.status not in (200, 201, 204):
                raise ValueError(f"Supabase returned HTTP {response.status}.")
    except HTTPError as error:
        body = error.read(1000).decode("utf-8", errors="replace")
        raise ValueError(f"Supabase rejected the publish ({error.code}): {body}") from error
    except URLError as error:
        raise ValueError(f"Could not reach the configured Supabase project: {error.reason}") from error
    return None


def approve_schedule(directory: Path, reviewer: str) -> int:
    """Stamp every package in a schedule as reviewed. A person runs this after
    reading the content; the tool never approves anything by itself."""
    from datetime import datetime, timezone

    if not reviewer.strip():
        raise ValueError("--by must name the human reviewer.")
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    count = 0
    for path in sorted(directory.rglob("*.json")):
        package = load_package(path)
        if "lesson" not in package:
            continue
        package["review_status"] = "approved"
        package["reviewed_by"] = reviewer.strip()
        package["reviewed_at"] = stamp
        path.write_text(
            json.dumps(package, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        count += 1
    return count


def publish_schedule(
    directory: Path,
    environment: str,
    from_date: date,
    days: int,
    dry_run: bool = False,
) -> tuple[int, int]:
    if not directory.is_dir():
        raise ValueError(f"Schedule directory does not exist: {directory}")
    until = from_date.fromordinal(from_date.toordinal() + days - 1)
    selected: list[tuple[Path, dict]] = []
    skipped_for_review = 0
    for path in sorted(directory.rglob("*.json")):
        package = load_package(path)
        available_on = package.get("available_on")
        if not isinstance(available_on, str):
            continue
        try:
            scheduled_date = date.fromisoformat(available_on)
        except ValueError:
            continue
        if not from_date <= scheduled_date <= until:
            continue
        if environment == "production" and (
            package.get("review_status") != "approved"
            or not package.get("reviewed_by")
            or not package.get("reviewed_at")
        ):
            skipped_for_review += 1
            continue
        errors = validate(package)
        if errors:
            raise ValueError(
                f"Package validation failed for {path}:\n- "
                + "\n- ".join(errors)
            )
        selected.append((path, package))

    if not selected:
        print(
            f"No eligible {environment} packages from {from_date} through {until}. "
            f"Skipped {skipped_for_review} package(s) awaiting human review."
        )
        return 0, skipped_for_review

    for path, package in selected:
        available_on = package["available_on"]
        publish(package, environment, available_on, dry_run=dry_run)
        verb = "Would publish" if dry_run else "Published"
        print(f"{verb} {package['id']} to {environment} for {available_on}.")
    if skipped_for_review:
        print(f"Skipped {skipped_for_review} package(s) awaiting human review.")
    return len(selected), skipped_for_review


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    check = subparsers.add_parser("validate", help="Check a challenge package")
    check.add_argument("package", type=Path)
    bundle = subparsers.add_parser("bundle", help="Copy the approved local package into Flutter assets")
    bundle.add_argument("package", type=Path)
    stage = subparsers.add_parser("publish", help="Publish to a separate Supabase project")
    stage.add_argument("package", type=Path)
    stage.add_argument("--environment", choices=("staging", "production"), required=True)
    stage.add_argument("--available-on", help="Local availability date, YYYY-MM-DD")
    schedule = subparsers.add_parser(
        "publish-schedule",
        help="Publish staged packages in a date window; production skips drafts",
    )
    schedule.add_argument("directory", type=Path)
    schedule.add_argument("--environment", choices=("staging", "production"), required=True)
    schedule.add_argument("--from-date", type=date.fromisoformat, default=date.today())
    schedule.add_argument("--days", type=int, default=30)
    schedule.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and build the exact rows, but send nothing",
    )
    approve = subparsers.add_parser(
        "approve", help="Mark every package in a schedule as reviewed by a person"
    )
    approve.add_argument("directory", type=Path)
    approve.add_argument("--by", required=True, help="Name of the human reviewer")
    args = parser.parse_args(argv)

    try:
        if args.command == "approve":
            count = approve_schedule(args.directory, args.by)
            print(f"Marked {count} package(s) approved by {args.by}.")
            return 0
        if args.command == "publish-schedule":
            if args.days < 1 or args.days > 90:
                raise ValueError("--days must be between 1 and 90.")
            publish_schedule(
                args.directory,
                args.environment,
                args.from_date,
                args.days,
                dry_run=args.dry_run,
            )
            return 0
        package = load_package(args.package)
        errors = validate(package, getattr(args, "available_on", None))
        if errors:
            print("Package validation failed:", file=sys.stderr)
            for error in errors:
                print(f"- {error}", file=sys.stderr)
            return 1
        if args.command == "validate":
            print(f"Valid: {package['id']} · {len(package['lesson']['steps'])} steps")
            return 0
        if args.command == "bundle":
            target = Path(__file__).resolve().parents[1] / "assets/content/tcf/daily_challenges" / args.package.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(package, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"Bundled {package['id']} to {target.relative_to(Path(__file__).resolve().parents[1])}.")
            return 0
        available_on = args.available_on or package.get("available_on")
        if not available_on:
            raise ValueError("Provide --available-on or set available_on in the package.")
        publish(package, args.environment, available_on)
        print(f"Published {package['id']} to {args.environment} for {available_on}.")
        return 0
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
