/**
 * Telling the person from the voice's own words coming back through the microphone, ported from the
 * Mac's `Echo.swift`. It compares spellings and order only; it never decides what anybody meant.
 */

const LETTER = /\p{L}/u;

/** The words in a line, lowercased, for comparing what was heard with what was said. */
function wordsIn(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^\p{L}]+/u)
    .filter((word) => [...word].length > 1);
}

function length(word: string): number {
  return [...word].length;
}

/** Shorter words match only exactly, since "so" is a letter from "to" and "them" holds "the". */
const FUZZY_ECHO_LENGTH = 4;
/** A spelling one edit in this many letters away is still its own word misheard. */
const MISSPELLING_SHARE = 3;

/** Letters at the start of a word that are not said. */
const SOUNDS_ALIKE: readonly [string, string][] = [
  ['wr', 'r'],
  ['kn', 'n'],
  ['wh', 'w'],
  ['ps', 's'],
];
/** Spellings anywhere in a word that say the same sound. */
const SPELLED_ALIKE: readonly [string, string][] = [
  ['gh', ''],
  ['ph', 'f'],
  ['ck', 'k'],
  ['ei', 'e'],
  ['ea', 'e'],
];

/** How a word sounds rather than how it is spelled, so homophones the recognizer swaps share a key. */
function soundKey(word: string): string {
  let text = word;
  for (const [from, to] of SOUNDS_ALIKE) {
    if (text.startsWith(from)) {
      text = to + text.slice(from.length);
      break;
    }
  }
  for (const [from, to] of SPELLED_ALIKE) text = text.split(from).join(to);
  if (length(text) > 2 && text.endsWith('e')) text = text.slice(0, -1);
  let key = '';
  for (const letter of text) {
    const sound = 'aeiouy'.includes(letter) ? 'a' : letter;
    if (!key.endsWith(sound)) key += sound;
  }
  return key;
}

function editDistance(a: string, b: string): number {
  const left = [...a];
  const right = [...b];
  if (left.length === 0) return right.length;
  let row = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let i = 1; i <= left.length; i += 1) {
    const next = [i];
    for (let j = 1; j <= right.length; j += 1) {
      next[j] = Math.min((row[j] ?? 0) + 1, (next[j - 1] ?? 0) + 1, (row[j - 1] ?? 0) + (left[i - 1] === right[j - 1] ? 0 : 1));
    }
    row = next;
  }
  return row[right.length] ?? 0;
}

/**
 * Whether a heard word is the voice's own, misheard: the same word, one inside the other, or a spelling
 * a third away. A short word counts only when it is the very word, since fuzzy matching on those took
 * the person's own words for its echo and talked on over them.
 */
function isEcho(word: string, said: readonly string[]): boolean {
  return said.some((spoken) => {
    if (spoken === word) return true;
    // Its "asks" comes back as "ask", and a plural ending is never how "the" turns into "them".
    if (spoken === `${word}s` || word === `${spoken}s`) return true;
    if (length(word) < FUZZY_ECHO_LENGTH || length(spoken) < FUZZY_ECHO_LENGTH) return false;
    if (spoken.includes(word) || word.includes(spoken)) return true;
    // Its "write" comes back as "right" and "there" as "their": spelled apart, said alike.
    if (soundKey(word) === soundKey(spoken)) return true;
    return editDistance(word, spoken) <= Math.floor(Math.min(length(word), length(spoken)) / MISSPELLING_SHARE);
  });
}

/** How many of the person's own words it takes to call what was heard them cutting in. */
const BARGE_IN = {
  /** Nothing is being said, so two words of theirs are enough. */
  inSilence: 2,
  /** The voice is talking, which is when its echo is loudest. */
  overSpeech: 3,
  /** The voice is talking and what was heard opens with its own words, the likeliest echo of all. */
  overEcho: 4,
  /** Most of the recent words have to be theirs, so a stray novel word inside an echo does not count. */
  novelShare: 0.6,
} as const;

/** The first words heard, which open with its own when the echo is carrying on. */
const ECHO_OPENING_WORDS = 2;
/** Words a person says to stop the voice mid sentence, and its own name, which mean "listen to me". */
const STOP_WORDS = new Set(['stop', 'wait', 'hold', 'quiet', 'enough', 'shut', 'pause', 'memnox', 'jarvis']);
/** The last few words heard, which is where a person cutting in shows up. */
const BARGE_WINDOW = 6;
/** How many words in a row not its own it takes to pause the voice. */
const FIRST_WORDS_OF_THEIRS = 2;

/**
 * Whether what the microphone heard while the voice was talking is the person rather than its echo:
 * enough words it did not just say, and most of what was heard. The bar is higher while it speaks.
 */
export function isBargeIn(heard: string, spoken: string, speaking = false): boolean {
  const said = wordsIn(spoken);
  const all = wordsIn(heard);
  // Only the newest words: the start of what was heard is mostly its own voice.
  const recent = all.slice(-BARGE_WINDOW);
  const novel = recent.filter((word) => !isEcho(word, said));
  const opensWithEcho = all.slice(0, ECHO_OPENING_WORDS).every((word) => isEcho(word, said));
  // "Stop" or "wait" is one word and has to cut in at once; its own voice never says them unprompted.
  if (novel.some((word) => STOP_WORDS.has(word))) return true;
  const needed = speaking ? (opensWithEcho ? BARGE_IN.overEcho : BARGE_IN.overSpeech) : BARGE_IN.inSilence;
  return novel.length >= needed && novel.length >= recent.length * BARGE_IN.novelShare;
}

/** Whether a word is the start of one it said, which the recognizer writes before it has the rest. */
function isEchoStarting(word: string, said: readonly string[]): boolean {
  return said.some((spoken) => length(spoken) > length(word) && spoken.startsWith(word));
}

/**
 * Whether the newest words heard over the voice are not ones it said, the first sign of the person
 * starting to talk. Two in a row, since one stray word is how its own voice comes back misheard.
 */
export function mayBeCuttingIn(heard: string, spoken: string): boolean {
  const said = wordsIn(spoken);
  const words = wordsIn(heard);
  const newest = words[words.length - 1];
  if (newest === undefined) return false;
  // Only when it did not just say it: its own name is in half its sentences.
  if (STOP_WORDS.has(newest) && !isEcho(newest, said)) return true;
  const recent = words.slice(-FIRST_WORDS_OF_THEIRS);
  return recent.length === FIRST_WORDS_OF_THEIRS && recent.every((word) => !isEcho(word, said) && !isEchoStarting(word, said));
}

/** What was heard from the words it paused on, since everything before them was its own voice. */
export function sincePause(heard: string, pausedOn: string): string {
  const before = pausedOn.split(/\s+/).filter((word) => word !== '').length;
  return heard
    .split(/\s+/)
    .filter((word) => word !== '')
    .slice(Math.max(before - FIRST_WORDS_OF_THEIRS, 0))
    .join(' ');
}

/** Whether the words heard since it went quiet are the person: two of theirs after the ones it paused on. */
export function isPersonAfterPause(sincePaused: string, spoken: string): boolean {
  const said = wordsIn(spoken);
  const heard = wordsIn(sincePaused).filter((word) => !isEcho(word, said));
  if (heard.some((word) => STOP_WORDS.has(word))) return true;
  return wordsIn(sincePaused).slice(FIRST_WORDS_OF_THEIRS).filter((word) => !isEcho(word, said)).length >= BARGE_IN.inSilence;
}

/**
 * What the person said over the voice, with its own words taken off the front. When they were already
 * talking while it was quiet, everything from their first word of their own is kept.
 */
export function cutInWords(heard: string, pausedOn: string, spoken: string, spokeInQuiet: boolean): string {
  if (!spokeInQuiet) return withoutEcho(sincePause(heard, pausedOn), spoken);
  const said = wordsIn(spoken);
  const parts = withoutEchoRuns(heard, spoken).split(' ');
  const first = parts.findIndex((part) => wordsIn(part).some((word) => !isEcho(word, said)));
  if (first === -1) return '';
  // "I" in "I think" is too short to judge, so it stays with the word of theirs it opens.
  let start = first;
  while (start > 0 && wordsIn(parts[start - 1] ?? '').length === 0) start -= 1;
  return parts.slice(start).join(' ');
}

/** What the person said once the voice's own words are taken off the front. */
export function withoutEcho(heard: string, spoken: string): string {
  const said = wordsIn(spoken);
  const parts = heard.split(' ').filter((part) => part !== '');
  while (parts.length > 0) {
    const word = wordsIn(parts[0] ?? '')[0];
    if (word === undefined || !isEcho(word, said)) break;
    parts.shift();
  }
  return parts.join(' ');
}

/** A few words at most beside an echo; more is the person carrying on. */
const ECHO_LEFTOVER_WORDS = 3;
/** Shorter than this a leftover matches anywhere in a sentence by chance. */
const ECHO_LEFTOVER_LETTERS = 3;
/** A run this long of its own words is echo; one alone could as well be theirs. */
const ECHO_RUN_LENGTH = 2;
/** How many of its own words an echo may drop between two it kept, since the recognizer misses some. */
const ECHO_GAP = 1;

function letters(text: string): string {
  return [...text.toLowerCase()].filter((character) => LETTER.test(character)).join('');
}

/** Heard words put back together where the recognizer split one it said, "hire me" for its "HireMe". */
function rejoined(parts: readonly string[], said: readonly string[]): string[] {
  const pieces: string[] = [];
  for (const part of parts) {
    const last = pieces[pieces.length - 1];
    if (last !== undefined && !said.includes(letters(last)) && said.includes(letters(last + part)) && length(letters(last + part)) >= FUZZY_ECHO_LENGTH) {
      pieces[pieces.length - 1] = `${last} ${part}`;
    } else {
      pieces.push(part);
    }
  }
  return pieces;
}

/** The words in a piece: a rejoined one is the single word it was split from. */
function pieceWords(piece: string): string[] {
  return piece.includes(' ') ? [letters(piece)] : wordsIn(piece);
}

/** Whether the words follow one another in what it said, since its echo comes back in its own order. */
function followsInOrder(words: readonly string[], said: readonly string[]): boolean {
  const from = (index: number, rest: readonly string[]): boolean => {
    const word = rest[0];
    if (word === undefined) return true;
    if (index >= said.length) return false;
    for (let at = index; at <= Math.min(index + ECHO_GAP, said.length - 1); at += 1) {
      if (isEcho(word, [said[at] ?? '']) && from(at + 1, rest.slice(1))) return true;
    }
    return false;
  };
  const first = words[0];
  if (first === undefined) return false;
  return said.some((spoken, index) => isEcho(first, [spoken]) && from(index + 1, words.slice(1)));
}

/**
 * What was heard with its own recent words taken off either end, which is where they land when a
 * sentence it was still saying runs into the microphone. A run of two or more is echo; one word alone
 * at an end could as well be theirs, so it stays.
 */
export function withoutEchoRuns(heard: string, spoken: string): string {
  const said = wordsIn(spoken);
  let parts = rejoined(heard.split(' ').filter((part) => part !== ''), said);
  const echoes = (part: string) => pieceWords(part).every((word) => isEcho(word, said));
  const judged = (run: readonly string[]) => run.filter((part) => pieceWords(part).length > 0).length;
  const isRun = (run: readonly string[]) => judged(run) >= ECHO_RUN_LENGTH && followsInOrder(run.flatMap(pieceWords), said);
  const leadingEnd = parts.findIndex((part) => !echoes(part));
  const leading = parts.slice(0, leadingEnd === -1 ? parts.length : leadingEnd);
  const removedLeading = isRun(leading);
  if (removedLeading) parts = parts.slice(leading.length);
  const reversedEnd = [...parts].reverse().findIndex((part) => !echoes(part));
  const trailing = parts.slice(reversedEnd === -1 ? 0 : parts.length - reversedEnd);
  const removedTrailing = isRun(trailing);
  if (removedTrailing) parts = parts.slice(0, parts.length - trailing.length);
  // What is left beside an echo, split where its sentence was not, is the end of the same echo.
  const left = letters(parts.join(''));
  if ((removedLeading || removedTrailing) && judged(parts) <= ECHO_LEFTOVER_WORDS && length(left) >= ECHO_LEFTOVER_LETTERS && letters(spoken).includes(left)) {
    return '';
  }
  return parts.join(' ');
}
