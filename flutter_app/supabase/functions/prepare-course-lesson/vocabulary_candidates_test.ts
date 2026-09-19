import { selectVocabularyCandidates } from "./vocabulary_candidates.ts";

function candidates(reviewCount: number, newCount: number) {
  return [
    ...Array.from({ length: reviewCount }, (_, index) => ({
      id: `r${index}`,
      fr: `review-${index}`,
      en: `review gloss ${index}`,
      phonetic: `r${index}`,
      role: "review" as const,
    })),
    ...Array.from({ length: newCount }, (_, index) => ({
      id: `n${index}`,
      fr: `new-${index}`,
      en: `new gloss ${index}`,
      phonetic: `n${index}`,
      role: "new" as const,
    })),
  ];
}

Deno.test("selects an exact two-review/three-new vocabulary set", () => {
  const selected = selectVocabularyCandidates(candidates(12, 12));
  if (selected.length !== 5) throw new Error("expected five candidates");
  if (selected.filter((candidate) => candidate.role === "review").length !== 2) {
    throw new Error("expected two review candidates");
  }
  if (selected.filter((candidate) => candidate.role === "new").length !== 3) {
    throw new Error("expected three new candidates");
  }
});

Deno.test("fills the five-word set when one candidate pool is short", () => {
  const selected = selectVocabularyCandidates(candidates(4, 1));
  if (selected.length !== 5) throw new Error("expected five candidates");
  if (selected.filter((candidate) => candidate.role === "review").length !== 4) {
    throw new Error("expected all four review candidates");
  }
  if (selected.filter((candidate) => candidate.role === "new").length !== 1) {
    throw new Error("expected the available new candidate");
  }
});

Deno.test("falls back instead of creating an impossible five-word schema", () => {
  const selected = selectVocabularyCandidates(candidates(1, 3));
  if (selected.length !== 0) throw new Error("expected empty fallback signal");
});

Deno.test("deduplicates stable ids before selecting the five words", () => {
  const pool = candidates(3, 3);
  pool.push({ ...pool[0], role: "new" });
  const selected = selectVocabularyCandidates(pool);
  if (selected.length !== 5) throw new Error("expected five candidates");
  if (new Set(selected.map((candidate) => candidate.id)).size !== 5) {
    throw new Error("candidate ids must be unique");
  }
});
