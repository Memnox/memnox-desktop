/** Short lines share their few words by chance, so only an exact one repeats. */
const LEAST_WORDS = 4;
/** Four in five words the same is the same sentence told again. */
const SAME_SHARE = 0.8;

/**
 * Whether a sentence says again what was already said in this reply, ported from `Repeats.swift`. The
 * brain often says what it is about to do, calls the tool, then says it once more; heard twice it sounds
 * broken, so the second is let go. Nearly the same words count too.
 */
export function repeats(sentence: string, saidAlready: readonly string[]): boolean {
  const words = new Set(wordsOf(sentence));
  if (words.size === 0) return false;
  return saidAlready.some((earlier) => {
    const before = new Set(wordsOf(earlier));
    const shared = [...words].filter((word) => before.has(word)).length;
    const union = new Set([...words, ...before]).size;
    if (shared === words.size && shared === before.size) return true;
    if (words.size < LEAST_WORDS || before.size < LEAST_WORDS) return false;
    return shared / union >= SAME_SHARE;
  });
}

function wordsOf(sentence: string): string[] {
  return sentence
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((word) => word !== '');
}
