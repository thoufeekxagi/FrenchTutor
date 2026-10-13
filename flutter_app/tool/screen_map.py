#!/usr/bin/env python3
"""Static screen map and testability lint.

  python3 tool/screen_map.py            regenerate docs/v3/SCREEN_MAP.md
  python3 tool/screen_map.py --check    lint lib/v3 only (exit 1 on findings)
  python3 tool/screen_map.py --find X   grep the map for a screen, key or label

Why: never guess where a button lives or what it is called. Read the map, then
read the file. Every interactive widget in lib/v3 must carry a stable
`ValueKey('screen.element')` or a Semantics label so on-device tests and the
probe can target it.
"""
import re
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
LIB = APP / "lib"
OUT = APP.parent / "docs" / "v3" / "SCREEN_MAP.md"

CLASS_RE = re.compile(
    r"^class\s+(\w+)\s+extends\s+(?:Stateless|Stateful|Consumer|ConsumerStateful|Hook)\w*Widget\b", re.M
)
KEY_RE = re.compile(r"""(?:Value)?Key\(\s*['"]([^'"]+)['"]\s*\)""")
LABEL_RE = re.compile(r"""(?:label|semanticLabel|semanticsLabel|tooltip)\s*:\s*['"]([^'"$]{2,80})['"]""")
PUSH_RE = re.compile(r"AppRouter\.(?:push|replace|pushReplacement)\w*(?:<[^>]*>)?\(\s*\w+\s*,\s*\(\w*\)\s*=>\s*(?:const\s+)?(\w+)")
TAP_RE = re.compile(r"\b(onTap|onPressed|onLongPress|onChanged|onSubmitted)\s*:")
GUARD_RE = re.compile(r"key\s*:|Semantics\(|semanticLabel|tooltip\s*:|label\s*:|Key\(|^\s*_\w+\(", re.M)


def scan(path):
    text = path.read_text(errors="ignore")
    return {
        "classes": CLASS_RE.findall(text),
        "keys": sorted(set(KEY_RE.findall(text))),
        "labels": sorted(set(LABEL_RE.findall(text)))[:25],
        "pushes": sorted(set(PUSH_RE.findall(text))),
        "taps": len(TAP_RE.findall(text)),
    }


# One design everywhere: these are the only ways a v3 screen may style text,
# colour and buttons. Each entry is (pattern, what to use instead).
CONSISTENCY_RULES = [
    (re.compile(r"GoogleFonts"), "use V3Type (one font family app wide), not GoogleFonts"),
    (re.compile(r"fontFamily\s*:"), "use V3Type, not fontFamily"),
    (re.compile(r"fontSize\s*:"), "set size through V3Type(size), not TextStyle(fontSize:)"),
    (re.compile(r"Color\(\s*0x|Color\.fromARGB|Color\.fromRGBO"), "use DesignTokens / AppearanceColors, not a raw colour"),
    (re.compile(r"\b(ElevatedButton|FilledButton|OutlinedButton|TextButton)\s*\("), "use V3Button / V3TextAction (one button design)"),
]


def lint_v3():
    root = LIB / "v3"
    findings = []
    if not root.exists():
        return findings
    for path in sorted(root.rglob("*.dart")):
        lines = path.read_text(errors="ignore").splitlines()
        for i, line in enumerate(lines):
            code = line.strip()
            if not code.startswith("//"):
                for pattern, advice in CONSISTENCY_RULES:
                    if pattern.search(code):
                        findings.append(f"{path.relative_to(APP)}:{i + 1}: {advice}")
            if TAP_RE.search(line) and "onChanged" not in line:
                window = "\n".join(lines[max(0, i - 14): i + 3])
                if not GUARD_RE.search(window):
                    findings.append(f"{path.relative_to(APP)}:{i + 1}: interactive widget has no key/Semantics/label nearby")
    return findings


def build_map():
    rows = []
    for path in sorted(LIB.rglob("*.dart")):
        rel = path.relative_to(APP).as_posix()
        if "/screens/" not in rel and "/v3/" not in rel and "/widgets/" not in rel:
            continue
        info = scan(path)
        if not info["classes"]:
            continue
        rows.append((rel, info))
    out = ["# Screen map (generated)", "",
           "Regenerate with `python3 flutter_app/tool/screen_map.py`. Do not edit by hand.",
           "Rule: read this, then read the file. Never assume a key, label or route.", ""]
    for rel, info in rows:
        out.append(f"## `{rel}`")
        out.append(f"- widgets: {', '.join(info['classes'])}")
        if info["pushes"]:
            out.append(f"- opens: {', '.join(info['pushes'])}")
        out.append(f"- tap handlers: {info['taps']}")
        if info["keys"]:
            out.append(f"- keys: {', '.join('`'+k+'`' for k in info['keys'])}")
        if info["labels"]:
            out.append(f"- labels: {', '.join(repr(x) for x in info['labels'])}")
        out.append("")
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    if "--check" in args:
        findings = lint_v3()
        for f in findings:
            print(f)
        print(f"v3 testability lint: {len(findings)} finding(s)")
        sys.exit(1 if findings else 0)
    text = build_map()
    if "--find" in args:
        needle = args[args.index("--find") + 1].lower()
        block = []
        for chunk in text.split("\n## "):
            if needle in chunk.lower():
                block.append("## " + chunk.strip())
        print("\n\n".join(block) or f"no match for {needle!r}")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text + "\n")
    print(f"wrote {OUT.relative_to(APP.parent)} ({text.count(chr(10)) } lines)")


if __name__ == "__main__":
    main()
