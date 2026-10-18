import assert from "node:assert/strict";
import test from "node:test";
import { dialogues, dictations, freeToolEntries, levels, normalizeAnswer, sentenceBuilders, tools } from "./practice";

test("the free directory contains exactly ten distinct entries", () => {
  assert.equal(freeToolEntries.length, 10);
  assert.equal(new Set(freeToolEntries.map((entry) => entry.href)).size, 10);
  assert.equal(tools.length, 7);
});

test("every level has three authored dictations and sentence builders", () => {
  for (const level of levels) {
    assert.equal(dictations[level].length, 3, `${level} dictations`);
    assert.equal(sentenceBuilders[level].length, 3, `${level} sentence builders`);
    for (const item of sentenceBuilders[level]) {
      const answerWords = normalizeAnswer(item.answer).split(" ").sort();
      const bankWords = item.words.map(normalizeAnswer).sort();
      assert.deepEqual(bankWords, answerWords, `${level}: ${item.answer}`);
    }
  }
});

test("each level's conversation gives three authored turns with one best-fit reply", () => {
  for (const level of levels) {
    assert.ok(dialogues[level].length > 0, `${level} has a conversation`);
    for (const scenario of dialogues[level]) {
      assert.equal(scenario.turns.length, 3, `${level}: ${scenario.title}`);
      for (const turn of scenario.turns) {
        assert.equal(turn.choices.length, 3, `${level}: ${turn.prompt}`);
        assert.equal(turn.choices.filter((choice) => choice.bestFit).length, 1, `${level}: ${turn.prompt}`);
      }
    }
  }
});
