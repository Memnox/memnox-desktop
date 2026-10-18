/**
 * When somebody has finished saying something, ported from the Mac's `TurnTaking.swift`. A short reply
 * is answered almost at once, a question a breath later, and somebody trailing off on "and" or "so" is
 * waited for longest, since answering half a thought means cancelling it and starting again.
 */

/** Words people trail off on, which mean they have not finished even when they pause. */
const TRAILING_WORDS = new Set([
  'uh', 'um', 'er', 'erm', 'hmm', 'so', 'and', 'but', 'or', 'like', 'the', 'a', 'an', 'to', 'of', 'with', 'because',
  'i', 'my', 'your', 'our', 'was', 'is', 'are', 'that', 'if', 'when', 'about', 'for', 'in', 'on', 'at', 'then', 'which', 'we', "it's", 'its',
]);

/** The openings of a request, which said alone are somebody gathering the rest of it. */
const REQUEST_OPENINGS = new Set([
  'can you', 'could you', 'would you', 'will you', 'can i', 'could i', 'can we', 'could we', 'do you',
  'is there', 'are there', 'what about', 'show me', 'tell me', 'i want', 'i need', 'i want you to', 'please',
  'okay so', 'ok so', 'so can you', 'and can you', 'hey', 'hey can you',
]);

/** Polite openings that need both a verb and what it acts on, so "can you open" is half a request. */
const POLITE_OPENINGS = new Set(['can you', 'could you', 'would you', 'will you', 'can we', 'could we', 'please', 'so can you', 'okay so can you']);

/** Words a request or a question opens with, so a short line opening with one is somebody asking. */
const ASKING_WORDS = new Set([
  'can', 'could', 'would', 'will', 'do', 'does', 'did', 'is', 'are', 'was', 'what', 'which', 'who', 'how',
  'why', 'where', 'when', 'please', 'open', 'show', 'tell', 'close', 'start', 'stop', 'run', 'make', 'ask',
  'check', 'give', 'let', 'i', 'so', 'okay', 'ok',
]);

/** The pauses that end what somebody is saying, in milliseconds, from a one word answer to somebody still thinking. */
export const SPEECH_PAUSE = {
  stillThinking: 3_000,
  shortReply: 800,
  finished: 1_400,
  finishedLong: 2_000,
  unmarked: 2_200,
  unmarkedLong: 2_600,
} as const;

const TRAILING_MARKS = [',', '...', '…'];
const FINISHING_MARKS = ['?', '.', '!'];
/** "Yes.", "Go ahead." or "Open it.": an answer, not the start of a thought. */
const SHORT_REPLY = 3;
/** Past this many words somebody is explaining, and pauses between their sentences. */
const LONG_THOUGHT = 8;

/** How long a pause ends what somebody is saying, in milliseconds. */
export function endOfSpeechPause(words: string): number {
  const trimmed = words.trim().toLowerCase();
  const spoken = trimmed.split(/[^\p{L}']+/u).filter((word) => word !== '');
  const last = spoken[spoken.length - 1] ?? '';
  const trailing = TRAILING_MARKS.some((mark) => trimmed.endsWith(mark));
  if (trailing || TRAILING_WORDS.has(last)) return SPEECH_PAUSE.stillThinking;
  if (REQUEST_OPENINGS.has(spoken.join(' '))) return SPEECH_PAUSE.stillThinking;
  // An opening and one word, like "can you open", names what to do and not yet what to do it to.
  if (spoken.length > 1 && POLITE_OPENINGS.has(spoken.slice(0, -1).join(' '))) return SPEECH_PAUSE.stillThinking;
  const long = spoken.length > LONG_THOUGHT;
  const answering = !ASKING_WORDS.has(spoken[0] ?? '');
  if (FINISHING_MARKS.some((mark) => trimmed.endsWith(mark))) {
    if (spoken.length <= SHORT_REPLY && answering) return SPEECH_PAUSE.shortReply;
    return long ? SPEECH_PAUSE.finishedLong : SPEECH_PAUSE.finished;
  }
  return long ? SPEECH_PAUSE.unmarkedLong : SPEECH_PAUSE.unmarked;
}

/**
 * Two stretches of what was heard as one sentence, with the space the recognizer leaves out between
 * segments, so "so." and "Is there" never read as "so.Is there", and a lone mark joins the words before it.
 */
export function joinedSpeech(first: string, second: string): string {
  return [first, second]
    .map((part) => part.trim())
    .filter((part) => part !== '')
    .join(' ')
    .replace(/\s+([?!,;:])/g, '$1')
    .replace(/([?!])[?!]+/g, '$1');
}

/** How long a pause is before the words so far are sent as a guess, well short of any end of speech. */
export const GUESS_AFTER_PAUSE_MS = 350;

/**
 * Whether a pause this long is worth starting the answer on, ported from `mayGuess`: never while they
 * trail off on a word like "and", and only while the pause has not yet ended what they are saying.
 */
export function mayGuess(words: string, pausedForMs: number): boolean {
  const ending = endOfSpeechPause(words);
  return /\p{L}/u.test(words) && ending < SPEECH_PAUSE.stillThinking && pausedForMs >= GUESS_AFTER_PAUSE_MS && pausedForMs < ending;
}
