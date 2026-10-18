export interface ExplanationRequest { text: string; sentence: string; level: 'A1' | 'A2' | 'B1' | 'B2'; mode: 'explanation' | 'translation' }
export interface Explanation { meaning: string; grammar: string; example: string; exampleTranslation: string }
export interface Translation { translation: string }
export function parseInput(value: unknown): ExplanationRequest {
  if (!value || typeof value !== 'object') throw new Error('invalid_input');
  const v = value as Record<string, unknown>;
  if (v.mode !== undefined && v.mode !== 'explanation' && v.mode !== 'translation') throw new Error('invalid_input');
  const translation = v.mode === 'translation';
  if (typeof v.text !== 'string' || !v.text.trim() || v.text.length > (translation ? 1600 : 240) ||
      typeof v.sentence !== 'string' || v.sentence.length > 1600 ||
      !['A1', 'A2', 'B1', 'B2'].includes(String(v.level))) throw new Error('invalid_input');
  return {
    text: v.text.trim(),
    sentence: v.sentence.trim(),
    level: v.level as ExplanationRequest['level'],
    mode: translation ? 'translation' : 'explanation',
  };
}
export function parseExplanation(value: unknown): Explanation {
  if (!value || typeof value !== 'object') throw new Error('invalid_response');
  const v = value as Record<string, unknown>;
  for (const key of ['meaning', 'grammar', 'example', 'exampleTranslation']) {
    if (typeof v[key] !== 'string' || !v[key].trim() || v[key].length > 2000) throw new Error('invalid_response');
  }
  return { meaning: String(v.meaning), grammar: String(v.grammar), example: String(v.example), exampleTranslation: String(v.exampleTranslation) };
}
export function parseTranslation(value: unknown): Translation {
  if (!value || typeof value !== 'object') throw new Error('invalid_response');
  const translation = (value as Record<string, unknown>).translation;
  if (typeof translation !== 'string' || !translation.trim() || translation.length > 4000)
    throw new Error('invalid_response');
  return { translation: translation.trim() };
}
