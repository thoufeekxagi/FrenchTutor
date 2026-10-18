export interface Meaning {
  text: string;
  translation: string;
  alternatives: { pos: string; terms: string[] }[];
}

/** Parse Google's keyless translate payload: segments plus optional dictionary entries. */
export function parseTranslation(text: string, data: unknown): Meaning | undefined {
  if (!Array.isArray(data) || !Array.isArray(data[0])) return;
  const translation = (data[0] as unknown[])
    .map((segment) => (Array.isArray(segment) && typeof segment[0] === "string" ? segment[0] : ""))
    .join("")
    .trim();
  if (!translation) return;
  const dictionary = Array.isArray(data[1]) ? (data[1] as unknown[]) : [];
  const alternatives = dictionary
    .flatMap((entry) =>
      Array.isArray(entry) && typeof entry[0] === "string" && Array.isArray(entry[1])
        ? [{ pos: entry[0], terms: (entry[1] as unknown[]).filter((t): t is string => typeof t === "string").slice(0, 4) }]
        : [],
    )
    .filter((entry) => entry.terms.length)
    .slice(0, 3);
  return { text, translation, alternatives };
}

const cache = new Map<string, Meaning>();

/** French to English, no account or API key. Used from the background worker. */
export async function translateFrench(text: string): Promise<Meaning | undefined> {
  const clean = text.trim().slice(0, 600);
  if (!clean) return;
  const hit = cache.get(clean);
  if (hit) return hit;
  const url = new URL("https://translate.googleapis.com/translate_a/single");
  url.searchParams.set("client", "gtx");
  url.searchParams.set("sl", "fr");
  url.searchParams.set("tl", "en");
  url.searchParams.append("dt", "t");
  url.searchParams.append("dt", "bd");
  url.searchParams.set("q", clean);
  const response = await fetch(url.href, { signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw Error(`translate ${response.status}`);
  const meaning = parseTranslation(clean, await response.json());
  if (meaning) {
    if (cache.size > 2000) cache.delete(cache.keys().next().value!);
    cache.set(clean, meaning);
  }
  return meaning;
}
