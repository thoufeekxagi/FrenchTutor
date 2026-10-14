"""Shared structure for hand-authored A2 units.

Each numbered chapter file supplies its own scenes, vocabulary, examples,
grammar, question banks, models and story glossary. This helper only assembles
those authored pieces into the common book/app structure.
"""
from book_lib import (
    H, H3, LIST, MCQ, P, TABLE, WORDS, DIALOGUE, STORY, WRITE, SPEAK, chapter,
)


def noun_group(title, entries, fr_pattern="Je vérifie {fr} avant le cours.",
               en_pattern="I check {en} before class."):
    """Make contextual examples for an authored group of nouns.

    Entries are (French headword, sound guide, English meaning). Choose a
    pattern that genuinely fits the whole group; override both templates when
    another scene fits better.
    """
    rows = []
    for entry in entries:
        if len(entry) == 5:
            # Allow an author-written example when one shared pattern would
            # sound forced or misleading for a word in the group.
            rows.append(tuple(entry))
            continue
        fr, sound, en = entry
        rows.append((fr, sound, en, fr_pattern.format(fr=fr), en_pattern.format(en=en)))
    return title, rows


def verb_group(title, entries, fr_pattern="Avant le cours, je peux {fr} sans aide.",
               en_pattern="Before class, I can {en} without help."):
    """Make short examples for infinitive verb entries."""
    rows = []
    for fr, sound, en in entries:
        en = en.removeprefix("to ")
        rows.append((fr, sound, "to " + en, fr_pattern.format(fr=fr), en_pattern.format(en=en)))
    return title, rows


def adj_group(title, entries, fr_pattern="La situation est {fr}.",
              en_pattern="The situation is {en}."):
    """Make examples for adjective forms that agree with the template noun."""
    rows = [(fr, sound, en, fr_pattern.format(fr=fr), en_pattern.format(en=en))
            for fr, sound, en in entries]
    return title, rows


def build_unit(data):
    n = data["number"]
    p = f"{n}."
    blocks = [
        H(f"{p}1  Words: {data['word_heading']}"),
        P(data["word_intro"]),
    ]
    expected_words = data.get("word_count", 48)
    group_counts = [len(rows) for _, rows in data["word_groups"]]
    if len(group_counts) != 6 or any(count < 5 or count > 8 for count in group_counts):
        raise ValueError(f"A2 Unit {n}: expected six contextual word groups with five to eight entries each")
    if sum(group_counts) != expected_words:
        raise ValueError(f"A2 Unit {n}: expected {expected_words} new word entries, got {sum(group_counts)}")
    for index, (title, rows) in enumerate(data["word_groups"], 1):
        blocks.append(WORDS(rows, f"Group {index}: {title}"))

    blocks.extend([
        P(data["canada_note"]),
        H(f"{p}2  Phrases: {data['phrase_heading']}"),
        P(data["phrase_intro"]),
        WORDS(data["phrases"], "Useful connected phrases"),
        H(f"{p}3  Grammar: {data['grammar_heading']}"),
        P(data["grammar_intro"]),
    ])
    for index, point in enumerate(data["grammar"], 1):
        label = chr(ord("A") + index - 1)
        blocks.append(H3(f"{label}. {point['title']}"))
        for table in point.get("tables", []):
            blocks.append(TABLE(table["headers"], table["rows"], table.get("caption", "")))
        if point.get("rows"):
            blocks.append(TABLE(point["headers"], point["rows"], point["caption"]))
        if point.get("rules"):
            blocks.append(LIST(*point["rules"]))
        if point.get("questions"):
            blocks.append(MCQ(f"{n}.3{label}", point.get("quiz_title", "Use the pattern"), "reading",
                              point.get("quiz_intro", "Choose the form that matches the meaning."),
                              point["questions"]))

    blocks.extend([
        H(f"{p}4  Dialogues: {data['dialogue_heading']}"),
        P(data["dialogue_intro"]),
    ])
    for title, setting, lines in data["dialogues"]:
        blocks.append(DIALOGUE(title, setting, lines))
    blocks.append(MCQ(f"{n}.4", "Follow the exchange", "reading",
                      "Choose the detail each speaker gives.", data["dialogue_questions"]))

    blocks.extend([
        H(f"{p}5  Story: {data['story']['heading']}"),
        P(data["story"]["intro"]),
        STORY(data["story"]["title"], data["story"]["title_en"], data["story"]["sentences"]),
        MCQ(f"{n}.5", "Understand the story", "reading",
            "Read for the main event, then check each detail in the text.", data["story"]["questions"]),
        H(f"{p}6  Listening: {data['listening_heading']}"),
        P(data["listening_intro"]),
        MCQ(f"{n}.6", "Listen for meaning", "listening",
            "Each original recording is played once. Listen for the goal and one useful detail.", data["listening"]),
        H(f"{p}7  Reading: {data['reading_heading']}"),
        P(data["reading_intro"]),
        MCQ(f"{n}.7", "Read everyday texts", "reading",
            "Scan the format first, then locate the detail that answers the question.", data["reading"]),
        H(f"{p}8  Writing: {data['writing']['heading']}"),
        WRITE(f"{n}.8W", data["writing"]["title"], data["writing"]["prompt"],
              data["writing"]["model"], data["writing"]["checklist"]),
        H(f"{p}9  Speaking: {data['speaking']['heading']}"),
        SPEAK(f"{n}.9S", data["speaking"]["title"], data["speaking"]["prompt"],
              data["speaking"]["model"], data["speaking"]["tips"]),
        H(f"{p}10  TCF corner and checkpoint"),
        P(data["tcf_intro"]),
        MCQ(f"{n}.10L", "TCF listening practice", "listening",
            "Listen once; choose the answer supported by the recording.", data["tcf_listening"]),
        MCQ(f"{n}.10R", "TCF reading practice", "reading",
            "Read each short message or notice once for the requested information.", data["tcf_reading"]),
        MCQ(f"{n}.10C", "Checkpoint: 10 questions", "reading",
            "Aim for 8/10. For each missed item, name the clue and retry after a delay.", data["checkpoint"]),
        H(f"A2 Unit {n}: retrieve, then transfer"),
        LIST(
            "After one day, close your notes and retrieve five useful words and the grammar pattern.",
            "After three and seven days, use the same language in a changed scene; bring back items that still need effort.",
            "Record one self-correction and one original sentence in your notes, then say the sentence without reading.",
            "Move on when you can do the transfer task with the notes closed; lesson completion alone is not mastery.",
        ),
    ])
    ch = chapter(
        f"a2-u{n:02d}", f"A2 · Unit {n}", data["title"], blocks,
        can_do=data["can_do"], situation=data["situation"],
        canada=data.get("canada", [data["canada_note"]]),
        badge=f"A2.{n}",
    )
    ch["story_meta"] = data["story"]["meta"]
    ch["story_gloss"] = data["story"]["gloss"]
    return ch
