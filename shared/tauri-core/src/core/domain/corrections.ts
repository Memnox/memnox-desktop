/** A word Memnox typed from what it heard, and what the person changed it to. */
export interface WordCorrection {
  readonly heard: string;
  readonly meant: string;
}

/** The limits a correction is held to, as the Mac's `Corrections`. */
const CORRECTIONS = {
  /** More than half the words changed is a rewrite. */
  mostChanged: 0.5,
  /** A misheard name is a word or a few, never a clause. */
  mostWords: 3,
  /** Shorter than this is a sound, not a word worth learning. */
  leastLetters: 3,
  /** Spellings further apart than this share of their letters do not sound alike. */
  mostDifferent: 0.7,
  /** One edit fixes a few words at most; past this it is a rewrite. */
  mostAtOnce: 5,
} as const;

interface Word {
  readonly written: string;
  readonly key: string;
}

/**
 * The words the person fixed in text Memnox typed for them, ported from `Corrections.swift`: the two are
 * lined up word by word, so "show the surgeons" sent as "show the sessions" is surgeons for sessions. A
 * rewrite, a word added or dropped, a fix of case or punctuation, or a swap for a word that sounds nothing
 * alike teaches nothing, since none of them is the recognizer mishearing a word.
 */
export function correctedWords(typed: string, sent: string): WordCorrection[] {
  const before = wordsIn(typed);
  const after = wordsIn(sent);
  if (before.length === 0 || after.length === 0) return [];
  const kept = commonRun(
    before.map((word) => word.key),
    after.map((word) => word.key),
  );
  if ((before.length - kept.length) / before.length > CORRECTIONS.mostChanged) return [];
  const found: WordCorrection[] = [];
  let b = 0;
  let a = 0;
  for (const [keptBefore, keptAfter] of [...kept, [before.length, after.length] as const]) {
    const one = correction(before.slice(b, keptBefore), after.slice(a, keptAfter));
    if (one !== undefined) found.push(one);
    b = keptBefore + 1;
    a = keptAfter + 1;
  }
  return found.slice(0, CORRECTIONS.mostAtOnce);
}

function wordsIn(text: string): Word[] {
  return text
    .split(/\s+/)
    .map((token) => token.replace(/^[\p{P}]+|[\p{P}]+$/gu, ''))
    .map((written) => ({ written, key: written.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '') }))
    .filter((word) => word.key !== '');
}

/** The words kept in order in both, as index pairs, by the longest common run of words. */
function commonRun(a: readonly string[], b: readonly string[]): (readonly [number, number])[] {
  const table = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i -= 1) {
    for (let j = b.length - 1; j >= 0; j -= 1) {
      table[i]![j] = a[i] === b[j] ? table[i + 1]![j + 1]! + 1 : Math.max(table[i + 1]![j]!, table[i]![j + 1]!);
    }
  }
  const pairs: (readonly [number, number])[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      pairs.push([i, j]);
      i += 1;
      j += 1;
    } else if (table[i + 1]![j]! >= table[i]![j + 1]!) i += 1;
    else j += 1;
  }
  return pairs;
}

/** A changed stretch as a correction, when it is a word or a few swapped for ones that sound alike. */
function correction(heard: readonly Word[], meant: readonly Word[]): WordCorrection | undefined {
  if (heard.length === 0 || meant.length === 0 || heard.length > CORRECTIONS.mostWords || meant.length > CORRECTIONS.mostWords) return undefined;
  const heardKey = heard.map((word) => word.key).join('');
  const meantKey = meant.map((word) => word.key).join('');
  if (heardKey.length < CORRECTIONS.leastLetters || meantKey.length < CORRECTIONS.leastLetters || heardKey === meantKey) return undefined;
  const apart = letterDistance(heardKey, meantKey) / Math.max(heardKey.length, meantKey.length);
  if (apart > CORRECTIONS.mostDifferent) return undefined;
  return { heard: heard.map((word) => word.written).join(' '), meant: meant.map((word) => word.written).join(' ') };
}

function letterDistance(a: string, b: string): number {
  const left = [...a];
  const right = [...b];
  let row = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let i = 1; i <= left.length; i += 1) {
    const next = [i];
    for (let j = 1; j <= right.length; j += 1) {
      next[j] = Math.min(row[j]! + 1, next[j - 1]! + 1, row[j - 1]! + (left[i - 1] === right[j - 1] ? 0 : 1));
    }
    row = next;
  }
  return row[right.length]!;
}
