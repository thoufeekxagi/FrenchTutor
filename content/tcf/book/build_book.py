#!/usr/bin/env python3
"""Builds the A1 book PDF from content/tcf/book/chapters/*.py.

  python3 content/tcf/book/build_book.py          # HTML + PDF
Output: docs/v3/book/ParleSprint_A1_Book.(html|pdf)
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from book_lib import render_book  # noqa: E402
from front import FRONT  # noqa: E402

OUT = HERE.parents[2] / "docs" / "v3" / "book"
OUT.mkdir(parents=True, exist_ok=True)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def load_chapters():
    chapters = []
    for path in sorted((HERE / "chapters").glob("[0-9][0-9]_*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        # This script builds the A1 reference PDF. Keep later CEFR stages out
        # even after their source chapters are added to the shared book folder.
        if mod.CHAPTER["id"] == "s0" or mod.CHAPTER["id"].startswith("a1-"):
            chapters.append(mod.CHAPTER)
    return chapters


def main():
    chapters = load_chapters()
    html, words, exercises = render_book(FRONT, chapters)
    html_path = OUT / "ParleSprint_A1_Book.html"
    pdf_path = OUT / "ParleSprint_A1_Book.pdf"
    html_path.write_text(html, encoding="utf-8")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    "--virtual-time-budget=15000", f"--print-to-pdf={pdf_path}", f"file://{html_path}"],
                   check=True, capture_output=True, timeout=300)
    print(f"{len(chapters)} chapters, {words} distinct words, {exercises} exercise groups")
    print(f"wrote {pdf_path} ({pdf_path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
