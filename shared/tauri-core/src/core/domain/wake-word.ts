import { withoutEchoRuns } from './echo';

/**
 * Hearing its own name, ported from the Mac's `WakeWord.swift`. The name only opens the orb: what
 * follows goes whole to the brain, so nothing here acts on a word beyond knowing it was called.
 */

/** How the recognizer spells "Memnox" before it has learned the word, run together. */
const WAKE_SPELLINGS = new Set([
  'memnox', 'memnocks', 'memknox', 'memknocks', 'mennox', 'memnoks', 'memnux', 'menknocks', 'mennocks',
  'maamknox', 'mamknox', 'manknox', 'menknox', 'maamnox', 'mamnox', 'mamnocks', 'manknocks', 'memnoxs',
  // Heard on a real Mac: "Emma Knox", "MM Nox", "M Knox", "Minnox".
  'emmaknox', 'mmnox', 'mmknox', 'mknox', 'minnox', 'emnox', 'emknox',
  // Heard on a real Mac: "Memnox Manox", "Mnox".
  'manox', 'mannox', 'mnox', 'menox',
]);

/** The name cut to its end, which only counts at either end of what was said or beside the name itself. */
const EDGE_SPELLINGS = new Set(['knox', 'nox']);

/** The two halves of the name as somebody says it their own way; none is a common word of its own. */
const FIRST_HALVES = new Set(['mem', 'men', 'mam', 'mim', 'min', 'maam', 'emm', 'em', 'mm', 'emma', 'mehm', 'mehn', 'mimm']);
const SECOND_HALVES = new Set([
  'nox', 'nocks', 'nocs', 'noks', 'nux', 'nucks', 'nuks', 'nix', 'nicks', 'nics', 'nex', 'necks', 'nax', 'naks',
  'knox', 'knocks', 'knocs', 'knicks', 'knux', 'nock', 'noc',
]);

/** Four letters is the shortest run that can still be the name ("mnox"); anything shorter is a word of its own. */
const SHORTEST_NAME = 4;
/** The recognizer splits the name into at most three runs, as in "ma'am knox". */
const MOST_NAME_TOKENS = 3;
/** Only the first word, or the one after a word like "OK", is the start of what was said. */
const LEADING_EDGE_TOKENS = 2;
/** One word before the name, like "hey" or "OK", still makes it a greeting. */
const GREETING_WORDS_BEFORE_NAME = 2;
const NAME_SET_APART_BY = new Set(['.', '?', '!', ',']);

const LETTER = /\p{L}/u;
const LETTER_OR_NUMBER = /[\p{L}\p{N}]/u;

function isWakeSpelling(run: string): boolean {
  if (WAKE_SPELLINGS.has(run)) return true;
  const letters = [...run];
  if (letters.length < SHORTEST_NAME) return false;
  for (let cut = 1; cut < letters.length; cut += 1) {
    if (FIRST_HALVES.has(letters.slice(0, cut).join('')) && SECOND_HALVES.has(letters.slice(cut).join(''))) return true;
  }
  return false;
}

/** One run of letters in what was heard, lowercased, with where it sits in the words. */
interface HeardToken {
  readonly text: string;
  readonly start: number;
  readonly end: number;
}

function heardTokens(words: string): HeardToken[] {
  const tokens: HeardToken[] = [];
  let start: number | undefined;
  let index = 0;
  for (const character of words) {
    if (LETTER.test(character)) {
      if (start === undefined) start = index;
    } else if (start !== undefined) {
      tokens.push({ text: words.slice(start, index).toLowerCase(), start, end: index });
      start = undefined;
    }
    index += character.length;
  }
  if (start !== undefined) tokens.push({ text: words.slice(start).toLowerCase(), start, end: words.length });
  return tokens;
}

/** How many tokens from `position` on spell the name, undefined when they do not. */
function nameLength(tokens: readonly HeardToken[], position: number, edge: boolean): number | undefined {
  if (edge && EDGE_SPELLINGS.has(tokens[position]?.text ?? '')) return 1;
  let joined = '';
  for (let length = 1; length <= MOST_NAME_TOKENS && position + length <= tokens.length; length += 1) {
    joined += tokens[position + length - 1]?.text ?? '';
    if (isWakeSpelling(joined)) return length;
  }
  return undefined;
}

/** Whether a full stop, a question mark or a comma sits between two tokens, the way somebody sets a name apart. */
function setApart(before: HeardToken, token: HeardToken, words: string): boolean {
  return [...words.slice(before.end, token.start)].some((character) => NAME_SET_APART_BY.has(character));
}

/** Where the first call sits, its repeats included so "Memnox Manox" is one call. */
function firstCall(tokens: readonly HeardToken[], words: string): { first: number; after: number } | undefined {
  for (let position = 0; position < tokens.length; position += 1) {
    const previous = tokens[position - 1];
    const token = tokens[position];
    if (token === undefined) continue;
    const atEnd = position === tokens.length - 1 && (previous === undefined || setApart(previous, token, words));
    const length = nameLength(tokens, position, position < LEADING_EDGE_TOKENS || atEnd);
    if (length === undefined) continue;
    let after = position + length;
    for (;;) {
      const again = after < tokens.length ? nameLength(tokens, after, true) : undefined;
      if (again === undefined) break;
      after += again;
    }
    return { first: position, after };
  }
  return undefined;
}

function restAfter(words: string, tokens: readonly HeardToken[], after: number): string {
  const end = tokens[after - 1]?.end ?? 0;
  const rest = words.slice(end);
  const from = rest.search(LETTER_OR_NUMBER);
  return from === -1 ? '' : rest.slice(from).trim();
}

function wordsBefore(words: string, at: number): number {
  return words.slice(0, at).split(/\s+/).filter((word) => word !== '').length;
}

/**
 * What followed "Memnox" when the person called it by name, empty when the name was said alone, and
 * undefined when it was not said. With `spoken`, its own recent sentences are taken off first, so a
 * greeting it says with "Memnox" in it never wakes it.
 */
export function afterWakeWord(words: string, spoken?: string): string | undefined {
  const heard = spoken === undefined ? words : withoutEchoRuns(words, spoken);
  const tokens = heardTokens(heard);
  const call = firstCall(tokens, heard);
  if (call === undefined) return undefined;
  if (call.after >= tokens.length) return '';
  return restAfter(heard, tokens, call.after);
}

/** Only its name, or "hey" and its name: somebody getting its attention rather than asking. */
export function nameAlone(words: string): boolean {
  const rest = afterWakeWord(words);
  if (rest !== '') return false;
  const tokens = heardTokens(words);
  const call = firstCall(tokens, words);
  if (call === undefined) return false;
  return wordsBefore(words, tokens[call.first]?.start ?? 0) < GREETING_WORDS_BEFORE_NAME;
}

/** What they said with "Memnox" taken off the front, since calling it by name mid conversation is a greeting. */
export function withoutLeadingName(words: string): string {
  const tokens = heardTokens(words);
  const call = firstCall(tokens, words);
  if (call === undefined || call.after >= tokens.length) return words;
  if (wordsBefore(words, tokens[call.first]?.start ?? 0) >= GREETING_WORDS_BEFORE_NAME) return words;
  return restAfter(words, tokens, call.after);
}

/**
 * What they said less its name called at the end, set apart by a mark or said twice, as in "why so
 * slow? Memnox Memnox"; "start a session in Memnox" names a place so it stays.
 */
export function withoutTrailingName(words: string): string {
  const tokens = heardTokens(words);
  let cut = tokens.length;
  let names = 0;
  let kept: number | undefined;
  while (cut > 0) {
    let found: number | undefined;
    // The longest spelling first, so "ma'am Knox" goes whole rather than as a bare "Knox".
    for (let length = Math.min(MOST_NAME_TOKENS, cut); length >= 1; length -= 1) {
      if (nameLength(tokens, cut - length, true) === length) {
        found = length;
        break;
      }
    }
    if (found === undefined) break;
    cut -= found;
    names += 1;
    if (cut <= 0) break;
    const before = tokens[cut - 1];
    const token = tokens[cut];
    if (before === undefined || token === undefined) break;
    // A mark sets the name apart; with none anywhere, the name twice in a row is still somebody calling.
    if (setApart(before, token, words) || (names > 1 && kept === undefined)) kept = cut;
  }
  if (kept === undefined) return words;
  const before = words.slice(0, tokens[kept]?.start ?? 0).trim();
  return before.endsWith(',') ? before.slice(0, -1) : before;
}
