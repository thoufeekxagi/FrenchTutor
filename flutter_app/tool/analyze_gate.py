#!/usr/bin/env python3
"""Run flutter analyze and fail only on NEW errors or warnings.

Baseline: tool/known_analyzer_issues.txt (one normalized issue per line).
Infos are ignored. Line and column numbers are stripped so unrelated edits
above an old issue do not make it look new.

  python3 tool/analyze_gate.py            gate
  python3 tool/analyze_gate.py --update   rewrite the baseline (review the diff!)
"""
import re, subprocess, sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
BASE = APP / "tool" / "known_analyzer_issues.txt"
LINE = re.compile(r"^\s*(error|warning)\s+•\s+(.*?)\s+•\s+(\S+?):\d+:\d+\s+•\s+(\S+)\s*$")

out = subprocess.run(["flutter", "analyze", "--no-pub", "--no-fatal-infos"],
                     cwd=APP, capture_output=True, text=True).stdout
now = sorted({f"{m[1]}|{m[2]}|{m[3]}|{m[4]}" for l in out.splitlines() if (m := LINE.match(l))})
if "--update" in sys.argv:
    BASE.write_text("\n".join(now) + "\n")
    print(f"baseline written: {len(now)} issues")
    sys.exit(0)
known = set(BASE.read_text().splitlines()) if BASE.exists() else set()
new = [i for i in now if i not in known]
gone = [i for i in known if i not in set(now)]
print(f"analyzer: {len(now)} errors/warnings now, {len(known)} in baseline")
for i in new:
    print("NEW  :", i)
for i in gone:
    print("fixed:", i, "(remove from baseline with --update)")
sys.exit(1 if new else 0)
