export type VocabularyCandidate = {
  id: string;
  fr: string;
  en: string;
  phonetic: string;
  role: "review" | "new";
};

/**
 * Vocabulary artifacts contain exactly five entries. Sending the model a
 * 24-word pool and merely asking it to "aim" for a 2/3 review/new split made
 * the prompt weaker than validateVocabulary(): the model could choose five
 * valid words but miss one role, and the server would reject the whole lesson.
 * Preselect five candidates so the prompt and validator share one achievable
 * contract.
 */
export function selectVocabularyCandidates(
  candidates: VocabularyCandidate[],
): VocabularyCandidate[] {
  const uniqueById = new Map<string, VocabularyCandidate>();
  for (const candidate of candidates) {
    if (candidate.id && !uniqueById.has(candidate.id)) {
      uniqueById.set(candidate.id, candidate);
    }
  }
  const unique = [...uniqueById.values()];
  if (unique.length < 5) return [];

  const review = unique.filter((candidate) => candidate.role === "review");
  const fresh = unique.filter((candidate) => candidate.role === "new");
  const selected = [
    ...review.slice(0, 2),
    ...fresh.slice(0, 3),
  ];
  for (const candidate of [...review.slice(2), ...fresh.slice(3)]) {
    if (selected.length >= 5) break;
    selected.push(candidate);
  }
  return selected.slice(0, 5);
}
