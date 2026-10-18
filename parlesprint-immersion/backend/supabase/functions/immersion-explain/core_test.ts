import { parseInput, parseExplanation, parseTranslation } from './core.ts';
function assert(value: boolean) { if (!value) throw new Error('assertion failed'); }
Deno.test('input rejects malformed levels and oversized text', () => {
  for (const input of [null, {}, {text:'bonjour',sentence:'',level:'C2'}, {text:'a'.repeat(241),sentence:'',level:'A1'}]) {
    let failed = false;
    try { parseInput(input); } catch { failed = true; }
    assert(failed);
  }
  assert(parseInput({text:' bonjour ',sentence:'Bonjour Marie',level:'A1'}).text === 'bonjour');
  assert(parseInput({text:'Bonjour',sentence:'Bonjour',level:'A1',mode:'translation'}).mode === 'translation');
  let invalidMode = false;
  try { parseInput({text:'bonjour',sentence:'bonjour',level:'A1',mode:'audio'}); } catch { invalidMode = true; }
  assert(invalidMode);
});
Deno.test('sentence translation accepts subtitle cues longer than word explanations', () => {
  const sentence = 'Je regarde cette vidéo. '.repeat(20).trim();
  assert(sentence.length > 240);
  assert(parseInput({text:sentence,sentence,level:'B1',mode:'translation'}).text === sentence);
  let explanationRejected = false;
  try { parseInput({text:sentence,sentence,level:'B1'}); } catch { explanationRejected = true; }
  assert(explanationRejected);
});
Deno.test('translation responses accept one bounded nonempty field', () => {
  assert(parseTranslation({translation:'Hello there.'}).translation === 'Hello there.');
  for (const value of [{translation:''}, {translation:12}, {translation:'a'.repeat(4001)}]) {
    let failed = false;
    try { parseTranslation(value); } catch { failed = true; }
    assert(failed);
  }
});
Deno.test('model response must contain bounded nonempty strings', () => {
  const good = {meaning:'hello',grammar:'greeting',example:'Bonjour Marie.',exampleTranslation:'Hello Marie.'};
  assert(parseExplanation(good).meaning === 'hello');
  for (const value of [{...good,meaning:''},{...good,grammar:12},{...good,example:'a'.repeat(2001)}]) {
    let failed = false;
    try { parseExplanation(value); } catch { failed = true; }
    assert(failed);
  }
});
