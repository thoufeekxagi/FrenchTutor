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
