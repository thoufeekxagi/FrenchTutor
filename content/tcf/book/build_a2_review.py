#!/usr/bin/env python3
"""Build the complete A2 reviewer copy from all twelve canonical chapters.

The app export remains a separate, scoped operation:
  python3 content/tcf/book/export_app.py --a2-only
This builder only writes the review HTML/PDF under docs/v3/book/.
"""
import html as html_lib
import importlib.util
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / "docs" / "v3" / "book"
CHROME = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
sys.path.insert(0, str(HERE))
from book_lib import render_book  # noqa: E402


def load_a2_chapters():
    paths = sorted((HERE / "chapters").glob("[0-9][0-9]_a2_unit*.py"))
    chapters = []
    for path in paths:
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        chapters.append(module.CHAPTER)

    expected = [f"a2-u{i:02d}" for i in range(1, 13)]
    actual = [chapter["id"] for chapter in chapters]
    if actual != expected:
        raise SystemExit(f"Expected all twelve A2 chapters in order; found {actual}")
    return chapters


def course_map(syllabus, grammar):
    points = {item["id"]: item["title"] for item in grammar["points"]}
    rows = []
    for index, unit in enumerate(syllabus["units"], 1):
        grammar_text = "; ".join(points[code] for code in unit.get("grammar_new", []))
        if not grammar_text:
            grammar_text = "Cumulative retrieval and transfer"
        rows.append(
            "<tr>"
            f"<td><b>{index:02d}</b><br>{unit['new_words_target']} new items</td>"
            f"<td><b>{html_lib.escape(unit['title'])}</b><br>"
            f"{html_lib.escape(unit['can_do'])}</td>"
            f"<td>{html_lib.escape(grammar_text)}</td>"
            "</tr>"
        )
    return "".join(rows)


def front_matter(syllabus, grammar):
    today = date.today().strftime("%-d %B %Y")
    hours = syllabus["planned_focused_hours_per_unit"]
    count = len(syllabus["units"])
    total_min = hours["min"] * count
    total_max = hours["max"] * count
    return f"""
<div class="coverbg reviewcover"><div class="cover reviewcover-main">
  <div class="eyebrow" style="color:rgba(255,255,255,.8)">PARLESPRINT · TCF CANADA</div>
  <div class="big">French A2.<br>Build independence.</div>
  <div class="small">Twelve original units for understanding, speaking, reading and writing about familiar life in Canada.</div>
</div></div>

<div class="cover-meta">
  <div class="eyebrow">COMPLETE COURSE · REVIEWER DRAFT · {html_lib.escape(today.upper())}</div>
  <p><b>All 12 planned A2 units are included.</b> This copy contains the lesson source, original dialogues and stories, listening and reading tasks, writing and speaking models, answer key, audio scripts and vocabulary index. It is generated from the same authored chapters exported to the app.</p>
  <p>Prepared for review by a fluent French speaker and a TCF Canada specialist. Human language, regional-use and audio review is still pending.</p>
  <div class="note watch"><b>Scope</b> This is an A2 learning stage. It is not an official TCF paper, proof of an attained CEFR level, a CLB/NCLC 7 result, or a guarantee of a test outcome.</div>
</div>

<div class="opener review-brief" style="padding-top:16mm">
  <div class="eyebrow">REVIEW BRIEF</div>
  <div class="ttl">What to assess</div>
  <p>The learner is an adult beginner in Canada. A typical study setup is ParleSprint on the left side of an iPad and personal notes on the right. The course uses explicit, concise English grammar support, then asks the learner to listen, read, speak or write in French, record a useful pattern and one error, close the notes, retrieve the language, and use it in a changed situation.</p>
  <p>Each unit has original vocabulary and phrases, grammar, two practical dialogues, a connected story, listening and reading questions, a writing task, speaking practice, a TCF-style corner and a cumulative checkpoint. Most units add 48 new vocabulary entries; Units 1 and 12 add 45 each, for <b>{syllabus['new_word_target']} planned new entries</b> across A2.</p>

  <h3>Review the language and teaching</h3>
  <ul>
    <li>Check French grammar, idiom, agreement, register and the English meaning of every vocabulary example, dialogue, story and model.</li>
    <li>Check that A2 language remains understandable for a learner moving up from A1, and that no explanation hides a required step.</li>
    <li>Check the order and completeness of the grammar sequence, especially the transition from completed past actions to background and event narration.</li>
    <li>Check Canadian context and label regional expressions clearly. In particular, review rental, transit, health-service, delivery and grocery wording for Ontario/Canadian use.</li>
    <li>Check every answer key against the supporting text or recording script; note ambiguous distractors and items with more than one plausible answer.</li>
    <li>Review the sound guides as rough English-language aids. They are not IPA and need a French speaker's correction; listen to the app voice separately.</li>
    <li>Judge whether each writing/speaking prompt is achievable at this point in the course and whether the model is a useful example rather than a script to memorize.</li>
  </ul>
  <p>For comments, identify the unit, section and item ID; quote the words at issue; suggest a correction; and say whether it is a French-language, level, fact, answer-key or teaching issue.</p>

  <h3>Course time is a workload estimate</h3>
  <p>The plan allocates <b>{hours['min']}–{hours['max']} focused hours per unit</b>, or <b>{total_min}–{total_max} hours for A2</b>. That is an estimate for study, delayed review and independent transfer, not a calendar rule or a research-validated guarantee. At two hours a day, it is roughly 12–14 weeks if studied every day, or 17–20 weeks at five days a week. At four hours a day, it is about 8–10 weeks at five days a week. The learner should move forward based on delayed recall and unfamiliar-context performance, not screen completion alone.</p>
  <p>The review cycle starts with suggested retrieval gaps of 1, 3, 7, 14 and 30 days, moving an item sooner when recall fails. The design combines adult-friendly explicit explanation with contextual French and repeated retrieval; it does not claim to reproduce how infants acquire language or that AI makes learning faster. Second-language meta-analyses support spaced practice on average and report positive average outcomes for generative AI chatbots, with variation across studies. Neither finding proves that this specific course accelerates French learning.</p>
  <p>Research references: Kim and Webb (2022), <i>Language Learning</i>, DOI 10.1111/lang.12479; Li, Wang and Yang (2025), <i>Journal of Computer Assisted Learning</i>, DOI 10.1111/jcal.70060. CEFR reference: <a href="https://www.coe.int/en/web/common-european-framework-reference-languages/cefr-companion-volume-and-its-language-versions">Council of Europe, CEFR Companion Volume</a>.</p>
</div>

<div class="opener review-tcf" style="padding-top:20mm">
  <div class="eyebrow">EXAM REFERENCE</div>
  <div class="ttl">What the official TCF Canada contains</div>
  <p>The TCF Canada has four required components. The figures below follow the official France Éducation international overview and candidate information; recheck the current source before release.</p>
  <table class="tbl">
    <tr><th>Component</th><th>Official format</th><th>Time</th></tr>
    <tr><td>Listening</td><td>39 multiple-choice questions; each recording is heard once</td><td>35 minutes</td></tr>
    <tr><td>Reading</td><td>39 multiple-choice questions</td><td>60 minutes</td></tr>
    <tr><td>Writing</td><td>3 tasks. Task 1: 60–120 words; Task 2: 120–150; Task 3: 120–180</td><td>60 minutes</td></tr>
    <tr><td>Speaking</td><td>3 tasks with an examiner</td><td>12 minutes</td></tr>
  </table>
  <p>A2 practice in this manuscript is original and progressively scaffolded. It practices short listening and reading items and the full Task 1 writing range; later writing and speaking task shapes appear as supported previews where stated. This is not a complete official-length test pack and does not claim that completing A2 is enough for a TCF or CLB/NCLC 7 result.</p>
  <p>Official sources: <a href="https://www.france-education-international.fr/test/tcf-canada">France Éducation international: TCF Canada</a> and <a href="https://www.france-education-international.fr/test/exemples-epreuves-tcf">official sample tasks</a>.</p>
  <div class="note canada"><b>In Canada</b> The course uses fictional service, rental, transit and shopping examples. They teach language for asking, comparing and explaining; they do not give medical, tenancy, legal, billing or current-service advice.</div>
</div>

<div class="reviewmap" style="break-before:page; padding-top:5mm">
  <div class="eyebrow">A2 COURSE MAP</div>
  <div class="ttl">Twelve units, a deliberate progression</div>
  <p>New grammar appears in context, then returns in later units and in the capstone. The word target is a planning target, not an official CEFR vocabulary count.</p>
  <table class="tbl unitmap">
    <tr><th>Unit and new words</th><th>Can-do goal</th><th>New grammar</th></tr>
    {course_map(syllabus, grammar)}
  </table>
  <h3>Contents</h3>
  {{{{TOC}}}}
</div>
"""


def count_new_words(chapters):
    return sum(
        len(block[1])
        for chapter in chapters
        for block in chapter["blocks"]
        if block[0] == "words" and block[2].startswith("Group ")
    )


def main():
    syllabus = json.loads((ROOT / "content/tcf/syllabus/a2.json").read_text(encoding="utf-8"))
    grammar = json.loads((ROOT / "content/tcf/syllabus/grammar_a2.json").read_text(encoding="utf-8"))
    chapters = load_a2_chapters()
    new_words = count_new_words(chapters)
    if new_words != syllabus["new_word_target"]:
        raise SystemExit(f"Expected {syllabus['new_word_target']} A2 new entries, found {new_words}")

    OUT.mkdir(parents=True, exist_ok=True)
    html_text, index_entries, exercise_groups = render_book(
        front_matter(syllabus, grammar), chapters, back_title="A2 vocabulary and phrase index"
    )
    html_text = html_text.replace(
        "<!doctype html><meta charset='utf-8'>",
        "<!doctype html><head><meta charset='utf-8'>"
        "<title>ParleSprint A2 Complete Course - Reviewer Draft</title></head>",
    )
    html_text = html_text.replace(
        "</style>",
        ".cover { break-after: auto !important; }"
        ".coverbg.reviewcover { height: 200mm !important; min-height: 200mm !important; padding: 16mm !important; break-after: auto !important; }"
        ".cover.reviewcover-main { height: 168mm !important; min-height: 168mm !important; break-after: auto !important; }"
        ".cover-meta { min-height: 97mm; padding: 15mm 16mm; border-top: 1px solid #E1E4EA; break-after: page; }"
        ".review-brief, .review-tcf { padding-top: 18mm !important; }"
        ".reviewmap { break-before: page; padding: 5mm 0 0; }"
        "table.unitmap { font-size: 8.3pt; line-height: 1.35; }"
        "table.unitmap td:first-child { white-space: nowrap; width: 26mm; }"
        "table.unitmap td:last-child { width: 51mm; }"
        "table.unitmap td { padding: 4pt 5pt; }"
        "@page { @bottom-center { content: 'ParleSprint A2 reviewer draft  ·  ' counter(page); font-size: 8pt; color: #697386; } }"
        "@page:first { @bottom-center { content: none; } }"
        "</style>",
    )
    # Avoid Unicode dash glyph substitutions in the PDF while keeping the
    # source files' French punctuation untouched.
    for dash in ("\u2010", "\u2011", "\u2012", "\u2013", "\u2014", "\u2212"):
        html_text = html_text.replace(dash, "-")

    html_path = OUT / "ParleSprint_A2_Reviewer_Draft.html"
    pdf_path = OUT / "ParleSprint_A2_Reviewer_Draft.pdf"
    html_path.write_text(html_text, encoding="utf-8")
    subprocess.run(
        [
            str(CHROME),
            "--headless=new",
            "--disable-gpu",
            "--no-pdf-header-footer",
            "--virtual-time-budget=20000",
            f"--print-to-pdf={pdf_path}",
            f"file://{html_path}",
        ],
        check=True,
        capture_output=True,
        timeout=300,
    )
    if not pdf_path.is_file() or pdf_path.stat().st_size < 50_000:
        raise SystemExit(f"PDF output is missing or unexpectedly small: {pdf_path}")
    print(
        f"A2 reviewer copy: {len(chapters)} units, {new_words} new vocabulary entries, "
        f"{index_entries} vocabulary/phrase index entries, {exercise_groups} answer-key groups"
    )
    print(f"wrote {pdf_path} ({pdf_path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
