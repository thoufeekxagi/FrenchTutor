# V3 story format (Reading, and later Listening and Speaking)

A story is one JSON file. Nothing is generated at runtime.

- Story files: `flutter_app/assets/content/tcf/stories/<id>.json`
- Order and list: `flutter_app/assets/content/tcf/stories.json`
- Generator record for the first four A1 stories:
  `content/tcf/tools/gen_a1_stories.py`
- Check with `python3 content/tcf/tools/validate.py`.

## Fields

| field | rule |
|---|---|
| `id`, `title`, `titleEn`, `summary` | all required |
| `level` | `A1`, `A2`, `B1` or `B2`. The hub's level chips filter on this |
| `minutes` | whole number shown on the card |
| `unit` | the course unit the story belongs to, for example `a1-u01` |
| `sentences` | list of `{fr, en, note?}`. A1: 6 to 12 sentences, 12 words or fewer each. `note` is a short English teaching note (Canada vs France, a grammar habit) |
| `words` | map from word to `{en, pos?, sound?}`. **Every word of every sentence must be in here**, so a tapped word is never blank |
| `keywords` | 4 to 8 keys of `words` shown in the Words tab, in order |
| `quiz` | at least 3 questions `{prompt, options (4), answer, explain}` in the TCF reading style |

## Word keys

The reader splits a sentence on spaces, trims punctuation (« » " ' . , ! ? ; :)
from the ends, and lowercases. So `m'appelle`, `l'immeuble` and `rendez-vous`
are single words, and `« Bonsoir !` gives `bonsoir`. `validate.py` uses the same
rule and fails if any word has no meaning.

## Writing rules

- Present tense and short sentences at A1. Canadian settings (neighbour, corner
  store, first job, clinic) so the story also teaches the situation.
- Every sentence has an English line. Add a `note` only when it teaches
  something real.
- Quiz answers must be provable from the story text alone. Distractors must be
  clearly wrong, never a matter of opinion.
- Original text only.
- Narration is live Marie, like the legacy reader (see
  `docs/v3/design/story_reader_redesign.png`).

## The reader (what the learner sees)

Built in `lib/v3/story/`. Design reference: `docs/v3/design/story_reader_redesign.png`.

- Full screen, no image. Title, English title, level, minutes, then tabs
  Story, Quiz, Words.
- Every sentence shows French, then English (toggle in the top bar). The line
  being read is tinted, and the spoken word is highlighted.
- **Tap a word** to get a small card just above it with the word, its meaning,
  part of speech and a sound guide, plus a speaker. It is a small card, never a
  sheet. Tap the word again or anywhere else to close it.
- **Hear words when tapped** (Settings, on by default): Marie says the word you
  tap. Turn it off and taps stay silent, though the card's own speaker still
  works.
- Tapping a word or a line selects that sentence, and Play starts from it. Tap
  it again to clear.
- Dock: replay the sentence, play or pause, stop, speed (1, 1.5, 0.5, 0.75).
- Settings sheet: translation, hear words, highlight the spoken word, text
  size, reading speed.
- Quiz is one question at a time with Check and a green or red answer card.
  Finishing the quiz records the story as read.
- Words tab lists the keywords with a speaker and a save star. Saved words are
  stored on the device. They are not yet wired into Review.
- Narration is live Marie (Gemini Live), connected on the first play or word
  tap, never cached. `V3StoryAudio` has a free fake used only by tests.
